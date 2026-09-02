/**
 * Sandbox plugin — fine-grained compose-test backend lifecycle for the
 * worktree-sandbox refactor. Sits beside `plugins/worktree.js` and mirrors
 * its posture (env-based Basic auth, ctx.serverUrl URL discovery, plain
 * JSON Schema args, pass-through {ok, status, body} envelope), plus a
 * `child_process` runner since this plugin actually executes commands
 * against the opencode-server `sandbox` CLI and `docker compose` —
 * worktree.js is HTTP-only CRUD, sandbox.js drives the compose test
 * backend end-to-end.
 *
 * Tools (8 total — see `skills/worktree-sandbox/SKILL.md` for the mode
 * matrix that composes them):
 *
 *   sandbox_probe     no exec; resolves OPENCODE_SANDBOX_ENABLED,
 *                     `command -v sandbox`, `command -v docker`.
 *                     Returns capability + recommended_backend.
 *   env_copy          runs `cp` per file. Replaces legacy symlinks
 *                     with copies. No contents, no .env.example.
 *   sandbox_create    runs `sandbox create --id ... --worktree ...`
 *                     (or no-op + warning when sandbox: unavailable).
 *                     One sandbox per worktree.
 *   sandbox_build     `sandbox exec --id ... -- docker compose -f ... build`
 *                     (or direct docker compose when sandbox: unavailable).
 *   sandbox_warm      smoke command inside the compose service via
 *                     `sandbox exec` — replaces cold-boot-on-first-RED.
 *   sandbox_run_test  per-stage test runner — wraps `sandbox exec --id ...
 *                     -- docker compose -f ... run --rm <service> <cmd>`
 *                     with optional test_filter. Used by test-writer
 *                     (RED), developer (GREEN), and code-review (replay).
 *   sandbox_status    `sandbox status --id ...` — read-only status.
 *   sandbox_destroy   `sandbox destroy --id ...` (unexpose first when
 *                     requested). Owned exclusively by worktree-sandbox
 *                     (mode: teardown) and code-review per docker-sandbox
 *                     skill §5 (APPROVED / ENV_BLOCKED).
 *
 * Every tool that exec's inherits the same shape: `{ok, status, body}`
 * envelope with timing, evidence_path for full output, and a single
 * `blocker_code` value (`ENV_BLOCKED` or `SANDBOX_ID_COLLISION`) on the
 * terminal failures. The plugin never invents an invocation form —
 * sandbox-exec routes use the documented `sandbox probe|create|exec|
 * status|destroy|expose|preview|unexpose` surface from
 * `skills/docker-sandbox/SKILL.md`; direct-Docker routes are the same
 * `docker compose` invocations the skill's Direct Docker fallback
 * prescribes. The two paths are interchangeable for verification.
 */

import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";

const EVIDENCE_DIR = path.join(
  process.env.OPENCODE_EVIDENCE_DIR ||
    path.join(os.tmpdir(), "opencode-sandbox-evidence"),
);

const KNOWN_BLOCKER_CODES = {
  ENV_BLOCKED: "ENV_BLOCKED",
  SANDBOX_ID_COLLISION: "SANDBOX_ID_COLLISION",
  COMPOSE_TEST_FILE_MISSING: "ENV_BLOCKED",
  DOCKER_UNAVAILABLE: "ENV_BLOCKED",
  SANDBOX_UNAVAILABLE_NO_FALLBACK: "ENV_BLOCKED",
};

function clientError(msg, blocker) {
  return JSON.stringify({
    ok: false,
    status: 0,
    body: msg,
    ...(blocker ? { blocker_code: blocker } : {}),
  });
}

async function writeEvidence(tool, id, payload) {
  try {
    await fs.mkdir(EVIDENCE_DIR, { recursive: true });
    const safe = `${tool}-${id || "anon"}-${Date.now()}-${process.pid}.json`;
    const p = path.join(EVIDENCE_DIR, safe);
    await fs.writeFile(p, JSON.stringify(payload, null, 2), "utf8");
    return p;
  } catch {
    return null;
  }
}

