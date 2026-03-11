# .plan Artifact Schema

All `.plan/<type>.<slug>.md` files follow this minimal structure. Assessor agents produce them; writer agents consume them.

## Required Sections

| Section | Purpose |
|---------|---------|
| **Context** | Brief background, constraints, and assumptions |
| **Goal** | One-sentence objective |
| **Tasks** | Numbered list of concrete steps to execute |
| **FilesToChange** | Paths and brief explanation per file |
| **AcceptanceChecks** | How to verify completion (tests, commands, criteria) |
| **Risks** | Known risks, rollback notes |
| **OutOfScope** | Explicitly excluded work |

## Artifact Types

- `plan.<slug>.md` — Feature implementation (from Plan agent)
- `debug.<slug>.md` — Bug fix (from Debugger agent)
- `refactor.<slug>.md` — Refactor migration (from Refactorer agent)
- `review.<slug>.md` — PR review changes (from PR Reviewer agent)

## Example Skeleton

```markdown
# <Type>: <Name>

## Context
...

## Goal
...

## Tasks
1. ...
2. ...

## FilesToChange
- path/to/file.ts: explanation
- ...

## AcceptanceChecks
- Run `npm test`
- ...

## Risks
- ...

## OutOfScope
- ...
```
