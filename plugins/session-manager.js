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
 *   session_list     GET  /session                                  {directory?}
 *   session_notify   POST /session/{id}/prompt_async                resolves target then
 *                     posts {parts:[{type:"text", text:msg}], agent?} as a 204-ack async prompt
 *
 * Mutual exclusion on `session_notify`: pass EITHER `sessionID` (exact
 * target) OR `directory` (resolve to newest no-parent session in that
 * worktree, with an unfiltered fallback when the scoped list returns empty
 * — server builds vary on whether `?directory=` is a hard filter).
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
    const dir = context && context.directory;
    const qs = dir ? `?directory=${encodeURIComponent(dir)}` : "";
    const url = `${baseUrl}${path}${qs}`;
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
          "Create a new session for the current project (or a project directory). Returns the new session id. Use when a fresh GUI session is needed (e.g. kicking a coder into a newly-created ticket worktree). For the common kickoff path prefer the session-manager subagent — it composes list-then-create and notification as one atomic action.",
        args: {
          directory: {
            type: "string",
            description:
              "Optional absolute project directory for the session. Defaults to the calling project's directory.",
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
          const r = await smFetch(
            "/session",
            { method: "POST", body: JSON.stringify(body) },
            context,
          );
          return JSON.stringify(r);
        },
      },

      session_list: {
        description:
          "List sessions visible to the calling project. Returns the sessions array (each entry includes id, directory, parentID, title, updatedAt, ...). The server may filter by directory when provided; the session-manager subagent does an unfiltered fallback when the scoped list returns empty and matches client-side, so callers can ignore directory filtering concerns.",
        args: {
          directory: {
            type: "string",
            description:
              "Optional project directory scope. When set, the server attempts to filter sessions to that directory.",
          },
        },
        async execute(args, context) {
          const r = await smFetch("/session", { method: "GET" }, context);
          return JSON.stringify(r);
        },
      },

      session_notify: {
        description:
          "Inject an async message into a session (POST /session/{id}/prompt_async). Resolves the target session id from EITHER `sessionID` (exact) OR `directory` (newest no-parent session in that worktree, with an unfiltered fallback) — passing both, or neither, is a client error. Returns {ok, admitted, session_id, target_directory, agent, manualRecovery} where `admitted` is true on HTTP 204 (the success contract for /prompt_async).",
        args: {
          sessionID: {
            type: "string",
            description:
              "Exact session id to inject into. Mutually exclusive with `directory`.",
          },
          directory: {
            type: "string",
            description:
              "Absolute worktree directory. The newest no-parent session under this directory is selected (unfiltered fallback when the scoped list is empty). Mutually exclusive with `sessionID`.",
          },
          agent: {
            type: "string",
            description:
              "Optional agent to bind the prompt to (e.g. 'coder', 'orchestrate'). Forwarded to /prompt_async unchanged.",
          },
          message: {
            type: "string",
            description:
              "Required. The text to inject into the session — sent as a single text part.",
          },
        },
        async execute(args, context) {
          const sessionID = args && args.sessionID;
          const directory = args && args.directory;
          const message = args && args.message;

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

          let targetID = sessionID;
          let targetDir = directory || null;

          if (!targetID) {
            const listArgs = { directory };
            const scoped = await smFetch(
              "/session",
              { method: "GET" },
              context,
            );
            let sessions = scoped.ok && Array.isArray(scoped.body) ? scoped.body : [];
            let scopedHit =
              sessions.some(
                (s) => s && s.directory && s.directory === directory,
              );
            if (!scopedHit) {
              const unfiltered = await smFetch(
                "/session",
                { method: "GET" },
                context,
              );
              if (
                unfiltered.ok &&
                Array.isArray(unfiltered.body) &&
                unfiltered.body.length > 0
              ) {
                sessions = unfiltered.body;
              }
            }
            const chosen = resolveNewestNoParent(sessions, directory);
            if (!chosen || !chosen.id) {
              const manualRecovery =
                `No session found in directory ${directory}. ` +
                `Open the Desktop GUI session for that worktree and type any message — ` +
                `the bootstrap (ticket-lifecycle §0) reconstructs from GitHub.`;
              return JSON.stringify({
                ok: false,
                admitted: false,
                status: 404,
                session_id: null,
                target_directory: directory,
                agent: (args && args.agent) || null,
                error: "no_session_in_directory",
                manualRecovery,
              });
            }
            targetID = chosen.id;
            targetDir = chosen.directory || directory;
          }

          const payload = {
            parts: [{ type: "text", text: message }],
          };
          if (args && args.agent) payload.agent = args.agent;

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
            agent: (args && args.agent) || null,
            error: r.ok ? null : r.body,
            manualRecovery: r.ok
              ? null
              : `curl -u "${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || "opencode"}" -H 'Content-Type: application/json' -d '${JSON.stringify(payload).replace(/'/g, "'\\''")}' "${baseUrl}/session/${targetID}/prompt_async?directory=${encodeURIComponent(targetDir || "")}"`,
          });
        },
      },
    },
  };
};
