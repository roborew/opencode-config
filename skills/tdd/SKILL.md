---
name: tdd
description: "Strict Red → Green → Refactor; commit after each green cycle"
---

## TDD loop

1. **Red** — write one failing test for the next smallest behavior.
2. **Green** — minimal code to pass.
3. **Refactor** — clean up with tests green.
4. **Commit** — after green+refactor cycle completes for this slice.

## Order of cases

Degenerate → happy path → variations → edge cases → errors.

## Rules

- One logical behavior change per red test when possible.
- Never “fix” by deleting the failing test without user agreement.
- Editing an existing assertion to match new code is **not** a green. Add or adjust a test that is RED first, or list and justify the assertion change explicitly (`assertion_delta`). A replaced positive assertion in the same commit is a smell, not a green.
- Keep the same test identifier across RED and GREEN so the failing-then-passing transition is verifiable by the parent/verifier.
