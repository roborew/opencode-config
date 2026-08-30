# OpenCode Workflow

Shared vocabulary for spec-driven, GitHub-issue-backed delivery using the OpenCode agent pipeline in this config repo.

## Language

**Spec feature**:
A multi-repo product change planned in the spec repo (PRD → fanout → child issues in implementation repos).
_Avoid_: Big feature, epic file, `.plan/feature.*`

**Targeted change**:
A smaller, single-repo change planned directly in one implementation repo (issues created via `to-issues`, no PRD).
_Avoid_: Legacy plan, local feature file, ad-hoc `.plan`

**Wayfinder map**:
A strategic planning index issue (`wayfinder:map` label) in the spec repo that holds decision tickets for a foggy / multi-session idea. Upstream of a Spec feature when the destination is a PRD.
_Avoid_: Local map file, planning folder, "raw idea doc"

**Decision ticket**:
A child issue of a wayfinder map labelled `wayfinder:<type>` (`research` | `prototype` | `grilling` | `task`). Resolved by a decision, not a build slice. Impl execution never lives here.
_Avoid_: Fanout ticket (those are execution, not planning)

**Fog of war** (wayfinder term):
In-scope questions on a wayfinder map that are not yet sharp enough to ticket. Lives in the map's `## Not yet specified`. Graduates into tickets as the frontier advances.
_Avoid_: Unknown unknown, hidden backlog

**Frontier** (wayfinder term):
The set of open, unblocked, unassigned children of a wayfinder map — the edge of the known on a wayfinder effort.
_Avoid_: Ready-to-do list, work queue

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
One TDD slice within an issue's `stages[]` array; orchestrate dispatches `developer`/`frontend-dev`/`ux-dev` per stage with `execution_mode: github_issue_stage`.
_Avoid_: Step, phase file

**GitHub-as-source-of-truth**:
Every planned unit of work exists as a GitHub issue before implementation; commits reference issues (`Refs:`). Issues close at Spec merge via **feature-complete**. No local `.plan/` work files in any repo.
_Avoid_: Plan file, local backlog

**Phase R**:
Impl architect Mode F step that triages post-PR feedback (hosted review comments, CI failures, incomplete tickets, user feedback) and publishes remediation sub-issues before acceptance. Re-enter via **impl architect option 4 → R** after orchestrate remediation push.
_Avoid_: Post-merge review only, spec sign-off

**Remediation ticket**:
A `remediation:` prefixed GitHub issue in an impl repo, linked as a PRD sub-issue, created during Phase R for orchestrate to execute.
_Avoid_: Ad-hoc fix list, review sidecar only

**Merge gate**:
Spec feature-complete step where the user chooses manual PR merge or agent merge on their behalf, with protected-branch-safe head deletion.
_Avoid_: Auto-merge, silent close

**Close-at-merge**:
Policy that impl repos only transition `state:*` labels; GitHub issue **close** happens in spec feature-complete when PRs merge.
_Avoid_: Close on accept, progressive close in impl

**Claude Context (indexing)**:
Optional semantic code index via `mcp.claude-context` in `opencode.json`. Speeds discovery; OpenCode works without it (`MCP_FALLBACK`). **Host vs Docker:** `enabled: true` only for local-only Desktop/CLI; keep `enabled: false` on the host when attached to the Docker OpenCode server (container + Milvus indexes instead). Never enable both.
_Avoid_: Running host and server `claude-context` together

**Sandbox (Sysbox sibling)**:
Optional opencode-server feature: ephemeral Sysbox sibling containers via the `sandbox` CLI for self-contained compose build/test (app + Caddy) and optional review publish. Gated by `OPENCODE_SANDBOX_ENABLED`; typically off on Mac. Agents use only the CLI — never invent host `docker.sock` or ad-hoc `sysbox-runc`. Preflight only probes; create/exec/expose/destroy live in skill `docker-sandbox`. **Orchestrate does not load that skill** — it instructs `developer` / `frontend-dev` / `code-review` Tasks to load it when compose/Docker/review URL applies, and menu **(2)** runs **Sandbox feature build mode** (build/refresh current branch without the issue queue). Unrelated to Cloudflare Workers Sandbox under `skills/cloudflare/references/sandbox/`.
_Avoid_: Mounting host Docker socket into app compose; GPU/CUDA in sandbox; forcing Sysbox on Desktop; cloudflared in app compose; expecting orchestrate to run `sandbox` CLI itself

**Review hostname**:
Public feature review URL pattern `{feature-slug}.{apex}` (e.g. `blockshed.blockshared.com`), where apex comes from repo `review_domain` / `apex_domain` (or README). Nested Caddy is published to `127.0.0.1:<hostPort>` via `sandbox expose`; host cloudflared serves a public hostname on the **existing** tunnel; agents may create/update **tunnel public hostname + DNS**. Tunnel public hostname must use **service type HTTPS**, URL `https://127.0.0.1:<hostPort>`, and **No TLS Verify ON** — never HTTP service type (browsers need HTTPS). Orchestrate asks **“Publish review URL?”** once before instructing expose.
_Avoid_: Global `reviews.*` suffix; `cloudflared tunnel create`; HTTP tunnel service type for review hostnames

**App vs server Infisical**:
OpenCode **server** Infisical injects secrets into the OpenCode process only. **App** Infisical for sandbox Compose comes from the mounted repo `.env` (setup create + paste). Sibling must reach Infisical over the network.
_Avoid_: Assuming server Infisical populates app Compose; copying `.env.example` into `.env`

## Relationships

- A **Spec feature** lives in the **Spec repo** as a PRD and produces **Fanout** child issues in one or more **Implementation repos**
- A **Targeted change** skips the PRD and creates issues directly in one **Implementation repo**
- A **Wayfinder map** lives in the **Spec repo** as a `wayfinder:map` issue and holds **Decision tickets** (planning, not execution). When the map's destination is a PRD, it feeds a **Spec feature** — chart map → resolve tickets → clear frontier → `to-prd` (skipping `grill-me`) → fanout → issue-expand → orchestrate. Decision tickets are **not** fanout tickets (planning vs execution).
- **Issue-expand** runs in an **Implementation repo** before orchestrate picks up the queue
- **Orchestrate** runs **Stages** sequentially until the issue is ready-for-review
- **Impl architect Mode F** runs Phase R → accept (`state:done`, open) → docs
- **Feature-complete** (spec repo) closes child issues at merge, merges PRs, and closes the spec parent issue

## Example dialogue

> **Operator:** "I want to tweak the web header layout — no PRD."
> **Architect:** "That's a **Targeted change** in `APP-web`. I'll create GitHub issue(s) via **to-issues**, optionally **issue-expand** for TDD stages, then provide a table handoff with the exact issue/feature target and copy/paste `orchestrate` prompt."

> **Operator:** "Ship the new billing flow across API and web."
> **Architect:** "That's a **Spec feature**. We'll **grill-me** → **to-prd** → fanout, then **issue-expand** in each impl repo — then a **new orchestrate session** per impl repo (`feature:<slug>`)."

## Flagged ambiguities

- "Feature" alone may mean a GitHub label (`feature:<slug>`), a **Spec feature**, or a **Targeted change** — use the qualified terms above.
- "Decision ticket" / "wayfinder ticket" is **planning** (a question whose resolution is a decision), distinct from a **fanout ticket** / **PRD child issue** (which is **execution** — a build slice). Don't confuse the two; a wayfinder map can clear without ever producing a fanout ticket (e.g. destination = locked decision or in-place change).
- "Legacy" in older docs meant local `.plan` files; that path is removed. Use **Targeted change** for small single-repo work instead.
