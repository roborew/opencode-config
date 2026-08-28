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

Read `CONTEXT.md`, `CONTEXT-MAP.md`, and relevant ADRs when they exist. Challenge terminology against the glossary immediately, propose precise canonical terms for vague language, stress-test relationships with concrete edge cases, and cross-reference claims with the code. Keep domain concepts distinct from implementation details.

Create context and ADR files lazily. The Architect is read-only: when a term is resolved or an ADR is warranted, Task `scribe` with the target path and the complete file content using `mode: create` or `update`. Scribe is the only write path. Offer an ADR only when the decision is hard to reverse, surprising without context, and the result of a real trade-off.

The session is done when the frontier is empty: every branch of the design tree has been visited and nothing remains silently assumed. Do not act on the plan until the user confirms that shared understanding has been reached.
