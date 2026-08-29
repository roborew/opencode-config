/**
 * Worktree plugin — drives OpenCode's own `/experimental/worktree` API so
 * worktrees + sessions register in the Desktop GUI.
 *
 * Canonical source: opencode-config/plugins/worktree.js (this repo).
 * Deployed via:    opencode-config/plugins/ → ${OPENCODE_CONFIG_DIR}/plugins/
 *                  (entrypoint copies config-repo plugins into the runtime
 *                  plugin dir alongside server-side docker/plugins/*.js).
 *
 * IMPORTANT — which client to use:
 *   Plugins receive `ctx.client`, which is the **v1** OpencodeClient
 *   (@opencode-ai/sdk). The v1 client has NO `worktree` namespace. The
 *   `/experimental/worktree` endpoints live only on the **v2** client
 *   (@opencode-ai/sdk/v2). So this plugin builds its own v2 client pointed
 *   at `ctx.serverUrl` (loopback) with HTTP Basic Auth from
 *   OPENCODE_SERVER_USERNAME/PASSWORD — the same auth the in-process v1
 *   client carries automatically. Calling `ctx.client.worktree` (as a prior
 *   version did) is always undefined and made the plugin throw at init,
 *   silently dropping all four tools.
 *
 * Tool definitions use the `tool()` helper + Zod `args` (via `tool.schema`)
 * from `@opencode-ai/plugin` — the only shape OpenCode's plugin loader
 * registers (ToolDefinition). A `parameters` (JSON Schema) object is the
 * MCP-server shape, NOT a plugin ToolDefinition, and the loader will not
 * register it. `execute` returns a ToolResult (a JSON string here).
 *
 * Delete safety has two layers:
 *   1. The *********:4097 delete-guard proxy blocks DELETE whose body
 *      `directory` is under OPENCODE_APPS_DIR (only when called via the
 *      proxy — i.e. from the host). It does NOT guard calls from the
 *      in-process plugin, which talks to loopback directly.
 *   2. This plugin replicates `_is_protected_project_root` and refuses to
 *      delete any path under OPENCODE_APPS_DIR before forwarding.
 *
 * Mirrors opencode-server/docker/worktree-delete-guard.py:
 *   _is_worktree_path + _is_protected_project_root.
 */

import { spawn } from "node:child_process";
import { tool } from "@opencode-ai/plugin";
import { createOpencodeClient } from "@opencode-ai/sdk/v2";

const HOST_WT = (process.env.OPENCODE_WORKTREES_DIR || "").replace(/\/+$/, "");
const HOST_APPS = (process.env.OPENCODE_APPS_DIR || "").replace(/\/+$/, "");
// Same-path inside the container as the proxy uses (see worktree-delete-guard.py:CONTAINER_WT).
const CONTAINER_WT = "/var/opencode-xdg/opencode/worktree";

function isWorktreePath(path) {
  const p = (path || "").replace(/\/+$/, "");
  for (const root of [CONTAINER_WT, HOST_WT]) {
    if (root && (p === root || p.startsWith(root + "/"))) return true;
  }
  return false;
}

function isProtectedProjectRoot(path) {
  const p = (path || "").replace(/\/+$/, "");
  if (!p || isWorktreePath(p)) return false;
  if (!HOST_APPS) return false;
  return p === HOST_APPS || p.startsWith(HOST_APPS + "/");
}

function protectedRootReason(directory) {
  if (!directory) return null;
  const norm = String(directory).replace(/\/+$/, "");
  if (isProtectedProjectRoot(norm)) {
    return (
      `Refusing to delete project root ${norm} (would wipe the real checkout ` +
      `under OPENCODE_APPS_DIR). Only paths under the OpenCode worktree store ` +
      `(${CONTAINER_WT} or ${HOST_WT || "<unset>"}) can be deleted via worktree_delete.`
    );
  }
  return null;
}

