# OpenCode Workflow

Shared vocabulary for spec-driven, GitHub-issue-backed delivery using the OpenCode agent pipeline in this config repo.

## Language

**Spec feature**:
A multi-repo product change planned in the spec repo (PRD → fanout → child issues in implementation repos).
_Avoid_: Big feature, epic file, `.plan/feature.*`

**Targeted change**:
A smaller, single-repo change planned directly in one implementation repo (issues created via `to-issues`, no PRD).
_Avoid_: Legacy plan, local feature file, ad-hoc `.plan`

**Spec repo**:
The `APP-spec` sibling repository holding PRDs, registry (`docs/agents/repos.md`), and product glossary (`CONTEXT.md`, `LANGUAGE.md`).
_Avoid_: Docs repo, planning folder

**Implementation repo**:
A sibling repo (`APP-web`, `APP-api`, `APP-ingest`, …) containing application code and operational config only — not work-tracking artifacts.
_Avoid_: Target repo, code repo (when meaning impl)

**Fanout**:
The spec-repo action that creates GitHub child issues in target implementation repos from an approved PRD's `tickets:` list.
_Avoid_: Issue export, ticket dump

**Issue-expand**:
Implementation-repo planning that enriches fanout (or targeted) issues with Implementation planning sections and TDD `stages[]` in `opencode-task-yaml`.
_Avoid_: Local issue plan, `.plan/issue.*`

**Stage**:
One TDD slice within an issue's `stages[]` array; orchestrate dispatches `developer`/`frontend-dev` per stage with `execution_mode: github_issue_stage`.
_Avoid_: Step, phase file

**GitHub-as-source-of-truth**:
Every planned unit of work exists as a GitHub issue before implementation; commits reference or close issues (`Refs:` / `Closes:`). No local `.plan/` work files in any repo.
_Avoid_: Plan file, local backlog

## Relationships

- A **Spec feature** lives in the **Spec repo** as a PRD and produces **Fanout** child issues in one or more **Implementation repos**
- A **Targeted change** skips the PRD and creates issues directly in one **Implementation repo**
- **Issue-expand** runs in an **Implementation repo** before orchestrate picks up the queue
- **Orchestrate** runs **Stages** sequentially until the issue is ready-for-review
- **Feature-complete** (spec repo) closes the spec parent issue after all impl repos finish

## Example dialogue

> **Operator:** "I want to tweak the web header layout — no PRD."
> **Architect:** "That's a **Targeted change** in `APP-web`. I'll create GitHub issue(s) via **to-issues**, optionally **issue-expand** for TDD stages, then: *Next step: create a new session in orchestrate…*"

> **Operator:** "Ship the new billing flow across API and web."
> **Architect:** "That's a **Spec feature**. We'll **grill-me** → **to-prd** → fanout, then **issue-expand** in each impl repo — then a **new orchestrate session** per impl repo (`feature:<slug>`)."

## Flagged ambiguities

- "Feature" alone may mean a GitHub label (`feature:<slug>`), a **Spec feature**, or a **Targeted change** — use the qualified terms above.
- "Legacy" in older docs meant local `.plan` files; that path is removed. Use **Targeted change** for small single-repo work instead.
