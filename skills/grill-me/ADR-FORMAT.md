# ADR Format

ADRs live in `docs/adr/` and use sequential filenames such as `0003-short-decision.md`. They are short memory aids for key architectural decisions, not a source of truth or a replacement for checking current code.

Keep each ADR concise: state the context, decision, and reason. Add **Status**, **Considered Options**, or **Consequences** only when they preserve genuinely useful trade-off context.

During each relevant `grill-me` session, compare the ADR with current code and settled decisions. If it has drifted, update it or archive it as superseded through `scribe`, then continue with current evidence.

Offer an ADR only when all three conditions apply:

1. The decision is hard to reverse.
2. The decision is surprising without context.
3. The decision resulted from a meaningful trade-off.
