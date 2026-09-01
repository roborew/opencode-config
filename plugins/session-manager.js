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
 *                     (scope defaults to "global"; pass scope:"directory" + directory to
 *                      ask the server to filter — advisory; the session-manager subagent
 *                      also filters client-side defensively)
 *   session_notify   POST /session/{id}/prompt_async                resolves target then
 *                     posts {parts:[{type:"text", text:msg}], agent?} as a 204-ack async prompt
 *                     (when sessionID is omitted, scope defaults to "global" so the
 *                     directory-resolve sees worktree-bound sessions even when the
 *                     calling agent's `context.directory` differs from the target dir)
 *
 * Mutual exclusion on `session_notify`: pass EITHER `sessionID` (exact
 * target) OR `directory` (resolve to newest no-parent session in that
 * worktree). When `sessionID` is provided, `GET /session` (unfiltered, scope:
 * "global") is consulted only to verify the id exists and (if `args.directory`
 * was also passed) that the binding matches — no silent create on miss.
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
          "Create a new session for the current project (or a project directory). Returns the new session id. Use when a fresh GUI session is needed (e.g. kicking a coder into a newly-created ticket worktree). For the common kickoff path prefer the session-manager subagent — it composes list-then-create and notification as one atomic action. The `directory` arg is forwarded to the server as `?directory=...` on the POST URL and binds the new session to that worktree directory; without it, the server binds to the calling project's directory.",
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
          return JSON.stringify(r);
        },
      },

      session_list: {
        description:
          "List sessions. Returns the sessions array (each entry includes id, directory, parentID, title, updatedAt, ...). Default scope is `global` (unfiltered) — the session-manager subagent filters client-side against `args.directory` defensively. Pass `scope: \"directory\"` to also forward `?directory=...` to the server (advisory; some server builds ignore it).",
        args: {
          directory: {
            type: "string",
            description:
              "Optional project directory scope. When set with `scope: \"directory\"`, the server attempts to filter sessions to that directory (advisory — the session-manager subagent filters again on the client).",
          },
          scope: {
            type: "string",
            description:
              "Optional. `\"global\"` (default) returns every session the server knows about; `\"directory\"` forwards `?directory=<args.directory>` to the server. The session-manager subagent always filters client-side.",
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
          "Inject an async message into a session (POST /session/{id}/prompt_async). Resolves the target session id from EITHER `sessionID` (exact) OR `directory` (newest no-parent session bound to that worktree, picked from a global-scope list — the previous scoped-list path was the source of the self-resolve bug against worktree dirs). Passing both, or neither, is a client error. Returns {ok, admitted, session_id, target_directory, agent, directory_match, agent_match, manualRecovery} where `admitted` is true on HTTP 204 (the success contract for /prompt_async). When `sessionID` is provided but the server has no entry with that id, returns `error: \"session_not_found\"` (hard stop — no silent create).",
        args: {
          sessionID: {
            type: "string",
            description:
              "Exact session id to inject into. Mutually exclusive with `directory`. When provided, the plugin asserts the id appears in `GET /session` (scope: global) — a miss returns `error: \"session_not_found\"`, never silently creates.",
          },
          directory: {
            type: "string",
            description:
              "Absolute worktree directory. The newest no-parent session bound to this directory is selected from a global-scope list (`GET /session`, no `?directory=` — the previous scoped path was the self-resolve bug). Mutually exclusive with `sessionID`.",
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
            description:
              "Optional. For directory-mode resolution only — `\"global\"` (default) unfiltered list, `\"directory\"` filters by `?directory=`. Ignored in `sessionID` mode (always global so a fresh id is always findable).",
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

          // sessionID mode: assert the id exists in the global list (no scoped listing
          // — silent scoping caused the self-resolve bug against worktree dirs).
          if (sessionID) {
            const list = await smFetch(
              "/session",
              { method: "GET" },
              context,
            );
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
            // directory-mode resolve. Default scope is `global`; caller may opt into
            // scoped listing by passing scope:"directory" + directory.
            const useScoped =
              args &&
              args.scope === "directory" &&
              typeof directory === "string" &&
              directory.length > 0;
            const listInit = { method: "GET" };
            if (useScoped) listInit.query = { directory };
            const list = await smFetch("/session", listInit, context);
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
    },
  };
};