// GUI recovery snippet — the Desktop UI talks to the same API, so a curl
// here is the manual fallback the user can run from their machine.
function guiRecovery({ method, name, directory }) {
  const host = process.env.OPENCODE_PROXY_HOST || "*********";
  const port = process.env.OPENCODE_PROXY_PORT || "4097";
  const user = process.env.OPENCODE_SERVER_USERNAME || "opencode";
  const pass = process.env.OPENCODE_SERVER_PASSWORD || "";
  const base = `http://${host}:${port}`;
  const auth = `${user}:${pass}`;
  if (method === "DELETE" && directory) {
    return `curl -sS -u '${auth}' -X DELETE '${base}/experimental/worktree' \\\n  -H 'Content-Type: application/json' \\\n  -d '{"directory":"${directory}"}'`;
  }
  if (method === "POST" && name) {
    return `curl -sS -u '${auth}' -X POST '${base}/experimental/worktree?directory=$PWD' \\\n  -H 'Content-Type: application/json' \\\n  -d '{"name":"${name}"}'`;
  }
  if (method === "GET") {
    return `curl -sS -u '${auth}' '${base}/experimental/worktree?directory=$PWD'`;
  }
  return `# no manual recovery snippet for ${method}`;
}

function fail(status, body, method, opts = {}) {
  return {
    ok: false,
    status: status ?? 0,
    body: body ?? null,
    error: opts.error || `worktree_${method.toLowerCase()} failed`,
    manualRecovery: guiRecovery({ method, ...opts }),
  };
}

// Build the v2 SDK client once at plugin init. The v1 ctx.client has no
// `worktree` namespace; the /experimental/worktree API is v2-only.
function buildV2Client(ctx) {
  const baseUrl = ctx && ctx.serverUrl && (ctx.serverUrl.origin || String(ctx.serverUrl));
  if (!baseUrl) return null;
  const user = process.env.OPENCODE_SERVER_USERNAME || "";
  const pass = process.env.OPENCODE_SERVER_PASSWORD || "";
  const headers = {};
  if (user) {
    headers.Authorization = "Basic " + Buffer.from(user + ":" + pass).toString("base64");
  }
  try {
    return createOpencodeClient({ baseUrl, headers });
  } catch (_err) {
    return null;
  }
}

