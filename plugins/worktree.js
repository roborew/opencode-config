/**
 * Worktree plugin — MINIMAL BASELINE.
 * Stripped of v2-client construction, zod schemas, brief files, kickoff
 * orchestration, polling, and all helper modules. Single tool that hits
 * /experimental/worktree via plain fetch using ctx.serverUrl + Basic auth.
 *
 * Re-add features in phases per the bug-isolation plan; verify each one
 * registers in /experimental/tool/ids before adding the next.
 */

export const WorktreePlugin = async (ctx) => {
  console.log(
    "[worktree-plugin] minimal baseline loaded; ctx keys:",
    Object.keys(ctx),
  );
  const baseUrl = String(ctx.serverUrl).replace(/\/+$/, "");
  const auth =
    "Basic " +
    Buffer.from(
      (process.env.OPENCODE_SERVER_USERNAME || "opencode") +
        ":" +
        (process.env.OPENCODE_SERVER_PASSWORD || "opencode"),
    ).toString("base64");

  async function wtFetch(path, init = {}) {
    const url = `${baseUrl}${path}`;
    const res = await fetch(url, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        Authorization: auth,
        ...(init.headers || {}),
      },
    });
    const body = await res.text();
    return { ok: res.ok, status: res.status, body };
  }

  return {
    tool: {
      worktree_ping: {
        description:
          "List worktrees under the current project directory. Baseline probe.",
        args: {},
        async execute(_args, context) {
          const dir = context && context.directory;
          const qs = dir ? `?directory=${encodeURIComponent(dir)}` : "";
          const r = await wtFetch(`/experimental/worktree${qs}`, {
            method: "GET",
          });
          return JSON.stringify(r);
        },
      },
    },
  };
};
