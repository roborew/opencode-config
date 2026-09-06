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

// @version 1.2.0 — added worktree_reconcile

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
                  `If repair fails, worktree_delete and call worktree_create_feature again — never raw \`git worktree add\` (Hard Rule 1).`,
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
          "Diffs git's worktree list against GET /experimental/worktree (realpath-collapsed, so bind-mount aliases count as one entry), then: " +
          "(1) DELETEs plugin-only stale entries via DELETE /experimental/worktree; " +
          "(2) for missing git entries whose branch starts with `opencode/feat-`, renames the orphan's local branch via `git branch -m` to dodge the server's 409 collision, then POSTs /experimental/worktree {name, base} to register a new canonical entry off the existing feature branch; " +
          "(3) surfaces the orphan's old path in `orphans_to_cleanup[]` for operator-driven `worktree_delete` follow-up (never auto-deletes — Hard Rule 1). " +
          "Non-`opencode/feat-*` branches (develop, main, ticket branches) go to `not_recoverable[]` with manualRecovery hints. " +
          "The plugin itself shells out to git inside this tool only; agents must dispatch into this tool rather than running raw git for reconciliation. " +
          "Default dryRun=true: pass dryRun=false to actually write. Accepts optional mainCheckoutRoot (absolute path) for the git source — defaults to OPENCODE_MAIN_CHECKOUT env, then scans `git worktree list --porcelain` for the first non-`opencode/*` worktree.",
        args: {
          mainCheckoutRoot: {
            type: "string",
            description:
              "Optional. Absolute path to the main checkout of the repo. Defaults to OPENCODE_MAIN_CHECKOUT env, else the first non-opencode/* worktree from `git worktree list --porcelain`.",
          },
          dryRun: {
            type: "boolean",
            description:
              "Optional, default true. When true, only computes the diff and returns it without any writes or git mutations. Pass false to actually recreate missing entries and delete stale ones.",
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
          if (typeof dryRun !== "boolean") {
            return clientError("worktree_reconcile: dryRun must be boolean.");
          }
          const argMain = args && args.mainCheckoutRoot;
          if (argMain && typeof argMain !== "string") {
            return clientError(
              "worktree_reconcile: mainCheckoutRoot must be a string path.",
            );
          }
          if (argMain && !argMain.startsWith("/")) {
            return clientError(
              "worktree_reconcile: mainCheckoutRoot must be an absolute path.",
            );
          }

          const gitCwd =
            argMain ||
            process.env.OPENCODE_MAIN_CHECKOUT ||
            (() => {
              const probe = safeExec(
                "git worktree list --porcelain",
              );
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
              manualRecovery: `Confirm ${gitCwd} is a git worktree root (run \`git -C ${gitCwd} worktree list\` manually).`,
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

          // Prefer the spelling that equals WT_REAL when present; else first-seen.
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
              manualRecovery:
                "GET /experimental/worktree failed — server may be down. Retry after verifying server health.",
            });
          }
          const regRaw = Array.isArray(regResp.body)
            ? regResp.body
            : regResp.body &&
                Array.isArray(regResp.body.worktrees)
              ? regResp.body.worktrees
              : [];
          const pluginEntries = [];
          for (const e of regRaw) {
            if (typeof e === "string") {
              pluginEntries.push({ path: e });
            } else if (e && typeof e === "object") {
              pluginEntries.push({
                path: e.path || e.directory,
                branch: e.branch,
                head: e.head,
              });
            }
          }
          const pluginReals = new Set();
          const pluginByReal = new Map();
          for (const e of pluginEntries) {
            if (!e.path) continue;
            const real = await realpathSafe(e.path);
            pluginReals.add(real);
            if (!pluginByReal.has(real)) pluginByReal.set(real, e);
          }

          const missing = [];
          const stale = [];
          const duplicates_collapsed = [];
          const kept = [];

          for (const [real, rec] of canonicalByReal) {
            if (!pluginReals.has(real)) {
              missing.push({
                path: rec.path,
                branch: rec.branch,
                realpath: real,
              });
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

          const summaryBase = {
            git_worktrees: canonicalByReal.size,
            plugin_registrations: pluginEntries.length,
            missing: missing.length,
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
              summary: summaryBase,
              missing,
              stale,
              duplicates_collapsed,
              kept,
            });
          }

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
              stale_results.push({ path: s.path, ok: r.ok, status: r.status, body: r.body });
            } catch (e) {
              stale_results.push({
                path: s.path,
                ok: false,
                exec_error: (e && e.message) || String(e),
              });
            }
          }

          const missing_results = [];
          const missing_succeeded = [];
          const missing_failed = [];
          const not_recoverable = [];

          for (const m of missing) {
            if (!m.branch || !m.branch.startsWith(RESERVED_BRANCH_PREFIX)) {
              not_recoverable.push({
                path: m.path,
                branch: m.branch,
                reason: "non_feature_branch",
                manualRecovery:
                  "Branch does not start with 'refs/heads/opencode/feat-'. " +
                  "Prune the orphan manually if you want it gone; ticket branches and develop/main cannot be recreated via this tool.",
              });
              continue;
            }
            const branchShort = m.branch.slice("refs/heads/".length);
            const name = `feat-${branchShort.slice("opencode/feat-".length)}`;

            let branch_renamed_to = null;
            let rename_ok = false;
            const rev = safeExec(
              `git -C ${JSON.stringify(gitCwd)} rev-parse --verify ${branchShort}`,
            );
            if (rev.ok) {
              const unix = Date.now();
              const target = `${branchShort}-orphan-${unix}`;
              const rename = safeExec(
                `git -C ${JSON.stringify(gitCwd)} branch -m ${branchShort} ${target}`,
              );
              if (rename.ok) {
                branch_renamed_to = target;
                rename_ok = true;
              }
            }

            let feature_branch_stale = false;
            const localRev = safeExec(
              `git -C ${JSON.stringify(gitCwd)} rev-parse ${branchShort}`,
            );
            const originRev = safeExec(
              `git -C ${JSON.stringify(gitCwd)} rev-parse origin/${branchShort}`,
            );
            if (localRev.ok && originRev.ok && localRev.out !== originRev.out) {
              feature_branch_stale = true;
            }

            try {
              const r = await wtFetch(
                "/experimental/worktree",
                {
                  method: "POST",
                  body: JSON.stringify({ name, base: branchShort }),
                },
                context,
              );
              const entry = {
                old_path: m.path,
                branch_renamed_to,
                rename_ok,
                feature_branch_stale,
                create_envelope: r,
              };
              if (r.ok && r.body && r.body.directory && r.body.branch) {
                entry.new_directory = r.body.directory;
                entry.new_branch = r.body.branch;
                missing_succeeded.push(entry);
              } else {
                missing_failed.push(entry);
              }
              missing_results.push(entry);
            } catch (e) {
              const entry = {
                old_path: m.path,
                branch_renamed_to,
                rename_ok,
                feature_branch_stale,
                ok: false,
                exec_error: (e && e.message) || String(e),
              };
              missing_failed.push(entry);
              missing_results.push(entry);
            }
          }

          const orphans_to_cleanup = missing_succeeded.map(
            ({ old_path, new_directory, branch_renamed_to }) => ({
              old_path,
              new_directory,
              manualRecovery: branch_renamed_to
                ? `Branch was renamed to ${branch_renamed_to} so the orphan is no longer the canonical feature ref. After verifying the new canonical worktree at ${new_directory}, run worktree_delete({ directory: ${JSON.stringify(old_path)} }) to clean up the orphan and then optionally \`git branch -D ${branch_renamed_to}\` if you no longer need it.`
                : `Run worktree_delete({ directory: ${JSON.stringify(old_path)} }) to clean up the orphan.`,
            }),
          );

          return JSON.stringify({
            ok: true,
            dryRun: false,
            gitCwd,
            wtReal,
            summary: {
              ...summaryBase,
              plugin_registrations_before: pluginEntries.length,
              missing_attempted: missing.length,
              missing_succeeded: missing_succeeded.length,
              missing_failed: missing_failed.length,
              stale_attempted: stale.length,
              stale_succeeded: stale_results.filter((r) => r.ok).length,
              not_recoverable: not_recoverable.length,
            },
            stale_results,
            missing_results,
            not_recoverable,
            orphans_to_cleanup,
          });
        },
      },
    },
  };
};