// Fire-and-forget the system's sanctioned cleanup script after a successful
// delete. The plugin talks to loopback :4098 directly, bypassing the :4097
// delete-guard proxy that schedules rewrite-worktree-gitdirs.py remove, so this
// compensates. Best-effort and idempotent; never blocks the tool response.
function scheduleGitCleanup(directory, project) {
  if (!directory) return;
  const script = "/usr/local/bin/rewrite-worktree-gitdirs.py";
  try {
    const args = ["python3", script, "remove", "--directory", directory];
    if (project) args.push("--project", project);
    const child = spawn(args[0], args.slice(1), {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
  } catch (_) {
    /* best-effort */
  }
}

// Normalize a v2 RequestResult ({ data, error, request, response }) into the
// plugin's { ok, status, body } envelope. With throwOnError=false (default)
// HTTP errors do NOT throw — they arrive as { data: undefined, error }.
async function unwrap(promise, method, opts = {}) {
  try {
    const res = await promise;
    const status = res && res.response && res.response.status;
    if (!res || res.error != null || res.data === undefined) {
      return fail(
        status ?? 0,
        res && res.error != null ? res.error : null,
        method,
        { ...opts, error: `worktree_${method.toLowerCase()} returned status ${status ?? 0}` }
      );
    }
    return { ok: true, status: status ?? 200, body: res.data };
  } catch (err) {
    return fail(err?.status ?? 0, err?.body ?? String(err?.message || err), method, {
      ...opts,
      error: String(err?.message || err),
    });
  }
}

// Tools are registered unconditionally. If the v2 client could not be built,
// each execute returns a structured 503 with a manualRecovery curl — matching
// the worktree-manager failure contract (BLOCKED: WORKTREE_API_FAILED). We
// deliberately do NOT throw at plugin init: throwing would silently drop all
// four tools, so the subagent would not see `worktree_create` at all and would
// confabulate a "no MCP server" diagnosis (which is what happened).
function unavailable(method, opts = {}) {
  return JSON.stringify(
    fail(503, "v2 worktree client unavailable in this environment", method, {
      ...opts,
      error:
        "worktree plugin: could not build @opencode-ai/sdk/v2 client (ctx.serverUrl missing or createOpencodeClient failed) — tool registered but cannot reach /experimental/worktree",
    })
  );
}

export const WorktreePlugin = async (ctx) => {
  const v2 = buildV2Client(ctx);

  return {
    tool: {
      worktree_create: tool({
        description:
          "Create an OpenCode worktree under OPENCODE_WORKTREES_DIR via the /experimental/worktree API. Branch is auto-prefixed opencode/<name>. After create, the worktree appears in the Desktop GUI and a session is auto-started.",
        args: {
          name: tool.schema
            .string()
            .describe(
              "Worktree name (no slashes). Convention: feat-<slug> or ticket-<issue>-<slug>."
            ),
        },
        async execute({ name }, context) {
          if (!v2) return unavailable("POST", { name });
          if (!name || typeof name !== "string" || name.includes("/")) {
            return JSON.stringify(
              fail(0, null, "POST", {
                name,
                error: "worktree_create: `name` is required and must not contain '/'",
              })
            );
          }
          return JSON.stringify(
            await unwrap(
              v2.worktree.create({
                directory: (context && context.directory) || undefined,
                worktreeCreateInput: { name },
              }),
              "POST",
              { name }
            )
          );
        },
      }),

      worktree_list: tool({
        description:
          "List worktrees under the current project directory. Returns string[] of worktree directory paths.",
        args: {},
        async execute(_args, context) {
          if (!v2) return unavailable("GET");
          return JSON.stringify(
            await unwrap(
              v2.worktree.list({ directory: (context && context.directory) || undefined }),
              "GET"
            )
          );
        },
      }),

      worktree_delete: tool({
        description:
          "Delete an OpenCode worktree by directory path. Self-guards against deleting any path under OPENCODE_APPS_DIR (mirrors the *********:4097 delete-guard proxy). The worktree-manager subagent pre-checks pushed/clean state before calling this.",
        args: {
          directory: tool.schema
            .string()
            .describe("Absolute worktree directory path to delete."),
        },
        async execute({ directory }, context) {
          if (!v2) return unavailable("DELETE", { directory });
          const reason = protectedRootReason(directory);
          if (reason) {
            return JSON.stringify({
              ok: false,
              status: 0,
              error: reason,
              refused: "PROTECTED_PROJECT_ROOT",
              manualRecovery: guiRecovery({ method: "DELETE", directory }),
            });
          }
          if (!directory || typeof directory !== "string") {
            return JSON.stringify(
              fail(0, null, "DELETE", {
                directory,
                error: "worktree_delete: `directory` is required",
              })
            );
          }
          const res = await unwrap(
            v2.worktree.remove({
              directory: (context && context.directory) || undefined,
              worktreeRemoveInput: { directory },
            }),
            "DELETE",
            { directory }
          );
          if (res.ok) scheduleGitCleanup(directory, context && context.directory);
          return JSON.stringify(res);
        },
      }),

      worktree_reset: tool({
        description:
          "Reconcile a worktree directory after a server restart or stale state. Calls POST /experimental/worktree/reset.",
        args: {
          directory: tool.schema
            .string()
            .describe("Absolute worktree directory path to reset."),
        },
        async execute({ directory }, context) {
          if (!v2) return unavailable("POST", { directory });
          if (!directory || typeof directory !== "string") {
            return JSON.stringify({
              ok: false,
              status: 0,
              error: "worktree_reset: `directory` is required",
            });
          }
          return JSON.stringify(
            await unwrap(
              v2.worktree.reset({
                directory: (context && context.directory) || undefined,
                worktreeResetInput: { directory },
              }),
              "POST",
              { directory }
            )
          );
        },
      }),
    },
  };
};
