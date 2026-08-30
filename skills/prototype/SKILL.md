---
name: prototype
description: "Build a throwaway prototype to raise the fidelity of a wayfinder decision. Use when the question is 'does this logic / state model feel right?' or 'what should this look like?' Companion to the wayfinder skill."
modelTier: smart
roleReminder: "Spec repo context (wayfinder tickets). Architect is read-only — scribe writes outlines/stubs/rough takes to tmp/ or .prototype/<slug>/; Task ux-dev writes HTML UI to .prototype/<slug>/ reusing docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md. Architect never edits prototype files directly."
---

# Prototype

Adapted from Matt Pocock's [`prototype`](https://github.com/mattpocock/skills/tree/main/skills/engineering/prototype) skill. A prototype is **throwaway code that answers a question**. The question decides the shape. Prototypes are scoped to a **wayfinder decision ticket** and live as files linked from the ticket, not in the ticket body.

## When to load

- A wayfinder ticket of type `prototype` is the current open frontier ticket (or the user explicitly asks for a prototype).
- The user wants to sanity-check whether a state model or logic feels right, or explore what a UI should look like.

## Pick a branch

Identify which question is being answered, using the ticket body, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → **logic branch**. Build a single shareable HTML file (free-play buttons plus tabbed guided walkthroughs) that pushes the state machine through cases that are hard to reason about on paper, and that a non-developer can drive.
- **"What should this look like?"** → **UI branch**. Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts, so getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Name files so a casual reader can see it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure.
2. **Trivial to run.** A UI prototype starts from one command in the project's task runner: `pnpm <name>`, `python <path>`, `bun <path>`, etc. A logic demo is a single HTML file the user double-clicks. Either way, no thinking required to start it.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is *checking*, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE, wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype *runnable*, no abstractions. The point is to learn something fast.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Capture it when done.** Fold any validated decision into the real code, then capture the prototype itself as a **primary source**: commit it to a throwaway branch, out of main, and leave a context pointer to that branch on the implementation issue. Capture the answer too (the verdict and the question it settled) in the issue or a commit. The main branch keeps only the validated decision.

## Storage and ownership (this config)

In the **spec repo** running a wayfinder session, the architect is read-only. Prototype artifacts are written by other agents and **linked from the wayfinder ticket**, never pasted.

| Artifact kind | Writer | Path |
|---|---|---|
| Outline / rough take / stub (markdown, prose) | Task **`scribe`** | `tmp/wayfinder/<slug>/<name>.md` (scratch) — or `.prototype/<slug>/<name>.md` once validated |
| HTML UI prototype | Task **`ux-dev`** | `.prototype/<slug>/index.html` (reusing [`docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md`](../../docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md)) |
| Logic / state-machine demo (HTML) | Task **`scribe`** (single-file HTML) | `tmp/wayfinder/<slug>/demo.html` (scratch) |
| Branded demo with images / multiple files | Task **`ux-dev`** | `.prototype/<slug>/` |

`tmp/` is in the recommended agent-scratch `.gitignore` (see `README.md`); `.prototype/` follows the same convention as `.research/` (gitignored where adopted). Once a prototype graduates, the validated decision moves into the real codebase via the regular pipeline (`to-tickets` → `orchestrate`) — the prototype itself stays throwaway.

## Ticket linkage

After the artifact exists, post a **resolution comment** with a link:

```bash
opencode-run spec wayfinder-ticket --comment <ticket-issue> --body-file tmp/wayfinder/<slug>-comment.md
opencode-run spec wayfinder-ticket --close <ticket-issue>
```

Body of the comment:

```markdown
## Prototype: <branch label>

Artifact: <relative path to .prototype/<slug>/... or tmp/wayfinder/<slug>/...>
Question answered: <the decision this prototype was settling>
Branch: <branch-name if committed>
```

The ticket body itself stays minimal (`## Question` only). Prototypes live as files.

## Hard rules

1. **Throwaway.** Mark prototypes clearly; don't merge throwaway code into the main branch.
3. **Link, don't paste.** The ticket body is short; the artifact lives as a file.
4. **Architect never writes prototype files.** Delegate to `scribe` (prose / single-file HTML) or `ux-dev` (multi-file / branded HTML).
5. **Reuse the HTML template.** HTML UI prototypes follow [`docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md`](../../docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md) unless the project already has a stronger convention.
6. **No persistence by default.** Surface state in-memory; only persist when the prototype's question explicitly involves persistence.
7. **One ticket, one prototype.** A wayfinder prototype ticket resolves a single decision; don't accumulate prototypes on the same ticket.