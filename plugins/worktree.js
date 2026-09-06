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
 *   worktree_reconcile        Repair plugin registration by migrate-via-create:
 *                             diffs `git worktree list --porcelain` against
 *                             GET /experimental/worktree, recreates missing
 *                             feature-branch entries via POST (since the
 *                             server has no register-only verb), and DELETEs
 *                             stale plugin-only entries. Orphan cleanup is
 *                             operator-driven — surfaced in the report.
 *
 * Every call carries ?directory=<context.directory> to scope the operation
 * to the calling project. All HTTP work goes through one shared `wtFetch`
 * helper; per-tool code is just arg validation + body shape.
 */

const DEFAULT_BASE = "develop";
const FEATURE_BRANCH_PATTERN = /^opencode\/feat-/;
const RESERVED_BRANCH_PREFIX = "refs/heads/opencode/feat-";

import { execSync } from "child_process";
import { realpath } from "fs/promises";
import { join } from "path";
import os from "os";

// @version 1.3.0 — worktree_reconcile no longer renames local branches;
// worktree_create_feature returns WORKTREE_PRECONDITION_FAILED on duplicates.

async function realpathSafe(p) {
  try {
    return await realpath(p);
  } catch {
    return p;
  }
}

function safeExec(cmd) {
  try {
    return { ok: true, out: execSync(cmd, { encoding: "utf8" }).trim() };
  } catch (e) {
    return { ok: false, err: (e && e.message) || String(e) };
  }
}

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
          "Create a FEATURE worktree (opencode/feat-<slug>) for the current project. Forks off `base` (defaults to 'develop'). Use this ONLY for the top-level feature branch. The response includes a `branch` field (e.g. 'opencode/feat-<name>') — capture it and pass it as `feature_branch` to worktree_create_ticket when creating ticket worktrees off this feature. If a worktree with the same feature branch already exists on disk, returns WORKTREE_PRECONDITION_FAILED rather than reusing / renaming it.",
        args: {
          name: {
            type: "string",
            description:
              "Required. Feature slug, e.g. 'test' or 'billing-flow'. The plugin auto-prefixes 'feat-' if not already present.",
          },
          base: {
            type: "string",
            description:
              "Base branch to fork from. Pass an empty string to use the default 'develop'.",
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
          const branchShort = name.startsWith("opencode/") ? name : `opencode/${name}`;
          const fullRef = `refs/heads/${branchShort}`;

          // Precondition: if a worktree with this branch already exists in git,
          // refuse to create a duplicate / trigger collision. Direct the operator
          // to worktree_reset on the existing one instead.
          const existing = safeExec(
            `git worktree list --porcelain | grep -B1 "branch ${fullRef}" || true`,
          );
          if (existing.ok && existing.out.trim()) {
            const pathLine = safeExec(
              `git worktree list --porcelain | awk '/^worktree /{p=$2} /^branch /{b=$2} b==\\"${fullRef}\\"{print p; exit}'`,
            );
            return JSON.stringify({
              ok: false,
              blocker_code: "WORKTREE_PRECONDITION_FAILED",
              branch: branchShort,
              existing_path: pathLine.ok ? pathLine.out : null,
              manualRecovery:
                "A worktree for this feature branch already exists on disk. " +
                "Either (a) reuse it — call worktree_reset({directory: <path>}) to re-register it with the server; " +
                "or (b) remove it first — worktree_delete({directory: <path>}) — then call worktree_create_feature again.",
            });
          }

          const r = await wtFetch(
            "/experimental/worktree",
            { method: "POST", body: JSON.stringify({ name, base }) },
            context,
          );
          if (r && r.ok && r.body && r.body.branch && r.body.directory) {
            const branch = r.body.branch;
            const directory = r.body.directory;
            const head = safeExec(
              `git -C ${JSON.stringify(directory)} rev-parse --abbrev-ref HEAD`,
            );
            const remote = safeExec(
              `git -C ${JSON.stringify(directory)} config --get branch.${branch}.remote`,
            );
            const merge = safeExec(
              `git -C ${JSON.stringify(directory)} config --get branch.${branch}.merge`,
            );
            if (
              head.out !== branch ||
              remote.out !== "origin" ||
              !(merge.ok && merge.out.includes("refs/heads/"))
            ) {
              return JSON.stringify({
                ok: false,
                blocker_code: "WORKTREE_NO_UPSTREAM_TRACKING",
                branch,
                expected: { remote: "origin", merge: `refs/heads/${branch}` },
                actual: {
                  head: head.out,
                  remote: remote.out,
                  merge: merge.ok ? merge.out : null,
                  exec_error: !remote.ok ? remote.err : null,
                },
                manualRecovery:
                  `Inside ${directory}:\n` +
                  `  git worktree repair\n` +
                  `  git fetch origin ${branch}\n` +
                  `  git branch --set-upstream-to=origin/${branch} ${branch}\n` +
                  `If repair fails, worktree_delete and call worktree_create_feature again.`,
              });
            }
          }
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
          if (r && r.ok && r.body && r.body.branch && r.body.directory) {
            const branch = r.body.branch;
            const directory = r.body.directory;
            const head = safeExec(
              `git -C ${JSON.stringify(directory)} rev-parse --abbrev-ref HEAD`,
            );
            const remote = safeExec(
              `git -C ${JSON.stringify(directory)} config --get branch.${branch}.remote`,
            );
            const merge = safeExec(
              `git -C ${JSON.stringify(directory)} config --get branch.${branch}.merge`,
            );
            if (
              head.out !== branch ||
              remote.out !== "origin" ||
              !(merge.ok && merge.out.includes("refs/heads/"))
            ) {
              return JSON.stringify({
                ok: false,
                blocker_code: "WORKTREE_NO_UPSTREAM_TRACKING",
                branch,
                expected: { remote: "origin", merge: `refs/heads/${branch}` },
                actual: {
                  head: head.out,
                  remote: remote.out,
                  merge: merge.ok ? merge.out : null,
                  exec_error: !remote.ok ? remote.err : null,
                },
                manualRecovery:
                  `Inside ${directory}:\n` +
                  `  git worktree repair\n` +
                  `  git fetch origin ${branch}\n` +
                  `  git branch --set-upstream-to=origin/${branch} ${branch}\n` +
                  `If repair fails, worktree_delete and call worktree_create_ticket again — never raw \`git worktree add\` (Hard Rule 1).`,
              });
            }
          }
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

      worktree_reconcile: {
        description:
          "Repair the opencode server's worktree registration after it drifted from `git worktree list` — e.g. a manual `git worktree add -B` left a worktree on disk but invisible to the GUI. " +
          "Diffs git's worktree list against GET /experimental/worktree (realpath-collapsed, so bind-mount aliases count as one entry). " +
          "Surface-only by default: returns the diff with no mutations. " +
          "When dryRun=false: " +
          "(1) DELETEs plugin-only stale entries via DELETE /experimental/worktree (never touches git); " +
          "(2) for missing git entries, surfaces them in `missing_featurable[]` (opencode/feat-* branches the operator should re-register via worktree_create_feature) or `missing_ticketable[]` (opencode/ticket-* branches the operator should re-register via worktree_create_ticket) — the tool itself does NOT call POST /experimental/worktree or run `git branch -m` to avoid the 409-collision rename trap; " +
          "(3) surfaces bind-mount duplicate plugin entries in `duplicates_collapsed[]` (the plugin is the source of truth for collisions, but no auto-deletion — operator decides). " +
          "Optional mainCheckoutRoot (absolute path) — defaults to OPENCODE_MAIN_CHECKOUT env, then scans `git worktree list --porcelain` for the first non-`opencode/*` worktree. Default dryRun=true; pass dryRun=false to actually delete stale plugin entries.",
        args: {
          mainCheckoutRoot: {
            type: "string",
            description:
              "Optional. Absolute path to the main checkout of the repo. Defaults to OPENCODE_MAIN_CHECKOUT env, else the first non-opencode/* worktree from `git worktree list --porcelain`.",
          },
          dryRun: {
            type: "boolean",
            description:
              "Optional, default true. When true, only computes the diff and returns it without any mutations. Pass false to actually delete stale plugin entries (worktree DELETE only — never touches git).",
          },
        },
        async execute(args, context) {
          if (!context || !context.directory) {
            return clientError(
              "worktree_reconcile requires a project context.directory.",
            );
          }
          const dryRun =
            args && typeof args.dryRun === "boolean" ? args.dryRun : true;
          const argMain = args && args.mainCheckoutRoot;
          if (argMain && (typeof argMain !== "string" || !argMain.startsWith("/"))) {
            return clientError(
              "worktree_reconcile: mainCheckoutRoot must be an absolute path.",
            );
          }

          const gitCwd =
            argMain ||
            process.env.OPENCODE_MAIN_CHECKOUT ||
            (() => {
              const probe = safeExec("git worktree list --porcelain");
              if (!probe.ok) return null;
              const blocks = probe.out.split("\n\n");
              for (const b of blocks) {
                const lines = b.split("\n");
                const wtLine = lines.find((l) => l.startsWith("worktree "));
                const brLine = lines.find((l) => l.startsWith("branch "));
                if (!wtLine || !brLine) continue;
                const branch = brLine.slice("branch ".length).trim();
                if (!branch.startsWith("opencode/")) {
                  return wtLine.slice("worktree ".length).trim();
                }
              }
              return null;
            })();

          if (!gitCwd) {
            return JSON.stringify({
              ok: false,
              blocker_code: "RECONCILE_NO_GIT_SOURCE",
              manualRecovery:
                "Pass an absolute mainCheckoutRoot argument or set OPENCODE_MAIN_CHECKOUT, or run from a directory whose `git worktree list --porcelain` shows a non-opencode/* worktree (typically the main checkout).",
            });
          }

          const wtListRaw = safeExec(
            `git -C ${JSON.stringify(gitCwd)} worktree list --porcelain`,
          );
          if (!wtListRaw.ok) {
            return JSON.stringify({
              ok: false,
              blocker_code: "RECONCILE_NO_GIT_SOURCE",
              gitCwd,
              exec_error: wtListRaw.err,
              manualRecovery: `Confirm ${gitCwd} is a git worktree root.`,
            });
          }

          const wtReal = await realpathSafe(
            process.env.OPENCODE_WORKTREES_DIR ||
              join(os.homedir(), ".opencode-worktrees"),
          );

          const gitRecords = [];
          for (const block of wtListRaw.out.split("\n\n")) {
            const lines = block.split("\n").filter(Boolean);
            let path, branch;
            for (const l of lines) {
              if (l.startsWith("worktree ")) path = l.slice("worktree ".length);
              else if (l.startsWith("branch "))
                branch = l.slice("branch ".length);
            }
            if (!path) continue;
            const real = await realpathSafe(path);
            gitRecords.push({ path, real, branch });
          }

          // Prefer the spelling that equals WT_REAL when present.
          const canonicalByReal = new Map();
          for (const rec of gitRecords) {
            if (!canonicalByReal.has(rec.real)) {
              canonicalByReal.set(rec.real, rec);
            } else if (rec.path === wtReal) {
              canonicalByReal.set(rec.real, rec);
            }
          }

          const regResp = await wtFetch(
            "/experimental/worktree",
            { method: "GET" },
            context,
          );
          if (!regResp.ok) {
            return JSON.stringify({
              ok: false,
              blocker_code: "RECONCILE_NO_PLUGIN_SOURCE",
              regResp,
            });
          }
          const regRaw = Array.isArray(regResp.body)
            ? regResp.body
            : regResp.body && Array.isArray(regResp.body.worktrees)
              ? regResp.body.worktrees
              : [];
          const pluginEntries = [];
          for (const e of regRaw) {
            if (typeof e === "string") pluginEntries.push({ path: e });
            else if (e && typeof e === "object")
              pluginEntries.push({
                path: e.path || e.directory,
                branch: e.branch,
                head: e.head,
              });
          }
          const pluginReals = new Set();
          const pluginByReal = new Map();
          for (const e of pluginEntries) {
            if (!e.path) continue;
            const real = await realpathSafe(e.path);
            pluginReals.add(real);
            if (!pluginByReal.has(real)) pluginByReal.set(real, e);
          }

          const missing_featurable = [];
          const missing_ticketable = [];
          const missing_other = [];
          const stale = [];
          const duplicates_collapsed = [];
          const kept = [];

          for (const [real, rec] of canonicalByReal) {
            if (!pluginReals.has(real)) {
              if (rec.branch && rec.branch.startsWith(RESERVED_BRANCH_PREFIX)) {
                missing_featurable.push({
                  path: rec.path,
                  branch: rec.branch,
                  realpath: real,
                  manual_recovery:
                    "Call worktree_create_feature({ name: '<feat-slug>', base: '<branch-name>' }). The slug is the part after 'opencode/feat-'. The plugin auto-prefixes 'feat-' to the name. If a worktree with that name already exists, worktree_create_feature will return WORKTREE_PRECONDITION_FAILED — call worktree_reset on the existing one first.",
                });
              } else if (rec.branch && rec.branch.startsWith("refs/heads/opencode/ticket-")) {
                const branchShort = rec.branch.slice("refs/heads/".length);
                missing_ticketable.push({
                  path: rec.path,
                  branch: branchShort,
                  realpath: real,
                  manual_recovery:
                    "Ticket branches cannot be auto-recreated by reconcile (the server's create-collision rule renames them). Either: (a) keep the existing on-disk worktree and call worktree_reset({ directory: <path> }) to re-register it; or (b) worktree_delete it then worktree_create_ticket({ feature_branch: '<feat-branch>', name: '<ticket-name>' }) to recreate from origin.",
                });
              } else {
                missing_other.push({
                  path: rec.path,
                  branch: rec.branch,
                  realpath: real,
                });
              }
            } else {
              const pluginEntry = pluginByReal.get(real);
              if (pluginEntry.path === rec.path) {
                kept.push({
                  path: rec.path,
                  branch: rec.branch,
                  plugin_path: pluginEntry.path,
                });
              } else {
                duplicates_collapsed.push({
                  git_path: rec.path,
                  plugin_path: pluginEntry.path,
                  realpath: real,
                });
              }
            }
          }
          for (const e of pluginEntries) {
            if (!e.path) continue;
            const real = await realpathSafe(e.path);
            if (!canonicalByReal.has(real)) {
              stale.push({ path: e.path, branch: e.branch });
            }
          }

          const summary = {
            git_worktrees: canonicalByReal.size,
            plugin_registrations: pluginEntries.length,
            missing_featurable: missing_featurable.length,
            missing_ticketable: missing_ticketable.length,
            missing_other: missing_other.length,
            stale: stale.length,
            duplicates_collapsed: duplicates_collapsed.length,
            kept: kept.length,
          };

          if (dryRun) {
            return JSON.stringify({
              ok: true,
              dryRun: true,
              gitCwd,
              wtReal,
              summary,
              missing_featurable,
              missing_ticketable,
              missing_other,
              stale,
              duplicates_collapsed,
              kept,
            });
          }

          // dryRun=false: only delete stale plugin entries (no git mutations).
          const stale_results = [];
          for (const s of stale) {
            try {
              const r = await wtFetch(
                "/experimental/worktree",
                {
                  method: "DELETE",
                  body: JSON.stringify({ directory: s.path }),
                },
                context,
              );
              stale_results.push({
                path: s.path,
                ok: r.ok,
                status: r.status,
                body: r.body,
              });
            } catch (e) {
              stale_results.push({
                path: s.path,
                ok: false,
                exec_error: (e && e.message) || String(e),
              });
            }
          }

          return JSON.stringify({
            ok: true,
            dryRun: false,
            gitCwd,
            wtReal,
            summary: {
              ...summary,
              plugin_registrations_before: pluginEntries.length,
              stale_attempted: stale.length,
              stale_succeeded: stale_results.filter((r) => r.ok).length,
            },
            stale_results,
            // Surface the operator-action-required lists every time so the
            // operator can act on them.
            operator_action_required: {
              missing_featurable,
              missing_ticketable,
              missing_other,
              duplicates_collapsed,
            },
            note:
              "worktree_reconcile does NOT auto-register missing entries. Use worktree_create_feature for feature branches and worktree_create_ticket (or worktree_reset on existing) for ticket branches. See operator_action_required for per-entry guidance.",
          });
        },
      },
    },
  };
};