---
name: orchestrate-plan-compat
description: "Deprecated explicit local-plan compatibility loop. Load only for a supplied .plan path or explicit compatibility request; never as GitHub readiness fallback."
modelTier: "fast"
roleReminder: "Preserve existing local-plan behavior without recommending it or mixing it with GitHub queue execution."
---

## Compatibility Boundary

This skill is retained only for persisted or explicitly requested `.plan/<type>.<slug>.md` execution. The artifact is the source of truth; use its ordered stages and `FilesToChange`, dispatch the declared Owner, and run `verifier` after every implementer Task with the same acceptance gate used by GitHub stages.

Do not infer this path from missing issues, readiness failure, malformed metadata, or queue exhaustion. Do not create new local plans. Preserve existing retry, review, documentation, archive, and machine-state behavior; load `orchestrate-recovery` for failures and `orchestrate-completion` only after the explicit plan loop completes.
