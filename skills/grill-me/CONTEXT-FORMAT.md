# CONTEXT.md Format

`CONTEXT.md` is a concise glossary and relationship map. It is a memory aid for domain language, not an implementation specification or source of truth.

Use these sections when applicable:

```md
# Context Name

One or two sentences describing the domain context.

## Language

**Canonical term**:
One-sentence definition.
_Avoid_: Common aliases or overloaded alternatives.

## Relationships

- An **Entity** belongs to one **Context**.

## Example dialogue

> **Dev:** Clarifying question using the terms.
> **Domain expert:** Precise answer showing the boundary.

## Flagged ambiguities

- Ambiguous term and its resolved meaning.
```

Keep definitions domain-specific and free of implementation details. Add or revise entries only when a term is settled during grilling, and have `scribe` write the complete file.