function which(bin) {
  return new Promise((resolve) => {
    const proc = spawn("/bin/sh", ["-c", `command -v ${bin} || true`], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    proc.stdout.on("data", (chunk) => {
      out += chunk.toString("utf8");
    });
    proc.on("close", () => {
      const trimmed = out.trim();
      resolve(trimmed.length > 0 ? trimmed : null);
    });
    proc.on("error", () => resolve(null));
  });
}

async function resolveCapabilities() {
  const sandboxEnabled =
    String(process.env.OPENCODE_SANDBOX_ENABLED || "")
      .toLowerCase()
      .match(/^(1|true|yes)$/) !== null;
  const sandboxBin = await which("sandbox");
  const dockerBin = await which("docker");
  return {
    sandbox_enabled: sandboxEnabled,
    sandbox: sandboxBin ? "ready" : "unavailable",
    docker: dockerBin ? "ready" : "unavailable",
    recommended_backend: sandboxBin ? "sandbox" : dockerBin ? "docker" : null,
  };
}

function execCapture(bin, args, opts = {}) {
  return new Promise((resolve) => {
    const start = Date.now();
    const proc = spawn(bin, args, {
      stdio: ["ignore", "pipe", "pipe"],
      ...opts,
    });
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    proc.on("error", (err) => {
      resolve({
        ok: false,
        exit_code: -1,
        stdout: "",
        stderr: err.message,
        duration_seconds: (Date.now() - start) / 1000,
      });
    });
    proc.on("close", (exit_code) => {
      resolve({
        ok: exit_code === 0,
        exit_code,
        stdout,
        stderr,
        duration_seconds: (Date.now() - start) / 1000,
      });
    });
  });
}

async function sandboxExec(sandboxId, dockerArgs, worktreePath) {
  const args = ["exec", "--id", sandboxId];
  if (worktreePath) {
    args.push("--cwd", worktreePath);
  }
  args.push("--", "docker", "compose", ...dockerArgs);
  return execCapture("sandbox", args);
}

async function directDockerExec(dockerArgs, worktreePath) {
  const opts = worktreePath ? { cwd: worktreePath } : {};
  return execCapture("docker", ["compose", ...dockerArgs], opts);
}

function tailString(s, max = 4000) {
  if (!s) return "";
  return s.length <= max ? s : s.slice(s.length - max);
}

function parseComposeFileArg(composeFile) {
  return ["-f", composeFile];
}

function detectComposeFile(worktreePath) {
  return (async () => {
    const candidates = ["docker-compose.test.yml", "compose.test.yaml"];
    for (const name of candidates) {
      try {
        await fs.access(path.join(worktreePath, name));
        return name;
      } catch {
        // continue
      }
    }
    return null;
  })();
}

export const SandboxPlugin = async () => {
  console.log("[sandbox-plugin] compose-test backend tools loaded");

  return {
    tool: {
      sandbox_probe: {
        description:
          "Probe sandbox + docker capability. No args required (mode is informational). Returns { sandbox, docker, recommended_backend, sandbox_enabled }.",
        args: {
          mode: {
            type: "string",
            description:
              "Optional. Hint ('auto' | 'sandbox' | 'docker') — does not change the result, only records the requested mode in the response for audit.",
          },
        },
        async execute(args) {
          const caps = await resolveCapabilities();
          return JSON.stringify({
            ok: true,
            status: 200,
            body: {
              ...caps,
              requested_mode: (args && args.mode) || "auto",
            },
          });
        },
      },

      env_copy: {
        description:
          "Copy root .env / .env.local (or WORKTREE_ENV_FILES) from main checkout into the worktree. Replaces legacy symlinks with copies. Returns per-file status (paths only, never contents).",
        args: {
          worktree_path: {
            type: "string",
            description: "Required. Absolute path to the linked worktree root.",
          },
          main_path: {
            type: "string",
            description:
              "Required. Absolute path to the main checkout root (the source for env copies).",
          },
          files: {
            type: "string",
            description:
              "Optional. Space-separated basenames (default '.env .env.local'). Overrides WORKTREE_ENV_FILES.",
          },
        },
        async execute(args) {
          const wtRoot = args && args.worktree_path;
          const mainRoot = args && args.main_path;
          if (!wtRoot) {
            return clientError(
              "env_copy requires a non-empty 'worktree_path' argument.",
            );
          }
          if (!mainRoot) {
            return clientError(
              "env_copy requires a non-empty 'main_path' argument.",
            );
          }
          const list = (args && args.files) ||
            process.env.WORKTREE_ENV_FILES ||
            ".env .env.local";
          const files = list.split(/\s+/).filter((f) => f.length > 0);

          const fileEntries = [];
          for (const name of files) {
            const sourcePath = path.join(mainRoot, name);
            const targetPath = path.join(wtRoot, name);
            let status = "ok";
            let isRegular = false;
            try {
              const targetStat = await fs.lstat(targetPath).catch(() => null);
              if (targetStat) {
                if (targetStat.isSymbolicLink()) {
                  await fs.unlink(targetPath);
                  await fs.copyFile(sourcePath, targetPath);
                  status = "ok_replaced_symlink";
                  isRegular = true;
                } else if (targetStat.isFile()) {
                  status = "ok_existing";
                  isRegular = true;
                } else {
                  status = "skipped_non_regular";
                }
              } else {
                await fs.copyFile(sourcePath, targetPath);
                status = "ok";
                isRegular = true;
              }
            } catch (err) {
              status = err.code === "ENOENT"
                ? "skipped_missing_source"
                : "failed_cp";
              isRegular = false;
            }
            fileEntries.push({
              name,
              source: sourcePath,
              target: targetPath,
              status,
              is_regular_file: isRegular,
            });
          }

          const hadFailed = fileEntries.some((f) => f.status === "failed_cp");
          const allSkippedMissing = fileEntries.every(
            (f) => f.status === "skipped_missing_source",
          );
          const overall = hadFailed
            ? "failed_cp"
            : allSkippedMissing
              ? "skipped_missing_source"
              : "ok";

          const evidencePath = await writeEvidence("env_copy", path.basename(wtRoot), {
            tool: "env_copy",
            worktree_path: wtRoot,
            main_path: mainRoot,
            files: fileEntries,
            overall,
          });

          return JSON.stringify({
            ok: !hadFailed,
            status: hadFailed ? 1 : 0,
            body: {
              worktree_env: overall,
              wt_root: wtRoot,
              main_root: mainRoot,
              files: fileEntries,
              evidence_path: evidencePath,
              ...(hadFailed
                ? {
                    blocker_code: KNOWN_BLOCKER_CODES.ENV_BLOCKED,
                    recommended_env_fix:
                      "Copy env files from main checkout into this worktree (cp main .env worktree/.env), ensure targets are regular files, then retry env_copy.",
                  }
                : {}),
            },
          });
        },
      },

      sandbox_create: {
        description:
          "Create a Sysbox sibling sandbox for a worktree (or no-op + warning when sandbox: unavailable and docker: also unavailable). One sandbox per worktree.",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id (DNS-label).",
          },
          worktree_path: {
            type: "string",
            description: "Required. Absolute path to the worktree root.",
          },
        },
        async execute(args) {
          const id = args && args.id;
          const worktreePath = args && args.worktree_path;
          if (!id) {
            return clientError(
              "sandbox_create requires a non-empty 'id' argument.",
            );
          }
          if (!worktreePath) {
            return clientError(
              "sandbox_create requires a non-empty 'worktree_path' argument.",
            );
          }

          const caps = await resolveCapabilities();

          if (caps.sandbox !== "ready" && caps.docker !== "ready") {
            return clientError(
              "sandbox_create: neither sandbox nor docker is available — cannot create compose backend.",
              KNOWN_BLOCKER_CODES.SANDBOX_UNAVAILABLE_NO_FALLBACK,
            );
          }

          const composeTestFile = await detectComposeFile(worktreePath);
          if (!composeTestFile) {
            return clientError(
              `sandbox_create: no compose test file at ${worktreePath} (expected docker-compose.test.yml or compose.test.yaml).`,
              KNOWN_BLOCKER_CODES.COMPOSE_TEST_FILE_MISSING,
            );
          }

          const envGate = await checkEnvGate(worktreePath);
          if (!envGate.ok) {
            return JSON.stringify({
              ok: false,
              status: 1,
              body: {
                sandbox_id: id,
                backend: caps.recommended_backend,
                compose_test_file: composeTestFile,
                blocker_code: KNOWN_BLOCKER_CODES.ENV_BLOCKED,
                recommended_env_fix:
                  envGate.recommended_fix ||
                  `Add a .env at ${worktreePath} (copy from main checkout).`,
                env_gate: envGate,
              },
            });
          }

          if (caps.sandbox === "ready") {
            const statusProbe = await execCapture("sandbox", [
              "status",
              "--id",
              id,
            ]);
            if (statusProbe.exit_code === 0) {
              const evidencePath = await writeEvidence(
                "sandbox_create",
                id,
                {
                  tool: "sandbox_create",
                  reused: true,
                  sandbox_id: id,
                  backend: "sandbox",
                  compose_test_file: composeTestFile,
                },
              );
              return JSON.stringify({
                ok: true,
                status: 200,
                body: {
                  sandbox_id: id,
                  backend: "sandbox",
                  compose_test_file: composeTestFile,
                  reused: true,
                  evidence_path: evidencePath,
                },
              });
            }

            const createRes = await execCapture("sandbox", [
              "create",
              "--id",
              id,
              "--worktree",
              worktreePath,
            ]);
            const evidencePath = await writeEvidence("sandbox_create", id, {
              tool: "sandbox_create",
              create: createRes,
              sandbox_id: id,
              backend: "sandbox",
              compose_test_file: composeTestFile,
            });
            if (!createRes.ok) {
              const blocker = /collision|exists|already/i.test(createRes.stderr)
                ? KNOWN_BLOCKER_CODES.SANDBOX_ID_COLLISION
                : KNOWN_BLOCKER_CODES.ENV_BLOCKED;
              return JSON.stringify({
                ok: false,
                status: 1,
                body: {
                  sandbox_id: id,
                  backend: "sandbox",
                  compose_test_file: composeTestFile,
                  blocker_code: blocker,
                  stderr_tail: tailString(createRes.stderr),
                  evidence_path: evidencePath,
                  recommended_env_fix: blocker ===
                    KNOWN_BLOCKER_CODES.SANDBOX_ID_COLLISION
                    ? "Pick a different sandbox_id or run sandbox_destroy on the colliding id."
                    : "sandbox create failed — inspect opencode-server sandbox logs.",
                },
              });
            }
            return JSON.stringify({
              ok: true,
              status: 200,
              body: {
                sandbox_id: id,
                backend: "sandbox",
                compose_test_file: composeTestFile,
                reused: false,
                evidence_path: evidencePath,
              },
            });
          }

          const evidencePath = await writeEvidence("sandbox_create", id, {
            tool: "sandbox_create",
            backend: "docker",
            sandbox_id: id,
            compose_test_file: composeTestFile,
            note: "Direct-Docker fallback — Sysbox sandbox unavailable; compose runs directly via docker compose.",
          });
          return JSON.stringify({
            ok: true,
            status: 200,
            body: {
              sandbox_id: id,
              backend: "docker",
              compose_test_file: composeTestFile,
              reused: false,
              evidence_path: evidencePath,
            },
          });
        },
      },

      sandbox_build: {
        description:
          "Build the compose test images (idempotent). Returns build_seconds + image_ids. Uses sandbox exec when sandbox: ready, direct docker compose otherwise.",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id (also used for the backend hint).",
          },
          compose_file: {
            type: "string",
            description:
              "Required. Path to docker-compose.test.yml (absolute, or relative to the worktree).",
          },
          worktree_path: {
            type: "string",
            description:
              "Optional. Absolute worktree root (forwarded as --cwd for sandbox exec, or as cwd for direct docker compose).",
          },
        },
        async execute(args) {
          const id = args && args.id;
          const composeFile = args && args.compose_file;
          const worktreePath = args && args.worktree_path;
          if (!id) {
            return clientError(
              "sandbox_build requires a non-empty 'id' argument.",
            );
          }
          if (!composeFile) {
            return clientError(
              "sandbox_build requires a non-empty 'compose_file' argument.",
            );
          }

          const caps = await resolveCapabilities();
          if (caps.sandbox !== "ready" && caps.docker !== "ready") {
            return clientError(
              "sandbox_build: neither sandbox nor docker is available.",
              KNOWN_BLOCKER_CODES.DOCKER_UNAVAILABLE,
            );
          }

          const dockerArgs = [...parseComposeFileArg(composeFile), "build"];
          const buildRes = caps.sandbox === "ready"
            ? await sandboxExec(id, dockerArgs, worktreePath)
            : await directDockerExec(dockerArgs, worktreePath);

          const evidencePath = await writeEvidence("sandbox_build", id, {
            tool: "sandbox_build",
            sandbox_id: id,
            compose_file: composeFile,
            backend: caps.sandbox === "ready" ? "sandbox" : "docker",
            build: buildRes,
          });

          if (!buildRes.ok) {
            return JSON.stringify({
              ok: false,
              status: 1,
              body: {
                sandbox_id: id,
                backend: caps.sandbox === "ready" ? "sandbox" : "docker",
                compose_file: composeFile,
                build_seconds: buildRes.duration_seconds,
                exit_code: buildRes.exit_code,
                stderr_tail: tailString(buildRes.stderr),
                blocker_code: KNOWN_BLOCKER_CODES.ENV_BLOCKED,
                evidence_path: evidencePath,
                recommended_env_fix:
                  "Inspect compose build errors (e.g. service 'test' missing, base image pull failure). Fix the compose file, then retry sandbox_build.",
              },
            });
          }

          return JSON.stringify({
            ok: true,
            status: 200,
            body: {
              sandbox_id: id,
              backend: caps.sandbox === "ready" ? "sandbox" : "docker",
              compose_file: composeFile,
              build_seconds: buildRes.duration_seconds,
              evidence_path: evidencePath,
              image_ids: extractImageIds(buildRes.stdout),
            },
          });
        },
      },

      sandbox_warm: {
        description:
          "Run the smoke command inside the compose service via sandbox exec. Replaces cold-boot-on-first-RED with an explicit warm run. Returns warm_run_seconds + exit_code + stdout_tail.",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id.",
          },
          compose_file: {
            type: "string",
            description: "Required. Compose test file path.",
          },
          service: {
            type: "string",
            description:
              "Required. Compose service name to run the smoke command in (typically 'test').",
          },
          smoke_command: {
            type: "string",
            description:
              "Required. JSON-encoded string[] — the command (and args) to run inside the compose service for the warm pass. Example: '[\"mise\",\"exec\",\"--\",\"bin/rails\",\"test\",\"test/test_helper.rb\"]'.",
          },
          worktree_path: {
            type: "string",
            description: "Optional. Absolute worktree root.",
          },
        },
        async execute(args) {
          const id = args && args.id;
          const composeFile = args && args.compose_file;
          const service = args && args.service;
          const worktreePath = args && args.worktree_path;
          const smokeCommandRaw = args && args.smoke_command;
          if (!id || !composeFile || !service || !smokeCommandRaw) {
            return clientError(
              "sandbox_warm requires id, compose_file, service, and smoke_command arguments.",
            );
          }
          let smokeCommand;
          try {
            smokeCommand = JSON.parse(smokeCommandRaw);
            if (!Array.isArray(smokeCommand)) {
              throw new Error("smoke_command must be a JSON array of strings");
            }
          } catch (err) {
            return clientError(
              `sandbox_warm: invalid smoke_command — ${err.message}`,
            );
          }

          const caps = await resolveCapabilities();
          if (caps.sandbox !== "ready" && caps.docker !== "ready") {
            return clientError(
              "sandbox_warm: neither sandbox nor docker is available.",
              KNOWN_BLOCKER_CODES.DOCKER_UNAVAILABLE,
            );
          }

          const dockerArgs = [
            ...parseComposeFileArg(composeFile),
            "run",
            "--rm",
            service,
            ...smokeCommand,
          ];
          const warmRes = caps.sandbox === "ready"
            ? await sandboxExec(id, dockerArgs, worktreePath)
            : await directDockerExec(dockerArgs, worktreePath);

          const evidencePath = await writeEvidence("sandbox_warm", id, {
            tool: "sandbox_warm",
            sandbox_id: id,
            compose_file: composeFile,
            service,
            smoke_command: smokeCommand,
            backend: caps.sandbox === "ready" ? "sandbox" : "docker",
            warm: warmRes,
          });

          return JSON.stringify({
            ok: warmRes.ok,
            status: warmRes.ok ? 200 : 1,
            body: {
              sandbox_id: id,
              backend: caps.sandbox === "ready" ? "sandbox" : "docker",
              compose_file: composeFile,
              service,
              smoke_command: smokeCommand,
              warm_run_seconds: warmRes.duration_seconds,
              exit_code: warmRes.exit_code,
              stdout_tail: tailString(warmRes.stdout),
              evidence_path: evidencePath,
              ...(warmRes.ok
                ? {}
                : {
                    blocker_code: KNOWN_BLOCKER_CODES.ENV_BLOCKED,
                    stderr_tail: tailString(warmRes.stderr),
                    recommended_env_fix:
                      "Warm run failed — inspect compose smoke output for toolchain / dependency issues, then retry sandbox_build + sandbox_warm.",
                  }),
            },
          });
        },
      },

      sandbox_run_test: {
        description:
          "Per-stage test runner. Wraps `sandbox exec --id ... -- docker compose -f <file> run --rm <service> <command>` (or direct docker compose). Used by test-writer (RED), developer (GREEN), and code-review (replay).",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id.",
          },
          compose_file: {
            type: "string",
            description: "Required. Compose test file path.",
          },
          service: {
            type: "string",
            description: "Required. Compose service name (typically 'test').",
          },
          command: {
            type: "string",
            description:
              "Required. JSON-encoded string[] — command + args to run inside the compose service.",
          },
          test_filter: {
            type: "string",
            description:
              "Optional. Test path or filter (e.g. 'test/models/user_test.rb'). Appended to the command verbatim if provided.",
          },
          worktree_path: {
            type: "string",
            description: "Optional. Absolute worktree root.",
          },
        },
        async execute(args) {
          const id = args && args.id;
          const composeFile = args && args.compose_file;
          const service = args && args.service;
          const commandRaw = args && args.command;
          const worktreePath = args && args.worktree_path;
          if (!id || !composeFile || !service || !commandRaw) {
            return clientError(
              "sandbox_run_test requires id, compose_file, service, and command arguments.",
            );
          }
          let command;
          try {
            command = JSON.parse(commandRaw);
            if (!Array.isArray(command)) {
              throw new Error("command must be a JSON array of strings");
            }
          } catch (err) {
            return clientError(
              `sandbox_run_test: invalid command — ${err.message}`,
            );
          }
          if (args.test_filter) {
            command = [...command, args.test_filter];
          }

          const caps = await resolveCapabilities();
          if (caps.sandbox !== "ready" && caps.docker !== "ready") {
            return clientError(
              "sandbox_run_test: neither sandbox nor docker is available.",
              KNOWN_BLOCKER_CODES.DOCKER_UNAVAILABLE,
            );
          }

          const dockerArgs = [
            ...parseComposeFileArg(composeFile),
            "run",
            "--rm",
            service,
            ...command,
          ];
          const runRes = caps.sandbox === "ready"
            ? await sandboxExec(id, dockerArgs, worktreePath)
            : await directDockerExec(dockerArgs, worktreePath);

          const evidencePath = await writeEvidence("sandbox_run_test", id, {
            tool: "sandbox_run_test",
            sandbox_id: id,
            compose_file: composeFile,
            service,
            command,
            test_filter: args.test_filter || null,
            backend: caps.sandbox === "ready" ? "sandbox" : "docker",
            run: runRes,
          });

          const summary = parseTestSummary(runRes.stdout);

          return JSON.stringify({
            ok: runRes.ok,
            status: runRes.ok ? 200 : 1,
            body: {
              sandbox_id: id,
              backend: caps.sandbox === "ready" ? "sandbox" : "docker",
              compose_file: composeFile,
              service,
              command,
              test_filter: args.test_filter || null,
              exit_code: runRes.exit_code,
              duration_seconds: runRes.duration_seconds,
              stdout_tail: tailString(runRes.stdout, 8000),
              passed: summary.passed,
              failed: summary.failed,
              assertion_delta: summary.assertion_delta,
              evidence_path: evidencePath,
            },
          });
        },
      },

      sandbox_status: {
        description:
          "Read-only sandbox status. Returns { sandbox_id, backend, running, compose_test_file, last_warm_at, last_build_at }.",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id.",
          },
        },
        async execute(args) {
          const id = args && args.id;
          if (!id) {
            return clientError(
              "sandbox_status requires a non-empty 'id' argument.",
            );
          }
          const caps = await resolveCapabilities();
          if (caps.sandbox !== "ready") {
            return JSON.stringify({
              ok: true,
              status: 200,
              body: {
                sandbox_id: id,
                backend: "docker",
                running: false,
                compose_test_file: null,
                last_warm_at: null,
                last_build_at: null,
                note: caps.sandbox === "unavailable"
                  ? "Sandbox CLI unavailable; direct-Docker backend (compose images persist between runs; status is implicit)."
                  : "Sandbox CLI enabled but not currently installed on PATH.",
              },
            });
          }

          const statusRes = await execCapture("sandbox", [
            "status",
            "--id",
            id,
          ]);
          return JSON.stringify({
            ok: statusRes.ok,
            status: statusRes.ok ? 200 : 1,
            body: {
              sandbox_id: id,
              backend: "sandbox",
              running: statusRes.ok,
              compose_test_file: null,
              last_warm_at: null,
              last_build_at: null,
              stderr_tail: statusRes.ok ? null : tailString(statusRes.stderr),
            },
          });
        },
      },

      sandbox_destroy: {
        description:
          "Destroy a sandbox. Owned exclusively by worktree-sandbox (mode: teardown) and code-review per docker-sandbox §5 (APPROVED / ENV_BLOCKED).",
        args: {
          id: {
            type: "string",
            description: "Required. Sandbox id to destroy.",
          },
          unexpose: {
            type: "boolean",
            description:
              "Optional. When true (default), run `sandbox unexpose --id <id>` before destroy.",
          },
          compose_file: {
            type: "string",
            description:
              "Optional. When present + backend is direct-docker, also runs `docker compose -f <file> down` to release compose resources.",
          },
          worktree_path: {
            type: "string",
            description: "Optional. Absolute worktree root (for docker compose down cwd).",
          },
        },
        async execute(args) {
          const id = args && args.id;
          if (!id) {
            return clientError(
              "sandbox_destroy requires a non-empty 'id' argument.",
            );
          }
          const unexpose = args && args.unexpose !== false;
          const composeFile = args && args.compose_file;
          const worktreePath = args && args.worktree_path;

          const caps = await resolveCapabilities();
          const events = [];

          if (caps.sandbox === "ready" && unexpose) {
            const unexposeRes = await execCapture("sandbox", [
              "unexpose",
              "--id",
              id,
            ]);
            events.push({ step: "unexpose", ok: unexposeRes.ok });
          }

          let destroyRes = { ok: true, exit_code: 0, stderr: "", duration_seconds: 0 };
          if (caps.sandbox === "ready") {
            destroyRes = await execCapture("sandbox", [
              "destroy",
              "--id",
              id,
            ]);
            events.push({ step: "sandbox_destroy", ok: destroyRes.ok });
          }

          let downRes = null;
          if (composeFile) {
            const opts = worktreePath ? { cwd: worktreePath } : {};
            downRes = await execCapture(
              "docker",
              ["compose", "-f", composeFile, "down"],
              opts,
            );
            events.push({ step: "docker_compose_down", ok: downRes.ok });
          }

          const allOk = events.every((e) => e.ok);
          const evidencePath = await writeEvidence("sandbox_destroy", id, {
            tool: "sandbox_destroy",
            sandbox_id: id,
            events,
            backend: caps.sandbox === "ready" ? "sandbox" : "docker",
          });

          return JSON.stringify({
            ok: allOk,
            status: allOk ? 200 : 1,
            body: {
              sandbox_id: id,
              backend: caps.sandbox === "ready" ? "sandbox" : "docker",
              destroyed_at: new Date().toISOString(),
              events,
              evidence_path: evidencePath,
              ...(allOk
                ? {}
                : {
                    stderr_tail: tailString(
                      (destroyRes.stderr || "") +
                        (downRes ? "\n" + downRes.stderr : ""),
                    ),
                  }),
            },
          });
        },
      },
    },
  };
};

