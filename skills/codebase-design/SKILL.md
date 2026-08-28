---
name: codebase-design
description: Shared vocabulary for designing deep modules, clean seams, adapters, leverage, and locality.
---

# Codebase Design

Use this vocabulary when designing or restructuring code:

- **Module**: anything with an interface and an implementation.
- **Interface**: everything a caller must know, including invariants, errors, configuration, and performance.
- **Depth**: behaviour and leverage behind a small interface.
- **Seam**: the location where behaviour can be changed without editing the caller.
- **Adapter**: a concrete implementation satisfying an interface at a seam.
- **Leverage**: capability per unit of interface a caller learns.
- **Locality**: how much change, knowledge, and verification concentrate in one place.

Prefer deep modules: simplify parameters, hide complexity, and keep the interface as the test surface. Apply the deletion test. Do not introduce a seam for one adapter; two adapters make a seam real.
