/**
 * Session-manager plugin — thin messaging layer over the opencode server's
 * /session* API. Sits beside `plugins/worktree.js` and mirrors its
 * structure (env-based Basic auth, ctx.serverUrl URL, plain JSON Schema
 * args, pass-through {ok, status, body} envelope) so the two plugins read
 * like siblings.
 *
 * Three tools, each fetch-only — no file writes, no orchestration logic
 * lives here; the `session-manager` subagent (agents/session-manager.md)
 * owns the kickoff / notify choreography on top of these primitives.
 *
 *   session_create   POST /session                                  {directory?, agent?, title?}
 *                     (directory is forwarded as `?directory=...` on the URL — the
 *                      opencode server's POST /session binds sessions to a directory
 *                      via the query string, not the body)
*   session_list     GET  /session                                  {scope?, directory?}
 *                     (no scope arg = no query string, server returns everything the calling
 *                      project knows about; pass scope:"directory" + directory to forward
 *                      `?directory=...` to the server — advisory; the session-manager subagent
 *                      also filters client-side defensively)
 *   session_notify   POST /session/{id}/prompt_async                resolves target then
 *                     posts {parts:[{type:"text", text:msg}], agent?} as a 204-ack async prompt
 *                     (when sessionID is omitted, the list call has no query string so
 *                      directory-resolve sees worktree-bound sessions even when the
 *                      calling agent's `context.directory` differs from the target dir)
 *   session_delete   DELETE /session/{id}                            {sessionID?}
 *                     OR                                                    {directory?}
 *                     (mutual exclusion — same shape as session_notify; directory-mode
 *                      iterates the global list and deletes every session bound to
 *                      that directory, returning the per-id results)
 *
 * Mutual exclusion on `session_notify` / `session_delete`: pass EITHER `sessionID` (exact
 * target) OR `directory` (operate on every session bound to that directory).
 *
 * Listing un-scoping: `smFetch` no longer reads `context.directory` as an
 * implicit query string — the previous behaviour caused the
 * `session-manager.kickoff` self-resolve bug against worktree dirs.
 * `args.directory` + `args.scope` carry the intent explicitly now; the
 * session-manager subagent performs the global re-list + client-side filter.
 *
 * 204 void is the success contract on /prompt_async — `admitted` is keyed
 * on HTTP status, not body, matching the dev-loop-poller's silent curl.
 */