async function checkEnvGate(worktreePath) {
  const dotEnvPath = path.join(worktreePath, ".env");
  let present = false;
  try {
    const stat = await fs.stat(dotEnvPath);
    present = stat.isFile() && !stat.isSymbolicLink();
  } catch {
    present = false;
  }
  if (present) {
    return { ok: true };
  }
  return {
    ok: false,
    recommended_fix: `Copy .env from main checkout to ${dotEnvPath} (regular file, not symlink).`,
  };
}

function extractImageIds(stdout) {
  if (!stdout) return [];
  const ids = [];
  for (const line of stdout.split(/\r?\n/)) {
    const m = line.match(/\b([0-9a-f]{12,64})\b/);
    if (m) ids.push(m[1]);
  }
  return ids;
}

function parseTestSummary(stdout) {
  if (!stdout) return { passed: null, failed: null, assertion_delta: null };
  const passedMatch = stdout.match(/(\d+)\s+pass(?:ed|ing)?/i);
  const failedMatch = stdout.match(/(\d+)\s+fail(?:ed|ing|ure)?/i);
  const passed = passedMatch ? Number(passedMatch[1]) : null;
  const failed = failedMatch ? Number(failedMatch[1]) : null;
  let assertion_delta = null;
  if (passed !== null || failed !== null) {
    assertion_delta = {
      passed,
      failed,
      total: (passed || 0) + (failed || 0),
    };
  }
  return { passed, failed, assertion_delta };
}
