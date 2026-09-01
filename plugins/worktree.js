/**
 * Worktree plugin — CRUD tools over the opencode server's
 * /experimental/worktree API.
 *
 * Built on the proven minimal baseline: plain fetch, ctx.serverUrl URL
 * discovery, env-based Basic auth read at call time, pass-through
 * {ok, status, body} error envelope. No SDK imports, no zod schemas, no
 * kickoff machinery (brief files, session polling, promptAsync) — those are
 * deferred to their own stages.
 *
 * Tools:
 *   worktree_list   GET    /experimental/worktree
 *   worktree_create POST   /experimental/worktree        {name, base}
 *   worktree_delete DELETE /experimental/worktree        {directory}
 *   worktree_reset  POST   /experimental/worktree/reset  {directory}
 *
 * Every call carries ?directory=<context.directory> to scope the operation to
 * the calling project. worktree_create defaults `base` to "develop".
 */

const DEFAULT_BASE = "develop";

export const WorktreePlugin = async (ctx) => {
  console.log(
    "[worktree-plugin] CRUD tools loaded; ctx keys:",
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

  async function wtFetch(path, init = {}, context = undefined) {
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

  return {
    tool: {
      worktree_list: {
        description:
          "List the git worktrees registered for the current project. Takes no arguments. Returns the array of worktree directory paths from the opencode server.",
        args: {},
        async execute(_args, context) {
          const r = await wtFetch(
            "/experimental/worktree",
            { method: "GET" },
            context,
          );
          return JSON.stringify(r);
        },
      },

      worktree_create: {
        description:
          "Create a new git worktree for the current project. Use this to set up an isolated checkout for a feature or ticket. Returns the created worktree's directory and branch.",
        args: {
          name: {
            type: "string",
            description:
              "Required. Worktree name / branch slug, e.g. 'feat-billing-flow'.",
          },
          base: {
            type: "string",
            description:
              "Base branch to create the worktree from. Optional — pass an empty string to use the default 'develop'.",
          },
        },
        async execute(args, context) {
          const name = args && args.name;
          if (!name) {
            return JSON.stringify({
              ok: false,
              status: 0,
              body: "worktree_create requires a non-empty 'name' argument.",
            });
          }
          const base = (args && args.base) || DEFAULT_BASE;
          const r = await wtFetch(
            "/experimental/worktree",
            { method: "POST", body: JSON.stringify({ name, base }) },
            context,
          );
          return JSON.stringify(r);
        },
      },

      worktree_delete: {
        description:
          "Delete an existing git worktree by its absolute directory path. Use worktree_list first to get the exact path. The server rejects paths outside the worktree store.",
        args: {
          directory: {
            type: "string",
            description:
              "Required. Absolute path of the worktree to remove, exactly as returned by worktree_list.",
          },
        },
        async execute(args, context) {
          const directory = args && args.directory;
          if (!directory) {
            return JSON.stringify({
              ok: false,
              status: 0,
              body: "worktree_delete requires a non-empty 'directory' argument.",
            });
          }
          const r = await wtFetch(
            "/experimental/worktree",
            { method: "DELETE", body: JSON.stringify({ directory }) },
            context,
          );
          return JSON.stringify(r);
        },
      },

      worktree_reset: {
        description:
          "Reconcile the opencode server's state for an existing worktree, e.g. after manual git operations left it out of sync. Does not delete the worktree.",
        args: {
          directory: {
            type: "string",
            description:
              "Required. Absolute path of the worktree to reset, exactly as returned by worktree_list.",
          },
        },
        async execute(args, context) {
          const directory = args && args.directory;
          if (!directory) {
            return JSON.stringify({
              ok: false,
              status: 0,
              body: "worktree_reset requires a non-empty 'directory' argument.",
            });
          }
          const r = await wtFetch(
            "/experimental/worktree/reset",
            { method: "POST", body: JSON.stringify({ directory }) },
            context,
          );
          return JSON.stringify(r);
        },
      },
    },
  };
};
