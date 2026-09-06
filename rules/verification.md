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
  `state:ready-for-ticket-review` without a `code_review_gate:` comment whose
  `all_stages:` field is exactly `true`, whose `verdict:` field is exactly
  `APPROVED`, and whose `author.login` matches `${OPENCODE_CODER_AUTHOR}`
  when set, AND the `verified` label. Refuses `state:ticket-reviewed` if
  `verified` was dropped in between (outbound guard against out-of-band
  merges without gate evidence — the #247-class drift). The `OPENCODE_CODER_AUTHOR`
  env var is empty by default; an empty value bypasses the author check so
  legacy repos stay functional, but every impl repo should set it in its
  opencode config — the BLOCKED message echoes the configured value so
  operators can see what was expected.
- **Verification label is binary.** Every `feature:<slug>` (and targeted /
  remediation) issue carries exactly one of `verified` or `unverified` at all
  observable moments. The pair is centralized in `scripts/issue-state-transition.sh`,
  which enforces the swap on every state transition, and the coder calls
  `scripts/issue-verified-transition.sh` (delegated `developer` Task) to add
  `verified` on `code-review` APPROVED — these are the only two writers. Do
  **not** run `gh issue edit --add-label verified` directly anywhere; the
  inline `--add-label` leaves `unverified` in place and creates the duplicate
  pair. To clean up existing duplicates, the operator must run a one-off
  `gh issue edit --remove-label verified --add-label unverified` (or
  vice-versa) per offending issue — the binary pair itself is enforced
  centrally on every subsequent state transition.

## Migration

Existing projects must add a `docker-compose.test.yml` before they can be orchestrated.
Use `templates/project-stub/docker-compose.test.yml` as the starting point.