export const SessionManagerPlugin = async (ctx) => {
  console.log(
    "[session-manager-plugin] messaging tools loaded; ctx keys:",
    Object.keys(ctx),
  );
  const baseUrl = String(ctx.serverUrl).replace(/\/+$/, "");

  function authHeader() {
    return (
      "Basic " +
      Buffer.from(
        (process.env.OPENCODE_SERVER_USERNAME || "opencode") +
          ":" +
          (process.env.OPENCODE_SERVER_PASSWORD || "opencode"),
      ).toString("base64")
    );
  }

  async function smFetch(path, init = {}, context = undefined) {
    const qsFromInit =
      init && init.query && init.query.directory
        ? `?directory=${encodeURIComponent(init.query.directory)}`
        : "";
    const url = `${baseUrl}${path}${qsFromInit}`;
    const res = await fetch(url, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        Authorization: authHeader(),
        ...(init.headers || {}),
      },
    });
    const text = await res.text();
    let body;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = text;
    }
    return { ok: res.ok, status: res.status, body };
  }

  function clientError(msg) {
    return JSON.stringify({ ok: false, status: 0, body: msg });
  }

  function resolveNewestNoParent(sessions, directory) {
    if (!Array.isArray(sessions) || sessions.length === 0) return null;
    const inDir = sessions.filter(
      (s) => s && s.directory && s.directory === directory,
    );
    const pool = inDir.length > 0 ? inDir : sessions;
    const noParent = pool.filter((s) => !s.parentID && !s.parent_id);
    const candidates = noParent.length > 0 ? noParent : pool;
    candidates.sort((a, b) => {
      const ta = Date.parse(a.updatedAt || a.updated_at || 0) || 0;
      const tb = Date.parse(b.updatedAt || b.updated_at || 0) || 0;
      return tb - ta;
    });
    return candidates[0] || null;
  }

  return {
    tool: {
      session_create: {
        description:
          "Create a new session for the current project (or a project directory). Returns the new session id plus the server's stored `directory` and `agent` for the new session, inline in the same envelope as the create response (no follow-up list — eliminates the bind race that the previous global re-list had). Use when a fresh GUI session is needed (e.g. kicking a coder into a newly-created ticket worktree). For the common kickoff path prefer the session-manager subagent — it composes list-then-create and notification as one atomic action. The `directory` arg is forwarded to the server as `?directory=...` on the POST URL and binds the new session to that worktree directory; without it, the server binds to the calling project's directory. Returns {ok, status, body, session_id, target_directory, agent, requested_directory, requested_agent, directory_match, agent_match}; `directory_match` is `false` when the caller passed a `directory` and the server returned a different one (or none) — the session-manager subagent surfaces this as a tripwire instead of silently admitting. Also returns `bind_failed: true` whenever either `directory_match` or `agent_match` is `false`; the orchestrator hard-stops on `bind_failed: true` rather than admitting on `admitted`.",
        args: {
          directory: {
            type: "string",
            description:
              "Optional absolute project directory for the session. Forwarded as `?directory=...` to POST /session; defaults to the calling project's directory when omitted.",
          },
          agent: {
            type: "string",
            description:
              "Optional primary agent name to bind to the session (e.g. 'coder', 'orchestrate'). The session is created unbound if omitted.",
          },
          title: {
            type: "string",
            description:
              "Optional human-readable session title shown in the Desktop GUI.",
          },
        },
        async execute(args, context) {
          const body = {};
          if (args && args.agent) body.agent = args.agent;
          if (args && args.title) body.title = args.title;
          const init = { method: "POST", body: JSON.stringify(body) };
          if (args && args.directory) init.query = { directory: args.directory };
          const r = await smFetch("/session", init, context);
          // Normalize the new-session payload across server response shapes — some
          // builds return the session directly, some wrap as {session}, some as
          // {sessions:[...]}, some as [...]. When the shape is unknown, every stored
          // field is null and directory_match / agent_match are conservative-false so
          // the caller hard-stops rather than silently admitting.
          const newSession = Array.isArray(r.body) ? r.body[0]
                           : r.body && Array.isArray(r.body.sessions) ? r.body.sessions[0]
                           : r.body && r.body.session && typeof r.body.session === "object" ? r.body.session
                           : r.body && typeof r.body === "object" && r.body.id ? r.body
                           : null;
          const storedDirectory = newSession ? (newSession.directory ?? newSession.directory) : null;
          const storedAgent     = newSession ? (newSession.agent ?? newSession.agent) : null;
          const sessionId       = newSession ? (newSession.id ?? newSession.id) : null;
          const requestedDirectory = (args && args.directory) || null;
          const requestedAgent     = (args && args.agent) || null;
          const directoryMatch = !!(requestedDirectory && storedDirectory && storedDirectory === requestedDirectory);
          const agentMatch     = !!(requestedAgent && storedAgent && storedAgent === requestedAgent);
          return JSON.stringify({
            ...r,
            session_id: sessionId,
            target_directory: storedDirectory,
            agent: storedAgent || requestedAgent,
            requested_directory: requestedDirectory,
            requested_agent: requestedAgent,
            directory_match: directoryMatch,
            agent_match: agentMatch,
            bind_failed: !directoryMatch || !agentMatch,
          });
        },
      },

      session_list: {
        description:
          "List sessions. Returns the sessions array. With no `scope` arg, sends `GET /session` (no query string) and the server returns everything the calling project knows about — the session-manager subagent filters client-side against `args.directory` defensively. With `scope: \"directory\"` + `directory`, also forwards `?directory=...` to the server (advisory; some server builds ignore it).",
        args: {
          directory: {
            type: "string",
            description:
              "Optional project directory scope. When set with `scope: \"directory\"`, the server attempts to filter sessions to that directory (advisory — the session-manager subagent filters again on the client).",
          },
          scope: {
            type: "string",
            enum: ["directory"],
            description:
              "Optional. `\"directory\"` forwards `?directory=<args.directory>` to the server; absence of `scope` means no query string (server returns everything). The session-manager subagent always filters client-side.",
          },
        },
        async execute(args, context) {
          const init = { method: "GET" };
          if (
            args &&
            args.scope === "directory" &&
            typeof args.directory === "string" &&
            args.directory.length > 0
          ) {
            init.query = { directory: args.directory };
          }
          const r = await smFetch("/session", init, context);
          return JSON.stringify(r);
        },
      },

      session_notify: {
        description:
          "Inject an async message into a session (POST /session/{id}/prompt_async). Resolves the target session id from EITHER `sessionID` (exact) OR `directory` (newest no-parent session bound to that worktree, picked from an unfiltered list — the previous scoped-list path was the source of the self-resolve bug against worktree dirs). Passing both, or neither, is a client error. Returns {ok, admitted, session_id, target_directory, agent, directory_match, agent_match, manualRecovery} where `admitted` is true on HTTP 204 (the success contract for /prompt_async). When `sessionID` is provided but the server has no entry with that id, returns `error: \"session_not_found\"` (hard stop — no silent create).",
        args: {
          sessionID: {
            type: "string",
            description:
              "Exact session id to inject into. Mutually exclusive with `directory`. When provided, the plugin asserts the id appears in `GET /session` (scope: global) — a miss returns `error: \"session_not_found\"`, never silently creates.",
          },
          directory: {
            type: "string",
            description:
              "Absolute worktree directory. The newest no-parent session bound to this directory is selected from an unfiltered list (`GET /session`, no `?directory=` — the previous scoped path was the self-resolve bug). Mutually exclusive with `sessionID`.",
          },
          agent: {
            type: "string",
            description:
              "Optional agent to bind the prompt to (e.g. 'coder', 'orchestrate'). Forwarded to /prompt_async unchanged. Also used for the `agent_match` check — `agent_match` is `true` when this value equals the session's stored `agent`/`agent` (either casing is accepted).",
          },
          message: {
            type: "string",
            description:
              "Required. The text to inject into the session — sent as a single text part.",
          },
          scope: {
            type: "string",
            enum: ["directory"],
            description:
              "Optional. For directory-mode resolution only — `\"directory\"` filters by `?directory=<args.directory>` to the server (advisory). Ignored in `sessionID` mode (always unfiltered so a fresh id is always findable).",
          },
        },
        async execute(args, context) {
          const sessionID = args && args.sessionID;
          const directory = args && args.directory;
          const message = args && args.message;
          const requestedAgent = (args && args.agent) || null;

          if (!message || typeof message !== "string") {
            return clientError(
              "session_notify requires a non-empty 'message' argument.",
            );
          }
          if (Boolean(sessionID) === Boolean(directory)) {
            return clientError(
              "session_notify requires exactly one of 'sessionID' or 'directory' (not both, not neither).",
            );
          }

          let targetID = sessionID || null;
          let targetDir = directory || null;
          let resolvedSession = null;

          function sessionAgent(s) {
            if (!s) return undefined;
            return s.agent !== undefined ? s.agent : s.agent;
          }
          function sessionDirectory(s) {
            if (!s) return undefined;
            return s.directory !== undefined ? s.directory : s.directory;
          }
          function agentMatches(s, agent) {
            if (!agent) return true;
            const stored = sessionAgent(s);
            return stored === undefined ? true : stored === agent;
          }
          function directoryMatches(s, dir) {
            if (!dir) return true;
            const stored = sessionDirectory(s);
            return stored === undefined ? true : stored === dir;
          }

          const manualRecoveryCurl = (id, dir) =>
            `curl -u "${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || "opencode"}" -H 'Content-Type: application/json' -d '${JSON.stringify({ parts: [{ type: "text", text: message }] }).replace(/'/g, "'\\''")}' "${baseUrl}/session/${encodeURIComponent(id)}/prompt_async?directory=${encodeURIComponent(dir || "")}"`;

          // EVENTUAL_CONSISTENCY_RETRY: server commits the POST /session row before it
          // surfaces in GET /session; a freshly-created id may not be findable for ~250-1000 ms.
          // We bound this with a 3-attempt / 250-500-1000 ms ladder; the caller (kickoff) also
          // waits 750 ms after create. Terminal failure shape is unchanged.
          const RETRY_DELAYS_MS = [250, 500, 1000];
          const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
          async function listWithRetry(listInit) {
            let last = null;
            for (let i = 0; i < RETRY_DELAYS_MS.length + 1; i++) {
              const list = await smFetch("/session", listInit, context);
              last = list;
              const sessions = list.ok && Array.isArray(list.body) ? list.body : [];
              if (sessions.length > 0) return list;
              if (i < RETRY_DELAYS_MS.length) await sleep(RETRY_DELAYS_MS[i]);
            }
            return last;
          }

          // sessionID mode: assert the id exists in the unfiltered list (no scoped listing
          // — silent scoping caused the self-resolve bug against worktree dirs).
          if (sessionID) {
            const list = await listWithRetry({ method: "GET" });
            const sessions =
              list.ok && Array.isArray(list.body) ? list.body : [];
            resolvedSession =
              sessions.find((s) => s && s.id === sessionID) || null;
            if (!resolvedSession) {
              return JSON.stringify({
                ok: false,
                admitted: false,
                status: 404,
                session_id: sessionID,
                target_directory: null,
                agent: requestedAgent,
                directory_match: false,
                agent_match: false,
                error: "session_not_found",
                manualRecovery: manualRecoveryCurl(sessionID, ""),
              });
            }
            targetDir = sessionDirectory(resolvedSession) || null;
            // If caller passed BOTH sessionID and directory (client error shape), also
            // flag a binding mismatch — the explicit id wins, but a mismatch is a sign
            // of caller misuse.
            if (directory && !directoryMatches(resolvedSession, directory)) {
              return JSON.stringify({
                ok: false,
                admitted: false,
                status: 409,
                session_id: sessionID,
                target_directory: targetDir,
                agent: requestedAgent,
                directory_match: false,
                agent_match: agentMatches(resolvedSession, requestedAgent),
                error: "ambiguous_target",
                manualRecovery: manualRecoveryCurl(sessionID, targetDir || ""),
              });
            }
          } else {
            // directory-mode resolve. Caller may opt into scoped listing by passing
            // scope:"directory" + directory; default is unfiltered.
            const useScoped =
              args &&
              args.scope === "directory" &&
              typeof directory === "string" &&
              directory.length > 0;
            // EVENTUAL_CONSISTENCY_RETRY: when the caller did not opt into scoped listing,
            // retry the unfiltered GET /session with the 250/500/1000 ladder. When the
            // caller DID opt into scoped listing, server presence was already claimed and
            // a miss is a real LIST_SCOPE_INCOMPLETE — no retry.
            const listInit = { method: "GET" };
            if (useScoped) listInit.query = { directory };
            const list = useScoped
              ? await smFetch("/session", listInit, context)
              : await listWithRetry(listInit);
            let sessions =
              list.ok && Array.isArray(list.body) ? list.body : [];
            // Client-side filter — defensive even when the server scopes, because
            // server `?directory=` behaviour varies by build and was the source of the
            // worktree-dir self-resolve bug.
            const inDir = sessions.filter((s) => directoryMatches(s, directory));
            const pool = inDir.length > 0 ? inDir : sessions;
            const chosen = resolveNewestNoParent(pool, directory);
            if (!chosen) {
              if (useScoped) {
                // Server indicated scoped presence but client-side resolver returned
                // null — surface rather than silently admitting.
                return JSON.stringify({
                  ok: false,
                  admitted: false,
                  status: 500,
                  session_id: null,
                  target_directory: directory,
                  agent: requestedAgent,
                  directory_match: false,
                  agent_match: true,
                  error: "list_scope_incomplete",
                  manualRecovery:
                    `Scoped list returned entries for ${directory} but ` +
                    `resolveNewestNoParent could not pick one. Open the Desktop ` +
                    `GUI session for that worktree and type any message — ` +
                    `the bootstrap (ticket-lifecycle §0) reconstructs from GitHub.`,
                });
              }
              return JSON.stringify({
                ok: false,
                admitted: false,
                status: 404,
                session_id: null,
                target_directory: directory,
                agent: requestedAgent,
                directory_match: false,
                agent_match: true,
                error: "no_session_in_directory",
                manualRecovery:
                  `No session found in directory ${directory}. ` +
                  `Open the Desktop GUI session for that worktree and type any message — ` +
                  `the bootstrap (ticket-lifecycle §0) reconstructs from GitHub.`,
              });
            }
            resolvedSession = chosen;
            targetID = chosen.id;
            targetDir = chosen.directory || directory;
          }

          const directoryMatch = directoryMatches(resolvedSession, targetDir);
          const agentMatch = agentMatches(resolvedSession, requestedAgent);

          const payload = {
            parts: [{ type: "text", text: message }],
          };
          if (requestedAgent) payload.agent = requestedAgent;

          const r = await smFetch(
            `/session/${encodeURIComponent(targetID)}/prompt_async`,
            { method: "POST", body: JSON.stringify(payload) },
            context,
          );
          const admitted = r.status === 204 || (r.ok && r.body == null);
          return JSON.stringify({
            ok: r.ok,
            admitted,
            status: r.status,
            session_id: targetID,
            target_directory: targetDir,
            agent: requestedAgent,
            directory_match: directoryMatch,
            agent_match: agentMatch,
            error: r.ok ? null : r.body,
            manualRecovery: r.ok
              ? null
              : manualRecoveryCurl(targetID, targetDir || ""),
          });
        },
      },

      session_delete: {
        description:
          "Delete one or more sessions. Pass EITHER `sessionID` (single target, exact) OR `directory` (deletes every session bound to that worktree directory, returning per-id results). Returns {ok, deleted: [{session_id, status}], not_found?: [session_id], error?, manualRecovery?} where `ok` is true when the server returned a 2xx for every targeted id (404s on individual ids in directory-mode are not fatal — they are reported in `not_found`). Set `force: true` in sessionID-mode to treat a 404 as success — for the orphan-cleanup case where the operator is racing the server's eventual consistency on a session they just created. Directory-mode's `not_found[]` already handles 404s gracefully; `force` does NOT change directory-mode behavior.",
        args: {
          sessionID: {
            type: "string",
            description:
              "Exact session id to delete. Mutually exclusive with `directory`.",
          },
          directory: {
            type: "string",
            description:
              "Absolute worktree directory. Every session whose `directory` matches this value is deleted (global list — the previous scoped-list path was the self-resolve bug). Mutually exclusive with `sessionID`.",
          },
          force: {
            type: "boolean",
            description:
              "Optional bool (default false). sessionID-mode only — when true, a 404 is treated as success (`ok: true, status: 200, forced_404: true`) instead of the failure envelope. Directory-mode is unaffected (its 404 path is already non-fatal via `not_found`).",
          },
        },
        async execute(args, context) {
          const sessionID = args && args.sessionID;
          const directory = args && args.directory;
          const force = !!(args && args.force);

          if (Boolean(sessionID) === Boolean(directory)) {
            return clientError(
              "session_delete requires exactly one of 'sessionID' or 'directory' (not both, not neither).",
            );
          }

          const auth = (() => {
            const u = process.env.OPENCODE_SERVER_USERNAME || "opencode";
            const p = process.env.OPENCODE_SERVER_PASSWORD || "opencode";
            return "Basic " + Buffer.from(`${u}:${p}`).toString("base64");
          })();

          async function deleteOne(id) {
            const url = `${baseUrl}/session/${encodeURIComponent(id)}`;
            const res = await fetch(url, {
              method: "DELETE",
              headers: { Authorization: auth },
            });
            const text = await res.text();
            let body;
            try {
              body = text ? JSON.parse(text) : null;
            } catch {
              body = text;
            }
            return { id, ok: res.ok, status: res.status, body };
          }

          if (sessionID) {
            const r = await deleteOne(sessionID);
            if (r.status === 404 && force) {
              return JSON.stringify({
                ok: true,
                status: 200,
                session_id: sessionID,
                forced_404: true,
                error: null,
                manualRecovery: null,
              });
            }
            const manualRecovery =
              r.status === 404
                ? `curl -u "${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || "opencode"}" -X DELETE "${baseUrl}/session/${encodeURIComponent(sessionID)}" — already gone, no action needed`
                : r.ok
                  ? null
                  : `curl -u "${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || "opencode"}" -X DELETE "${baseUrl}/session/${encodeURIComponent(sessionID)}"`;
            return JSON.stringify({
              ok: r.ok,
              status: r.status,
              session_id: sessionID,
              error: r.ok ? null : r.body,
              manualRecovery,
            });
          }

          // directory-mode: global list, client-side filter, delete each match.
          const list = await smFetch("/session", { method: "GET" }, context);
          const sessions =
            list.ok && Array.isArray(list.body) ? list.body : [];
          const inDir = sessions.filter(
            (s) =>
              s &&
              (s.directory === directory || s.directory === directory),
          );
          if (inDir.length === 0) {
            return JSON.stringify({
              ok: true,
              status: 200,
              directory,
              deleted: [],
              not_found: [],
              error: null,
              manualRecovery: null,
            });
          }
          const deleted = [];
          const not_found = [];
          const failures = [];
          for (const s of inDir) {
            const r = await deleteOne(s.id);
            if (r.ok) {
              deleted.push({ session_id: s.id, status: r.status });
            } else if (r.status === 404) {
              not_found.push(s.id);
            } else {
              failures.push({ session_id: s.id, status: r.status, body: r.body });
            }
          }
          const ok = failures.length === 0;
          return JSON.stringify({
            ok,
            status: ok ? 200 : failures[0].status,
            directory,
            deleted,
            not_found,
            failures,
            error: ok ? null : failures[0].body,
            manualRecovery: ok
              ? null
              : `curl -u "${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || "opencode"}" -X DELETE "${baseUrl}/session/${encodeURIComponent(failures[0].session_id)}"`,
          });
        },
      },
    },
  };
};
