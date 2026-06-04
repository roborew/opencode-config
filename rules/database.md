<!-- Scope: migrations, models, schema files -->

# Database and migrations

## Schema change workflow (all stacks)

Follow the project's schema workflow in **`opencode.md`** or **README** (generate command, schema source path, migration output dir). If neither documents it, stop and ask the human before editing migrations.

**Universal rules (Drizzle, Prisma, Rails, etc.):**

1. **Source of truth** — Edit the stack's schema definition (e.g. Drizzle `schema/`, Prisma `schema.prisma`, Rails models + `rails generate migration`). Do not treat generated migration SQL as the place to express schema changes unless the project explicitly uses hand-written SQL migrations by convention.
2. **Never hand-edit generated migrations** — Do not create or modify files under generated migration output (e.g. `drizzle/`, Prisma `migrations/*/migration.sql`) without running that project's **generate** command in the same session. Hand-written SQL there drifts from the ORM and breaks `db generate` / migrate tooling.
3. **Generate, then commit together** — After schema source edits, run the documented generate command (`pnpm db:generate`, `npx prisma migrate dev --create-only`, `bin/rails generate migration`, etc.). Commit schema sources and generated migration artifacts in one logical change.
4. **Discover commands** — Read `package.json` scripts, `Makefile`, or plan `Tasks` for the exact command; do not guess paths or filenames.

**Stack examples (project `opencode.md` overrides these):**

| Stack | Edit | Generate (typical) | Do not hand-edit |
|-------|------|--------------------|------------------|
| Drizzle | `schema/` (or project path) | `db:generate` / `drizzle-kit generate` | `drizzle/*.sql` |
| Prisma | `schema.prisma` | `prisma migrate dev --create-only` | `migrations/*/migration.sql` |
| Rails | models + migration generator | `bin/rails generate migration` | rarely raw `db/migrate/*.rb` without generator |

## DDL and data safety

- Migrations must be reversible when the change is reversible; document irreversible steps.
- New indexes for columns used in new `WHERE` / `ORDER BY` / `JOIN` on hot paths.
- Avoid destructive data migrations without backup/rollout plan in the plan artifact.
- Use transactions for multi-step DDL where the database supports it safely.
