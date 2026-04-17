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
