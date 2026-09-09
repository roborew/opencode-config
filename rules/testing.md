# Testing conventions

- Prefer behavior-focused tests over implementation details.
- Arrange–Act–Assert; one primary assertion per test when practical.
- Mock only at system boundaries (network, clock, filesystem); prefer real implementations elsewhere.
- After code changes, run the narrowest test that proves the fix (file or suite), not the whole repo unless needed.
- Do not skip or delete failing tests to “go green”—fix or mark explicit pending with reason.
- When preflight/skill reports `sandbox: ready` and the repo documents compose tests, code-review may accept `sandbox exec` logs as equivalent evidence to local test runners.
- **The compose test file (`docker-compose.test.yml` / `compose.test.yaml`) is the only sanctioned test backend** — all RED/GREEN/final-gate test execution runs through `sandbox exec` (opencode-server) or direct `docker compose -f <file>` (local dev). Host-local suite setup is forbidden (no host npm/pip installs to "get tests running"); `compose_test_file: none` halts the ticket with `ENV_BLOCKED` + `recommended_env_fix: add docker-compose.test.yml`.

## Per-slice TDD commit contract

For every `stages[]` slice:

1. `test-writer` adds or updates only the test-side files and runs the focused test through the sanctioned compose backend, proving the test fails for the intended reason.
2. Commit that failing test as a **test-only RED commit**. The RED commit must contain no production changes.
3. The stage owner implements the behavior in a separate **production-only GREEN commit**. The GREEN commit must contain no test changes and must be tested through the same backend before handoff.
4. If a test needs to be corrected or expanded, make each amendment a separate test-only commit, distinct from both RED and GREEN; rerun the relevant evidence after the amendment.
5. `code-review` validates the RED/GREEN commit pair and any separately listed test-amendment commits against the stage scope and acceptance criteria. A passing test run without this commit evidence is not a complete stage handoff.
