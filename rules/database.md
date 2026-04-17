<!-- Scope: migrations, models, schema files -->

# Database and migrations

- Migrations must be reversible when the change is reversible; document irreversible steps.
- New indexes for columns used in new `WHERE` / `ORDER BY` / `JOIN` on hot paths.
- Avoid destructive data migrations without backup/rollout plan in the plan artifact.
- Use transactions for multi-step DDL where the database supports it safely.
