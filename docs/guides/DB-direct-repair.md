This prompt is for the operator (you) — paste it into the next
session if/when the plugin drift recurs and `worktree_reconcile`
can't fix it. It is the documented escape hatch. No code changes
needed; this is reference documentation for your own use.

# DB-direct repair — blocshed-web project

When `worktree_list()` and `git worktree list --porcelain` disagree,
the opencode-server's registration set is the cause. The
registration set lives in `/var/lib/opencode-data/opencode.db`,
table `project`, column `sandboxes` (JSON array of worktree paths).
Below is the exact procedure I've used twice this session.

## 1. Discover the project id and the project's main checkout

```bash
sqlite3 /var/lib/opencode-data/opencode.db \
  "SELECT id, worktree, sandboxes FROM project;"
```

If `sqlite3` isn't installed (it wasn't on the blocshed-web
container), use python3:

```bash
python3 - <<'PYEOF'
import sqlite3, json
DB = "/var/lib/opencode-data/opencode.db"
conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
cur = conn.cursor()
for row in cur.execute("SELECT id, worktree, sandboxes FROM project"):
    print(f"id={row['id']}\nmain_checkout={row['worktree']}")
    print(f"sandboxes={row['sandboxes']}\n")
    if row["sandboxes"]:
        for p in json.loads(row["sandboxes"]):
            print(f"  - {p}")
PYEOF
```

The `id` is the project id used in the next step. The `worktree`
field is the main checkout (which is the canonical worktree the
project "lives at"). The `sandboxes` field is the registration set.

## 2. Build the desired `sandboxes` array

```bash
# List git's authoritative worktree list (realpath-collapsed for
# bind-mount duplicates)
python3 - <<'PYEOF'
import subprocess, json, os
main_checkout = "<paste project.worktree here>"
res = subprocess.run(
    ["git", "-C", main_checkout, "worktree", "list", "--porcelain"],
    capture_output=True, text=True, check=True,
)
records = []
for block in res.stdout.split("\n\n"):
    if not block.strip():
        continue
    lines = [l for l in block.split("\n") if l]
    path = next((l.split(" ", 1)[1] for l in lines if l.startswith("worktree ")), None)
    branch = next((l.split(" ", 1)[1] for l in lines if l.startswith("branch ")), None)
    if not path:
        continue
    # prefer the spelling matching the bind-mount canonical path
    # (default ~/.opencode-worktrees); fall back to /var/opencode-xdg/... if that's the only spelling
    records.append((path, branch, os.path.realpath(path)))

# dedupe by realpath; prefer canonical spelling
by_real = {}
canonical = os.path.realpath(os.path.expanduser("~/.opencode-worktrees"))
for path, branch, real in records:
    if real not in by_real:
        by_real[real] = path
    elif path.startswith(canonical):
        by_real[real] = path

desired = list(by_real.values())
print(json.dumps(desired))
PYEOF
```

Copy the printed JSON array; that's your new `sandboxes` value.

## 3. Backup, then write

```bash
python3 - <<PYEOF
import sqlite3, json, datetime
DB = "/var/lib/opencode-data/opencode.db"
PROJECT_ID = "<paste id here>"
NEW = <paste the json array here, as a python list>
conn = sqlite3.connect(DB)
cur = conn.cursor()
cur.execute("SELECT sandboxes FROM project WHERE id = ?", (PROJECT_ID,))
current = cur.fetchone()[0]
backup_at = datetime.datetime.utcnow().isoformat()
# backup first (idempotent table creation)
cur.execute("""CREATE TABLE IF NOT EXISTS project_sandboxes_backup (
    project_id TEXT, sandboxes TEXT, backup_at TEXT
)""")
cur.execute("INSERT INTO project_sandboxes_backup VALUES (?, ?, ?)", (PROJECT_ID, current, backup_at))
# write new
new_json = json.dumps(NEW, separators=(",", ":"))
cur.execute("UPDATE project SET sandboxes = ? WHERE id = ?", (new_json, PROJECT_ID))
conn.commit()
print("OK. Backup row + write committed.")
# verify
cur.execute("SELECT sandboxes FROM project WHERE id = ?", (PROJECT_ID,))
print("NEW VALUE:", cur.fetchone()[0])
PYEOF
```

## 4. Restart opencode-server and verify

Restart the server (whatever your install's restart command is).
Then from a fresh session:

```python
worktree_list()  # should now match git worktree list --porcelain (realpath-collapsed)
git -C <main checkout> worktree list --porcelain
```

If they match, you're done. If they don't, the `sandboxes` value
is wrong; restore from `project_sandboxes_backup` and re-do.

## When NOT to use this

- During a `worktree_create_*` or `worktree_delete` op in flight.
- Before `worktree_reconcile(dryRun: true)` has been run to confirm
  the gap is real (and not a momentary server-side cache).
- When you don't have a backup of the current `sandboxes` value.