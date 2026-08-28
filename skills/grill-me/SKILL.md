---
name: grill-me
description: Relentless design-tree grilling that challenges plans against the domain model, sharpens terminology, and persists CONTEXT.md and ADR decisions through scribe.
---

# Grill Me

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask now without guessing at answers you have not heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format each round like this:

```
❓ **Q1** - **<question title>**: <question body, including choices where useful>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body>

➡️ <your recommended answer>
```

Each round reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. A question whose answer depends on another question still open in this round belongs to a later round.

Finding facts is the agent's job, never the user's. When a frontier question needs a filesystem, tool, or codebase fact, explore it or dispatch a sub-agent. Do not ask the user for facts that can be looked up. Do not block unrelated frontier questions on an exploration still in progress. The decisions are the user's: present them and wait.

## Domain awareness

Read `CONTEXT.md`, `CONTEXT-MAP.md`, and relevant ADRs when they exist. Treat both as helpful memory aids, not as the source of truth: the current code, explicit user decisions, and observed behavior win. Challenge terminology against the glossary immediately, propose precise canonical terms for vague language, stress-test relationships with concrete edge cases, and cross-reference claims with the code. Keep domain concepts distinct from implementation details.

### ADR drift check

For each relevant ADR, perform a lightweight drift check against the current code and the decisions settled in this session. If an ADR conflicts with the current code, do not treat the conflict as a blocker or silently follow the stale document. Explain the drift, then Task `scribe` to update the ADR or archive it as superseded according to the repository's documentation convention, and continue the interview using the current code and settled decision. Keep ADRs short, focused on key architectural decisions, and create one only when it prevents future re-litigating.

Create context and ADR files lazily. The Architect is read-only: when a term is resolved or an ADR is warranted, Task `scribe` with the target path and the complete file content using `mode: create` or `update`. Scribe is the only write path. Use the formats in [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md) and [ADR-FORMAT.md](ADR-FORMAT.md). Offer an ADR only when it is hard to reverse, surprising without context, and the result of a meaningful trade-off; otherwise keep the decision in the session or glossary.

The session is done when the frontier is empty: every branch of the design tree has been visited and nothing remains silently assumed. Do not act on the plan until the user confirms that shared understanding has been reached.
