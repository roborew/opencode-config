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
import { readFile, writeFile } from "node:fs/promises";
import { setTimeout as sleep } from "node:timers/promises";
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
  if (method === "PROMPT_ASYNC") {
    const dirQ = directory ? `?directory=${encodeURIComponent(directory)}` : "";
    const payload = (opts && opts.payload) || "{}";
    return `curl -sS -u '${auth}' -X POST '${base}/session/${name}${dirQ}' \\\n  -H 'Content-Type: application/json' \\\n  -d '${payload.replace(/'/g, "'\\''")}'`;
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

// Parse `<worktree>/.git` (a FILE for linked worktrees) to locate the gitdir.
// Returns null when `.git` is a directory (worktree dir IS the gitdir — cannot
// host a brief file outside the working tree). Brief file lives in gitdir so it
// auto-cleans on `git worktree remove` / gitdir pruning, and never appears in
// `git status` (the worktree-manager delete pre-check `git status --porcelain`
// stays valid).
async function resolveWorktreeGitdir(worktreeDir) {
  if (!worktreeDir) return null;
  let raw;
  try {
    raw = await readFile(`${worktreeDir}/.git`, "utf8");
  } catch (_) {
    return null;
  }
  const m = /^gitdir:\s*(.+)\s*$/m.exec(raw);
  return m ? m[1].trim() : null;
}

// Resolve the develop orchestrator session id from a context (worktree-manager's
// calling session). The worktree-manager runs in a child session whose parent is
// the develop orchestrator — we look it up via session.list with directory =
// context.directory (the project main checkout), find the calling sessionID,
// then take its parentID. Falls back to context.sessionID itself if no parent.
async function resolveDevelopSessionId(v2, context) {
  const dir = context && context.directory;
  const myId = context && context.sessionID;
  if (!v2 || !dir || !myId) return null;
  try {
    const res = await v2.session.list({ directory: dir });
    const list = (res && res.data) || [];
    const me = list.find((s) => s && s.id === myId);
    return (me && me.parentID) || myId || null;
  } catch (_) {
    return null;
  }
}

// Write the durable brief JSON into the worktree gitdir. NEVER in the working
// tree (would pollute `git status`, fail worktree-manager delete pre-check, and
// not auto-clean on worktree removal).
async function writeBriefFile(gitdir, brief) {
  if (!gitdir || !brief) return null;
  const path = `${gitdir}/opencode-ticket-brief.json`;
  await writeFile(path, JSON.stringify(brief, null, 2), "utf8");
  return path;
}

// Poll for the auto-started GUI session in a freshly-created worktree dir.
// Selection: newest by time.created, directory === worktreeDir, parentID absent.
// Up to `tries * intervalMs` total. Returns session id or null.
async function pollForTicketSession(v2, projectDir, worktreeDir, tries = 10, intervalMs = 1500) {
  if (!v2 || !worktreeDir) return null;
  for (let i = 0; i < tries; i += 1) {
    try {
      const res = await v2.session.list({ directory: projectDir });
      const list = (res && res.data) || [];
      const matches = list.filter(
        (s) => s && s.directory === worktreeDir && !s.parentID
      );
      if (matches.length) {
        matches.sort((a, b) => (b.time?.created || 0) - (a.time?.created || 0));
        return matches[0].id || null;
      }
    } catch (_) {
      /* retry */
    }
    if (i < tries - 1) await sleep(intervalMs);
  }
  return null;
}

// Look up a session id by directory (newest, no parentID). Used by session_notify
// when the caller supplies `directory` instead of `sessionID`.
async function resolveSessionByDir(v2, projectDir, targetDir) {
  if (!v2 || !targetDir) return null;
  try {
    const res = await v2.session.list({ directory: projectDir });
    const list = (res && res.data) || [];
    const matches = list.filter(
      (s) => s && s.directory === targetDir && !s.parentID
    );
    if (!matches.length) return null;
    matches.sort((a, b) => (b.time?.created || 0) - (a.time?.created || 0));
    return matches[0].id || null;
  } catch (_) {
    return null;
  }
}

// Call session.promptAsync. SDK contract: 204 + void data on success. We must
// NOT route this through `unwrap()` — its `data === undefined` check would treat
// 204 as failure (and 204 has no body). Check `error == null` + status directly.
async function callPromptAsync(v2, params) {
  try {
    const res = await v2.session.promptAsync(params);
    const status = res && res.response && res.response.status;
    if (res && res.error == null && (status === 204 || status === 200)) {
      return { ok: true, status: status || 204 };
    }
    return {
      ok: false,
      status: status || 0,
      error: (res && res.error) || `promptAsync unexpected status ${status || 0}`,
    };
  } catch (err) {
    return {
      ok: false,
      status: err?.status || 0,
      error: String(err?.message || err),
    };
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
          "Create an OpenCode worktree under OPENCODE_WORKTREES_DIR via the /experimental/worktree API. Branch is auto-prefixed opencode/<name>. After create, the worktree appears in the Desktop GUI and a session is auto-started. When `kickoff_message` is provided, the plugin writes a durable brief file into the worktree gitdir (NEVER in the working tree — never in `git status`) and injects a short pointer message into the auto-started GUI session via `session.promptAsync`. `kickoff_agent` switches the session's agent for the injected message (default `coder` — ticket sessions run as the `coder` primary agent loading `ticket-lifecycle`).",
        args: {
          name: tool.schema
            .string()
            .describe(
              "Worktree name (no slashes). Convention: feat-<slug> or ticket-<issue>-<slug>-<abbrev>."
            ),
          kickoff_message: tool.schema
            .string()
            .optional()
            .describe(
              "Short pointer text to inject into the auto-started GUI session. When present, also writes <gitdir>/opencode-ticket-brief.json before injecting."
            ),
          kickoff_agent: tool.schema
            .string()
            .optional()
            .describe("Agent for the kickoff message (default `coder`)."),
        },
        async execute({ name, kickoff_message, kickoff_agent }, context) {
          if (!v2) return unavailable("POST", { name });
          if (!name || typeof name !== "string" || name.includes("/")) {
            return JSON.stringify(
              fail(0, null, "POST", {
                name,
                error: "worktree_create: `name` is required and must not contain '/'",
              })
            );
          }
          const base = await unwrap(
            v2.worktree.create({
              directory: (context && context.directory) || undefined,
              worktreeCreateInput: { name },
            }),
            "POST",
            { name }
          );
          if (!base.ok) return JSON.stringify(base);

          // No kickoff requested: keep the existing envelope shape exactly.
          if (!kickoff_message || typeof kickoff_message !== "string") {
            return JSON.stringify(base);
          }

          // Kickoff path: write brief file, resolve develop session, inject.
          const projectDir = context && context.directory;
          const worktreeDir = (base.body && base.body.directory) || null;
          const gitdir = await resolveWorktreeGitdir(worktreeDir);
          const developSessionId = await resolveDevelopSessionId(v2, context);
          const brief = {
            execution_mode: "github_issue_full",
            issue_number: null,
            repo: null,
            issue_url: null,
            feature_slug: null,
            feature_branch: null,
            expected_branch: base.body && base.body.branch
              ? base.body.branch
              : `opencode/${name}`,
            worktree_directory: worktreeDir,
            agent: kickoff_agent || "coder",
            develop_session_id: developSessionId,
            auto_spawn_consent: true,
            kickoff_message,
            created_at: new Date().toISOString(),
          };
          const briefFile = await writeBriefFile(gitdir, brief);
          const ticketSessionId = await pollForTicketSession(v2, projectDir, worktreeDir);
          let kickoffStatus = "no_session_after_poll";
          let promptResult = null;
          if (ticketSessionId) {
            const agent = kickoff_agent || "coder";
            promptResult = await callPromptAsync(v2, {
              sessionID: ticketSessionId,
              directory: projectDir,
              agent,
              parts: [{ type: "text", text: kickoff_message }],
            });
            if (promptResult.ok) {
              kickoffStatus = "admitted";
            } else {
              kickoffStatus = "failed";
            }
          }
          return JSON.stringify({
            ...base,
            brief_file: briefFile,
            session_id: ticketSessionId,
            develop_session_id: developSessionId,
            kickoff_agent: kickoff_agent || "coder",
            kickoff: kickoffStatus,
            kickoff_error: promptResult && !promptResult.ok ? promptResult.error : null,
          });
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

      session_notify: tool({
        description:
          "Inject a short message into an existing session via POST /session/{id}/prompt_async (204 fire-and-forget). Used by ticket sessions to report back to the develop orchestrator, and by the worktree-manager to retry a kickoff that landed before the GUI session was registered. Pass exactly one of `sessionID` or `directory`: `directory` resolves to the newest session in that directory with no parentID (the auto-started GUI session for a ticket worktree). `agent` switches the session's agent for this message only (default: leave unchanged). Returns { ok, session_id, target_directory, agent, admitted }. Manual recovery: curl POST /session/<id>/prompt_async shown in `manualRecovery`.",
        args: {
          sessionID: tool.schema
            .string()
            .optional()
            .describe("Target session id (mutually exclusive with `directory`)."),
          directory: tool.schema
            .string()
            .optional()
            .describe(
              "Target worktree directory; resolves to the newest no-parent session in it (mutually exclusive with `sessionID`)."
            ),
          agent: tool.schema
            .string()
            .optional()
            .describe("Agent override for this message (optional)."),
          message: tool.schema
            .string()
            .describe("Message text to inject (short pointer only)."),
        },
        async execute({ sessionID, directory, agent, message }, context) {
          if (!v2) return unavailable("PROMPT_ASYNC", {});
          if (!message || typeof message !== "string") {
            return JSON.stringify(
              fail(0, null, "PROMPT_ASYNC", {
                error: "session_notify: `message` is required",
              })
            );
          }
          const hasId = !!sessionID;
          const hasDir = !!directory;
          if (hasId === hasDir) {
            return JSON.stringify(
              fail(0, null, "PROMPT_ASYNC", {
                error:
                  "session_notify: exactly one of `sessionID` or `directory` is required",
              })
            );
          }
          const projectDir = (context && context.directory) || undefined;
          let resolvedId = sessionID || null;
          let targetDir = null;
          if (!resolvedId) {
            resolvedId = await resolveSessionByDir(v2, projectDir, directory);
            if (!resolvedId) {
              const payload = JSON.stringify({
                parts: [{ type: "text", text: message }],
                agent,
              }).replace(/'/g, "'\\''");
              return JSON.stringify(
                fail(404, null, "PROMPT_ASYNC", {
                  directory,
                  error:
                    "session_notify: no session found for directory (session not yet registered or wrong path)",
                  manualRecovery: guiRecovery({
                    method: "PROMPT_ASYNC",
                    name: "<sessionID>",
                    directory,
                    payload,
                  }),
                })
              );
            }
            targetDir = directory;
          } else {
            // Best-effort directory capture for response shape.
            targetDir = directory || null;
          }
          const parts = [{ type: "text", text: message }];
          const params = { sessionID: resolvedId, parts };
          if (projectDir) params.directory = projectDir;
          if (agent) params.agent = agent;
          const promptResult = await callPromptAsync(v2, params);
          const payload = JSON.stringify({ parts, agent }).replace(
            /'/g,
            "'\\''"
          );
          if (!promptResult.ok) {
            return JSON.stringify(
              fail(promptResult.status || 502, promptResult.error, "PROMPT_ASYNC", {
                name: resolvedId,
                directory: targetDir,
                error: promptResult.error,
                manualRecovery: guiRecovery({
                  method: "PROMPT_ASYNC",
                  name: resolvedId,
                  directory: targetDir,
                  payload,
                }),
              })
            );
          }
          return JSON.stringify({
            ok: true,
            status: promptResult.status || 204,
            session_id: resolvedId,
            target_directory: targetDir,
            agent: agent || null,
            admitted: true,
            manualRecovery: guiRecovery({
              method: "PROMPT_ASYNC",
              name: resolvedId,
              directory: targetDir,
              payload,
            }),
          });
        },
      }),
    },
  };
};
