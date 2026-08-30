---
name: wayfinder
description: "Chart a big, foggy idea as a shared map of decision tickets in the spec repo's GitHub issues; resolve one ticket per session until the way to the destination (usually a PRD) is clear. Upstream of grill-me/to-prd."
disable-model-invocation: true
modelTier: smart
roleReminder: "Spec repo only. Map + tickets are GitHub issues via opencode-run spec wayfinder-map and opencode-run spec wayfinder-ticket (never raw gh issue create/edit/close/comment). Plan, don't do; hand off to to-prd when the way is clear."
---

# Wayfinder

Adapted from Matt Pocock's [`wayfinder`](https://github.com/mattpocock/skills/tree/main/skills/engineering/wayfinder) skill for this config's **GitHub-as-source-of-truth, spec-repo** workflow. A loose idea has arrived, too big for one `grill-me` session, and wrapped in fog. Wayfinder charts the way as a **shared map** on the spec repo's GitHub issue tracker, then works its **decision tickets** one per session until the route to the **destination** is clear.

The destination is named first and shapes every ticket. It might be a PRD to hand off and iterate on, a decision to lock before planning starts, or a change made in place (e.g. a data-structure migration). The map is domain-agnostic.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision; the map is done when the way is clear, with nothing left to decide before someone goes and does the thing. The pull to "just do the work" is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its `## Notes`, carrying execution into the map itself, but absent that, produce decisions, not deliverables.

A `task` ticket **unblocks a decision**; it is **not** impl execution. Impl execution happens later via fanout → issue-expand → orchestrate, not here.

## Refer by name

