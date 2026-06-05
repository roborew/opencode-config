# Interface Design

Use this only when the user explicitly wants to explore alternative interfaces for a chosen deepening candidate. This is the optional drill-down after the audit report, not the default audit path.

Uses the vocabulary in [LANGUAGE.md](LANGUAGE.md): **module**, **interface**, **seam**, **adapter**, **leverage**, **locality**.

## Process

### 1. Frame the problem space

Before spawning subagents, write a concise user-facing explanation:

- Constraints the new interface must satisfy.
- Dependencies and their category from [DEEPENING.md](DEEPENING.md).
- What sits behind the seam.
- Existing callers/tests that the design must respect.
- A rough illustrative code sketch to ground constraints, not a proposal.

Show this to the user, then proceed to parallel design exploration unless the user stops you.

### 2. Task strategist subagents

Use 3+ `strategist` Tasks in parallel. Each Task gets an independent brief containing:

- Candidate id and title.
- Files/modules involved.
- Coupling details and caller shapes.
- Dependency category.
- What implementation would sit behind the seam.
- Relevant `CONTEXT.md` vocabulary and [LANGUAGE.md](LANGUAGE.md) terms.

Give each strategist a different design constraint:

1. **Minimize the interface** — aim for 1-3 entry points max; maximize leverage per entry point.
2. **Maximize flexibility** — support many use cases and extension.
3. **Optimize for the common caller** — make the default case trivial.
4. **Ports & adapters** — include when cross-seam dependencies or external dependencies are involved.

Each strategist returns:

1. Interface: types, methods, params, invariants, ordering, error modes.
2. Usage example.
3. What the implementation hides behind the seam.
4. Dependency strategy and adapters.
5. Trade-offs: where leverage is high, where it is thin.

### 3. Compare

Present designs sequentially, then compare by:

- **Depth** — leverage at the interface.
- **Locality** — where change concentrates.
- **Seam placement** — what varies and what stays hidden.

End with a recommendation. If a hybrid is strongest, propose it directly.

Do not publish tickets unless the user explicitly asks to convert the chosen design into remediation issues.
