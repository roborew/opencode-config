/**
 * Worktree plugin — drives OpenCode's own `/experimental/worktree` API so
 * worktrees + sessions register in the Desktop GUI.
 *
 * Canonical source: opencode-config/plugins/worktree.js (this repo).
 * Deployed via:    opencode-config/plugins/ → ${OPENCODE_CONFIG_DIR}/plugins/
 *                  (entrypoint copies config-repo plugins into the runtime
 *                  plugin dir alongside server-side docker/plugins/*.js).
 *
 * No raw fetch needed: the in-process SDK `client` from PluginInput carries
 * HTTP Basic Auth automatically (OPENCODE_SERVER_USERNAME/PASSWORD).
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

export const WorktreePlugin = async (_ctx) => {
  // Tool factories are registered once at plugin init; ctx.client is the
  // in-process SDK client that talks to the upstream opencode serve on
  // loopback. Auth is carried automatically.
  const client = _ctx && _ctx.client;
  if (!client || !client.worktree) {
    throw new Error("worktree plugin: in-process SDK client is unavailable");
  }

  return {
    tool: {
      worktree_create: {
        description:
          "Create an OpenCode worktree under OPENCODE_WORKTREES_DIR via the /experimental/worktree API. Branch is auto-prefixed opencode/<name>. After create, the worktree appears in the Desktop GUI and a session is auto-started.",
        parameters: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description:
                "Worktree name (no slashes). Convention: feat-<slug> or ticket-<issue>-<slug>.",
            },
          },
          required: ["name"],
        },
        execute: async ({ name }) => {
          if (!name || typeof name !== "string" || name.includes("/")) {
            return {
              ok: false,
              status: 0,
              error:
                "worktree_create: `name` is required and must not contain '/'",
              manualRecovery: guiRecovery({ method: "POST", name }),
            };
          }
          try {
            const res = await client.worktree.create({
              worktreeCreateInput: { name },
            });
            return { ok: true, status: 200, body: res };
          } catch (err) {
            return fail(
              err?.status ?? 0,
              err?.body ?? String(err?.message || err),
              "POST",
              { name, error: String(err?.message || err) }
            );
          }
        },
      },

      worktree_list: {
        description:
          "List worktrees under the current project directory. Returns string[] of worktree directory paths.",
        parameters: { type: "object", properties: {} },
        execute: async () => {
          try {
            const res = await client.worktree.list();
            return { ok: true, status: 200, body: res };
          } catch (err) {
            return fail(
              err?.status ?? 0,
              err?.body ?? String(err?.message || err),
              "GET",
              { error: String(err?.message || err) }
            );
          }
        },
      },

      worktree_delete: {
        description:
          "Delete an OpenCode worktree by directory path. Self-guards against deleting any path under OPENCODE_APPS_DIR (mirrors the *********:4097 delete-guard proxy). The worktree-manager subagent pre-checks pushed/clean state before calling this.",
        parameters: {
          type: "object",
          properties: {
            directory: {
              type: "string",
              description: "Absolute worktree directory path to delete.",
            },
          },
          required: ["directory"],
        },
        execute: async ({ directory }) => {
          const reason = protectedRootReason(directory);
          if (reason) {
            return {
              ok: false,
              status: 0,
              error: reason,
              refused: "PROTECTED_PROJECT_ROOT",
              manualRecovery: guiRecovery({ method: "DELETE", directory }),
            };
          }
          if (!directory || typeof directory !== "string") {
            return {
              ok: false,
              status: 0,
              error: "worktree_delete: `directory` is required",
              manualRecovery: guiRecovery({ method: "DELETE", directory }),
            };
          }
          try {
            const res = await client.worktree.remove({
              directory,
              worktreeRemoveInput: { directory },
            });
            return { ok: true, status: 200, body: res };
          } catch (err) {
            return fail(
              err?.status ?? 0,
              err?.body ?? String(err?.message || err),
              "DELETE",
              { directory, error: String(err?.message || err) }
            );
          }
        },
      },

      worktree_reset: {
        description:
          "Reconcile a worktree directory after a server restart or stale state. Calls POST /experimental/worktree/reset.",
        parameters: {
          type: "object",
          properties: {
            directory: {
              type: "string",
              description: "Absolute worktree directory path to reset.",
            },
          },
          required: ["directory"],
        },
        execute: async ({ directory }) => {
          if (!directory || typeof directory !== "string") {
            return {
              ok: false,
              status: 0,
              error: "worktree_reset: `directory` is required",
            };
          }
          try {
            const res = await client.worktree.reset({
              directory,
              worktreeResetInput: { directory },
            });
            return { ok: true, status: 200, body: res };
          } catch (err) {
            return {
              ok: false,
              status: err?.status ?? 0,
              body: err?.body ?? String(err?.message || err),
              error: String(err?.message || err),
            };
          }
        },
      },
    },
  };
};