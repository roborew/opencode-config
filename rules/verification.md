# Verification convention (Docker-default)

Scope: how implementation is verified across orchestrate, developer, and code-review.

## Principle

Verification runs in a **reproducible Docker environment**, never on the host as the
primary path. This removes the host-toolchain gap (e.g. Ruby/mise/bundle missing on a
subagent host) that previously incentivized bypassing the code-review gate.

## Contract

- Every project with `test_commands` ships a **`docker-compose.test.yml`** (or
  `compose.test.yaml`) at the repo root.
- The compose file defines a **`test` service** that runs the project's
  `test_commands` self-contained, OR provides sufficient tooling to mock external
  dependencies.
- The compose file **volume-mounts the project source** so uncommitted edits are
  tested without a rebuild.
- Cleanup: `docker compose -f docker-compose.test.yml down` in a finally path.

## Backends (same compose file)

| Environment | Backend | Command |
|-------------|---------|---------|
| opencode-server | Sysbox sibling | `sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml run --rm test` |
| Local dev / Mac | Docker Desktop | `docker compose -f docker-compose.test.yml run --rm test` |

Probe order: `sandbox probe` → `sandbox exec`; else `docker` present → direct
`docker compose`; else `BLOCKED` (do not silently fall back to host).

## Enforcement

- **Readiness gate** (`orchestrate-readiness-check`): FAILs a project that defines
  `test_commands` but has no compose test file — it cannot enter the orchestrate loop.
- **Preflight**: records `compose_test_file`, `docker`, `sandbox`, and
  `verification_gap`.
- **Code-review**: runs `test_commands` via the Docker path by default. Host execution is
  only APPROVED-eligible when the user explicitly approves it for a confirmed
  host-runnable project.
- **Code-review gate backstop** (`issue-state-transition.sh`): refuses
  `state:ready-for-ticket-review` without a `code_review_gate:` comment with
  `all_stages: true` and `verdict: APPROVED`.

## Migration

Existing projects must add a `docker-compose.test.yml` before they can be orchestrated.
Use `templates/project-stub/docker-compose.test.yml` as the starting point.