Every map and ticket is an issue, so it has a **name**: its title. In everything the human reads (narration, the map's `## Decisions so far`), refer to it by name, never by a bare id/number/slug. A wall of `#42, #43, #44` is illegible; names read at a glance. The id and URL don't vanish — a name wraps its link, but they ride *inside* the name, never stand in for it.

## Tracker = GitHub, home = spec repo

- The **map** is a single issue in the **spec repo** labelled `wayfinder:map`. Its **tickets** are **child issues** of the map (`gh issue create --parent <map>`) labelled `wayfinder:<type>`.
- **Frontier** = open, unblocked, unassigned children of the map. Query with `gh issue list --search "is:open is:issue parent:<map-issue> no:assignee" --label wayfinder:<type> ...`.
- **Blocking** uses GitHub's native dependency relationship when the API supports it (`updateIssue.blockedByIds`); the script always also writes a `Blocked by: #N` line in the ticket body so the frontier stays legible even if native edges fail. Trackers lacking native blocking are handled by the body line alone.
- **Map + tickets are the canonical artifacts.** Linked assets (research notes, prototype files) live in this repo as files (`.research/<slug>.md`, `.prototype/<slug>/`), are linked from the ticket, and are **never** pasted into the ticket body.

## Publishing — never raw `gh issue create`

Architect bash denies raw `gh issue create`/`edit`/`close`/`comment`. Use these approved wrappers (all auto-discovered by `opencode-run`):

| Intent | Command |
|--------|---------|
| Create / update map | `opencode-run spec wayfinder-map --create [--slug <s>] --body-file <p>` / `--update <issue> --body-file <p>` |
| Create ticket | `opencode-run spec wayfinder-ticket --create --map <map-issue> --type <research\|prototype\|grilling\|task> --title <t> --body-file <p> [--blocked-by <n>...] [--assignee <user>]` |
| Wire blocking (second pass) | `opencode-run spec wayfinder-ticket --link <issue> --blocked-by <n>...` |
| Claim | `opencode-run spec wayfinder-ticket --claim <issue> --assignee <user>` |
| Resolution comment | `opencode-run spec wayfinder-ticket --comment <issue> --body-file <p>` |
| Close | `opencode-run spec wayfinder-ticket --close <issue>` |

**Fallback:** Task **`developer`** with `load: minimal` carrying the same `opencode-run` command. Never paraphrase the command, never drop the wrapper.

## Body transport (scratch files)

`opencode-run spec wayfinder-*` accepts a `--body-file` so the body never has to be passed through argv. The skill does not own the file:

1. Task **`scribe`** with `load: full` to write the body to scratch `tmp/wayfinder/<slug>-{map,ticket-<id>}.md` (gitignored — see `README.md` "Agent scratch `.gitignore`"). `tmp/**` is in scribe's allowed write paths via the `tmp/` allowance under "AGENTS.md" doc categories; if a future scribe hardening removes `tmp/**`, scribe must be re-allowed for that path before continuing. Map bodies and ticket bodies are always canonical in GitHub; the scratch file is non-canonical transport.
2. Pass `--body-file <that-path>` to the wrapper.
3. After success, the wrapper returns the URL; you may delete the scratch file in a follow-up scribe task or leave it to `tmp/` hygiene.

If scribe's write fails, fix the path allowlist before retrying — never paste bodies through `gh issue create --body "..."` (architect bash would deny the redirect; even if it didn't, it's a hygiene regression).

## The Map

The map is an **index**, not a store. It lists the decisions made and points at the tickets that hold their detail; a decision lives in exactly one place, its ticket, so the map never restates it, only gists it and links.

### Map body template

```markdown
## Destination

<what reaching the end of this map looks like. One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences. May also name the destination shape (PRD vs locked decision vs in-place change).>

## Decisions so far

<!-- index: one line per closed ticket, gist + link to the ticket that holds the detail -->

- [<closed ticket title>](link): <one-line gist of the answer>

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
```

### Updating the map

Every session that closes a ticket also updates the map:

1. Task **`scribe`** to draft the new map body (append the closed ticket's one-line gist to `## Decisions so far`, graduate any fog from `## Not yet specified`, rule out-of-scope from `## Out of scope`).
2. Run `opencode-run spec wayfinder-map --update <map-issue> --body-file <scratch-path>`.

Map updates are idempotent; you can re-run with the same body to recover from a failed edit.

## Tickets

Each ticket is a **child issue** of the map; its number is its identity. Its body is the question, sized to one session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Tickets carry a `wayfinder:<type>` label (`research` | `prototype` | `grilling` | `task`). A session **claims** a ticket by assigning it to itself **first**, before any work, so concurrent sessions skip it. That assignee *is* the claim.

**Blocking:** wire in `--create` when all blockers are already numbered. If a fresh ticket must block on a sibling not yet created, create both tickets with `--create` (one without `--blocked-by` since the blocker doesn't exist yet), then run `--link <new-ticket> --blocked-by <existing-ticket>` as a second pass. The script writes both the native edge and the `Blocked by: #N` body line.

A ticket is **unblocked** when every blocker is closed; the **frontier** is open, unblocked, unassigned children.

**Resolution:** the answer isn't part of the body — it lives on the closed ticket as a **resolution comment** posted via `--comment`. Then `--close`. Then update the map (`--update` with a fresh body).

Assets created while resolving a ticket are linked from the issue, never pasted.

## Skill-to-skill mapping (this config)

| Matt's `wayfinder` call | This config's skill |
|---|---|
| `Skill tool "grilling"` **and** `Skill tool "domain-modeling"` | `Skill tool "grill-me"` (**once**) — `grill-me` already embeds domain-modeling (glossary + ADRs via scribe). Do **not** call `grill-me` twice. |
| `Skill tool "research"` | `Skill tool "research"` — unchanged. AFK research tickets dispatch helper tasks in parallel; scribe writes findings to `.research/<ticket-slug>.md`; link from the ticket. |
| `Skill tool "prototype"` | `Skill tool "prototype"` — companion skill. HITL. Scribe (outline / rough take / stub → `tmp/` or `.prototype/<slug>/`) or Task **`ux-dev`** (HTML UI → `.prototype/<slug>/` using `docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md`); link asset from ticket. |

## Ticket Types

Every ticket is **HITL** (worked *with* a human who speaks for themselves) or **AFK**, driven by the agent alone.

- **Research** (AFK): Reading docs / APIs / local resources. Task **`research`** subagents in **parallel** for every `research` ticket you just created; capture findings via **`scribe`** to `.research/<ticket-slug>.md`; link the file from the ticket. **One exception to the one-ticket-per-session rule:** research tickets may all be resolved in the same session that creates them.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, throwaway artifact (outline, rough take, stub, or UI/logic code) via the `prototype` skill. Link the asset from the ticket; do not paste.
- **Grilling** (HITL): Conversation. Default. Load **`grill-me`** (which embeds domain-modeling) — once.
- **Task** (HITL or AFK): Manual work that must happen before a *decision* can be made — nothing to decide/prototype/research yet, but the discussion is blocked. Signing up for a service, provisioning access, moving data. Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, URLs, row counts) later tickets depend on. **Task tickets unblock decisions, they don't deliver the destination.** Impl execution stays in fanout/orchestrate.

## Fog of war

The map is deliberately incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war**: the dim view of decisions you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets, one at a time.

The map's `## Not yet specified` section is where that dim view is written down. **Fog or ticket?** The test is whether you can state the question precisely now, *not* whether you can answer it now.

- **Ticket when** the question is already sharp, even if blocked.
- **Not yet specified when** you can't phrase it that sharply.

## Out of scope

Fog only ever gathers *toward* the destination. Work beyond the destination is **out of scope**: not fog, belongs in `## Out of scope`. Out-of-scope work never graduates; it returns only if the destination is redrawn. When a ticket that already exists turns out to sit past the destination, **close it** (a closed ticket is unambiguously off the frontier) and leave one line in `## Out of scope`: the gist plus why it's out of scope, linking the closed ticket. It stays out of `## Decisions so far`, which records the route actually walked; a scope boundary isn't a step on it.

## Invocation (two modes)

Either way, **never resolve more than one ticket per session** — except research tickets, which may all be resolved in the session that creates them.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Load `grill-me` (it embeds domain-modeling). Pin down what this map is finding its way to: the spec, decision, or in-place change.
2. **Map the frontier.** `grill-me` again, **breadth-first**: fan out across the whole space rather than deep on any one thread. Surface the open decisions and the first steps takeable now. **If this surfaces no fog** (the way to the destination is already clear, the whole journey small enough for one session), you don't need a map — stop and ask the user how they'd like to proceed (likely: jump straight to `to-prd` or `to-tickets`).
3. **Create the map:** Task `scribe` writes the body to `tmp/wayfinder/<slug>-map.md`; `opencode-run spec wayfinder-map --create --slug <slug> --body-file <that-path>`. Capture the returned map URL.
4. **Create tickets** you can specify now as child issues of the map via `opencode-run spec wayfinder-ticket --create --map <map-issue> --type <type> --title <t> --body-file <p> [--blocked-by <n>...]`. Wire blocking in a **second pass** with `--link` after ids exist. Everything not yet specifiable stays in the fog (`## Not yet specified`).
5. **Fire the research subagents.** For each `research` ticket you just created, dispatch helper / research tasks in parallel; findings via scribe to `.research/<ticket-slug>.md`; link the file from each ticket (resolution comment, not body).
6. **Stop.** Charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map URL or number. A ticket is **optional**: without one, pick the next frontier ticket, not the user.

1. Load the **map** (low-res view): `gh issue view <map-issue> --repo <spec-repo>`. The script's `--update` mode is for editing; `gh issue view` is read-only and always allowed.
2. **Choose** the ticket. If the user named one, use it. Otherwise take the first frontier ticket in order.
3. **Claim it first:** `opencode-run spec wayfinder-ticket --claim <issue> --assignee <user>` (or Task `developer load: minimal` with the same command). **Never** skip the claim step — unassigned tickets are visible to every concurrent session.
4. **Resolve it.** Zoom as needed (`gh issue view <other-issue> ...`); load `grill-me` / `research` / `prototype` as the ticket type demands. If unsure whether the question is sharp enough to ticket, the ticket is wrong — escalate to map update.
5. **Record the resolution:** Task `scribe` writes the answer to scratch `tmp/wayfinder/<slug>-ticket-<n>.md`; `opencode-run spec wayfinder-ticket --comment <issue> --body-file <that-path>`; then `opencode-run spec wayfinder-ticket --close <issue>`.
6. **Update the map:** Task `scribe` drafts the new body (append closed-ticket gist to `## Decisions so far`, graduate any fog from `## Not yet specified`, rule out-of-scope to `## Out of scope`); `opencode-run spec wayfinder-map --update <map-issue> --body-file <that-path>`.
7. If the answer invalidates other parts of the map, close those tickets (don't resolve them on the route) and update the map to reflect.

The user may run unblocked tickets in parallel; expect other sessions to be editing the tracker concurrently. Claim-by-assignee prevents double work; native blocking + the `Blocked by: #N` body line both keep the frontier legible.

## Completion handoff

When the map clears and the destination is a PRD → **load `to-prd` in the same session** (skip `grill-me` — tickets already grilled the design tree). The new PRD's `## Linked artifacts` cites the closed decision tickets.

If the destination is a **locked decision** or an **in-place change**, declare the route clear and stop. Do not silently re-scope the destination.

## Hard rules

1. **Spec repo only.** Run wayfinder inside the spec repo (cwd has `docs/prd/` or the registered spec layout). Do not invoke from impl repos.
2. **Plan, don't do.** Tickets resolve decisions. `task` tickets unblock decisions only — never deliver the destination; impl execution lives in fanout/orchestrate.
3. **GitHub is canonical.** Map + tickets live as issues. Linked assets live as files (`tmp/wayfinder/*.md` scratch, `.research/*.md`, `.prototype/<slug>/`) linked from the ticket, never pasted.
4. **Never raw `gh issue create/edit/close/comment`.** Use `opencode-run spec wayfinder-map` / `wayfinder-ticket`, or Task `developer load: minimal` with the same command. Architect bash denials are not obstacles to work around.
5. **Never resolve more than one ticket per session** (research tickets excepted). The map is the unit of multi-session continuity, not the session.
6. **Refer by name.** Names in narration and `## Decisions so far`; ids/URLs ride inside the name, never stand in for it.
7. **Claim first.** Assign before any work; never start work on an unassigned ticket.
8. **Update the map on close.** Resolution comment, close, then `--update` the map. The map and the frontier must always agree.
9. **GitHub is the source of truth.** Map + tickets live as issues. Linked assets live as files (`tmp/wayfinder/*.md` scratch, `.research/*.md`, `.prototype/<slug>/`) linked from the ticket, never pasted. Do not write local plan artifacts.
10. **`grill-me` once per grilling ticket.** It already embeds domain-modeling. Do not call `grill-me` twice.