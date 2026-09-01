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
 * Tools (interface deliberately split by responsibility so the model can't
 * pick the wrong tool or forget to fork a ticket off the feature branch):
 *
 *   worktree_list             GET    /experimental/worktree
 *   worktree_create_feature   POST   /experimental/worktree  {name, base?}
 *                             base optional, defaults to "develop".
 *                             Use ONLY for the top-level feature worktree
 *                             (opencode/feat-<slug>).
 *   worktree_create_ticket    POST   /experimental/worktree  {name, base}
 *                             base REQUIRED and must match ^opencode/feat-.
 *                             Caller passes the `branch` field returned by
 *                             worktree_create_feature. Guarantees tickets
 *                             always fork off the feature branch, never off
 *                             develop or a previous ticket.
 *   worktree_delete           DELETE /experimental/worktree  {directory}
 *   worktree_reset            POST   /experimental/worktree/reset {directory}
 *
 * Every call carries ?directory=<context.directory> to scope the operation
 * to the calling project. All HTTP work goes through one shared `wtFetch`
 * helper; per-tool code is just arg validation + body shape.
 */

const DEFAULT_BASE = "develop";
const FEATURE_BRANCH_PATTERN = /^opencode\/feat-/;

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

  function clientError(msg) {
    return JSON.stringify({ ok: false, status: 0, body: msg });
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

      worktree_create_feature: {
        description:
          "Create a FEATURE worktree (opencode/feat-<slug>) for the current project. Forks off `base` (defaults to 'develop'). Use this ONLY for the top-level feature branch. The response includes a `branch` field (e.g. 'opencode/feat-<name>') — capture it and pass it as `feature_branch` to worktree_create_ticket when creating ticket worktrees off this feature.",
        args: {
          name: {
            type: "string",
            description:
              "Required. Feature slug, e.g. 'test' or 'billing-flow'. The plugin auto-prefixes 'feat-' if not already present, so the created branch is always 'opencode/feat-<name>' (idempotent — 'feat-x' is left as-is).",
          },
          base: {
            type: "string",
            description:
              "Base branch to fork from. Pass an empty string to use the default 'develop'. Use 'main' or another long-lived branch if your repo does not use 'develop'.",
          },
        },
        async execute(args, context) {
          const rawName = args && args.name;
          if (!rawName) {
            return clientError(
              "worktree_create_feature requires a non-empty 'name' argument.",
            );
          }
          const name = rawName.startsWith("feat-") ? rawName : `feat-${rawName}`;
          const base = (args && args.base) || DEFAULT_BASE;
          const r = await wtFetch(
            "/experimental/worktree",
            { method: "POST", body: JSON.stringify({ name, base }) },
            context,
          );
          return JSON.stringify(r);
        },
      },

      worktree_create_ticket: {
        description:
          "Create a TICKET worktree that forks off an existing feature branch. REQUIRED: pass the `branch` field from a prior worktree_create_feature response as `feature_branch`. The plugin rejects any value that does not start with 'opencode/feat-' so tickets cannot accidentally be forked off develop, main, or a sibling ticket. Always call worktree_create_feature first and pass its exact `branch` field here.",
        args: {
          feature_branch: {
            type: "string",
            description:
              "Required. The opencode/feat-<slug> branch returned by worktree_create_feature. Must start with 'opencode/feat-'. Pass the EXACT branch name from the create response — do not derive or guess it.",
          },
          name: {
            type: "string",
            description:
              "Required. Ticket worktree name, e.g. 'ticket-1-test-abcd'.",
          },
        },
        async execute(args, context) {
          const featureBranch = args && args.feature_branch;
          const name = args && args.name;
          if (!featureBranch) {
            return clientError(
              "worktree_create_ticket requires a non-empty 'feature_branch' argument — pass the 'branch' field returned by worktree_create_feature.",
            );
          }
          if (!name) {
            return clientError(
              "worktree_create_ticket requires a non-empty 'name' argument.",
            );
          }
          if (!FEATURE_BRANCH_PATTERN.test(featureBranch)) {
            return clientError(
              `worktree_create_ticket: feature_branch must start with 'opencode/feat-' — got '${featureBranch}'. Pass the branch returned by worktree_create_feature, not develop or main.`,
            );
          }
          const r = await wtFetch(
            "/experimental/worktree",
            {
              method: "POST",
              body: JSON.stringify({ name, base: featureBranch }),
            },
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
            return clientError(
              "worktree_delete requires a non-empty 'directory' argument.",
            );
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
            return clientError(
              "worktree_reset requires a non-empty 'directory' argument.",
            );
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