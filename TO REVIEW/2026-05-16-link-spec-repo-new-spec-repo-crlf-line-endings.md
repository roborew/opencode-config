# 2026-05-16 — `link-spec-repo` / `new-spec-repo` CRLF Line Endings Fix

**Cursor chat created:** 2026-05-16 (transcript birth time `2026-05-16 18:01`; parent transcript ID `6aa04808-f356-408a-821f-e2fcf0152738`).

**Session scope:** Diagnose and fix `env: bash\r: No such file or directory` when running `~/.config/opencode/bin/new-spec-repo`; normalize line endings on `bin/link-spec-repo` and `bin/new-spec-repo`; add Git attributes so `bin/*` stays LF; confirm both scripts remain valid after staging in the editor; document for re-application by another agent.

**Status:** Implemented and finalized in this chat. **Verify on disk before merge** — this repo may have since reorganized (e.g. `bin/` removed or scripts consolidated under `bin/stack/` / `setup-project`). Search for the behaviors below in the active entrypoint if paths differ.

**Related sessions (same or adjacent dates):**

- [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) — spec-repo sync path, `strip_crlf`, bulk normalize, CI gate
- [`2026-06-01-crlf-line-endings-and-architect-bash-permissions.md`](2026-06-01-crlf-line-endings-and-architect-bash-permissions.md) — broader CRLF + architect permission work (separate session)
- [`2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md`](2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md) — `new-spec-repo` create-or-sync behavior (separate session)

**Operator context at session start:** `mycelia-tree` parent folder (`~/05_Repos/01_PROJECTS/apps/mycelia-tree`) with sibling repos `mycelia-tree-frontend` and `mycelia-tree-api` already present locally.

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Symptom | `new-spec-repo` failed immediately with `env: bash\r: No such file or directory` |
| Root cause | Windows-style **CRLF** (`\r\n`) on shell shebangs — kernel/`env` looks for `bash\r` |
| Files fixed | `bin/new-spec-repo`, `bin/link-spec-repo` normalized to **LF-only** |
| Prevention | Root `.gitattributes` extended with `bin/* text eol=lf` |
| Permissions | Both scripts confirmed **executable** (`chmod +x`) |
| Validation | `file`, `rg` (no `\r`), `bash -n`, `od -c` — all passed |
| Editor UX | Files “disappearing” after **Stage** was explained as clean working tree / committed state, not deletion |
| Logic changes | **None** — line endings only; script bodies unchanged |

---

## 1. Problem reported

### Command

From the application parent folder:

```bash
~/.config/opencode/bin/new-spec-repo mycelia-tree mycelia-tree-frontend mycelia-tree-api
```

### Failure

```text
env: bash\r: No such file or directory
```

The script never started. Local sibling repos already existed; the failure blocked spec-repo bootstrap before any `gh repo create` output.

### Operator `ls` at session start (context only)

```text
~/05_Repos/01_PROJECTS/apps/mycelia-tree
total 0
drwxr-xr-x   4 robo  staff  128 16 May 17:42 .
drwxr-xr-x  10 robo  staff  320 16 May 17:01 ..
drwxr-xr-x@  4 robo  staff  128 16 May 17:40 mycelia-tree-api
drwxr-xr-x@ 31 robo  staff  992 20 Mar 11:50 mycelia-tree-frontend
```

The `16 May` folder dates are **when those directories were created**, not the Cursor chat date.

### Secondary report

After attempting to stage fixes in the editor, both `bin/link-spec-repo` and `bin/new-spec-repo` **vanished from the Source Control view** and appeared as generic **text** rather than shell scripts in some UI surfaces.

---

## 2. Root cause

### Technical mechanism

On macOS/Linux, the kernel reads the first line of an executable script as the interpreter path. With CRLF, the shebang is effectively:

```text
#!/usr/bin/env bash\r
```

`/usr/bin/env` then searches for a binary named `bash\r`, which does not exist → `env: bash\r: No such file or directory`.

### Byte-level before / after (shebang line)

**Broken (CRLF) — `od -c` on line 1:**

```text
0000000    #   !   /   u   s   r   /   b   i   n   /   e   n   v       b
0000020    a   s   h  \r  \n
```

**Fixed (LF) — `od -c` on line 1:**

```text
0000000    #   !   /   u   s   r   /   b   i   n   /   e   n   v       b
0000020    a   s   h  \n
```

### Why both scripts were affected

| File | CRLF state at investigation |
| --- | --- |
| `bin/new-spec-repo` | Had CRLF on first report; fixed in first pass of this chat |
| `bin/link-spec-repo` | Still had CRLF on second pass — `file` reported *with CRLF line terminators* |

| File | Size with CRLF | Size after LF normalize |
| --- | --- | --- |
| `bin/link-spec-repo` | 1476 bytes | 1436 bytes (−40 `\r` bytes ≈ one per line) |
| `bin/new-spec-repo` | (CRLF initially) | 3077 bytes |

CRLF also causes some tools (Finder, certain editors) to treat scripts as plain **text** instead of Unix shell executables, even when `chmod +x` is set.

### Why `.gitattributes` alone was insufficient

At session time the repo had `*.sh text eol=lf` but **`bin/link-spec-repo` and `bin/new-spec-repo` have no `.sh` extension**, so Git did not enforce LF on checkout/commit for those paths until `bin/*` was added.

---

## 3. Re-application guide (for another AI)

Execute in order. **Do not change script logic** — only line endings, permissions, and `.gitattributes`.

### Step 0 — Confirm the failure

```bash
OPENCODE="${OPENCODE:-$HOME/.config/opencode}"
file "$OPENCODE/bin/new-spec-repo" "$OPENCODE/bin/link-spec-repo"
head -1 "$OPENCODE/bin/new-spec-repo" | od -c | head -2
```

Expect on broken files: `file` mentions **CRLF**, or `od` shows `\r` before `\n` after `bash`.

### Step 1 — Strip CRLF (macOS / BSD sed)

```bash
OPENCODE="${OPENCODE:-$HOME/.config/opencode}"
sed -i '' 's/\r$//' "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo"
```

**Linux (GNU sed):**

```bash
sed -i 's/\r$//' "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo"
```

**Python fallback (cross-platform, in-place):**

```python
#!/usr/bin/env python3
import pathlib
root = pathlib.Path.home() / ".config/opencode/bin"
for name in ("link-spec-repo", "new-spec-repo"):
    p = root / name
    if p.exists():
        data = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        p.write_bytes(data)
        print(f"normalized {p}")
```

### Step 2 — Ensure executability

```bash
chmod +x "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo"
```

### Step 3 — Patch root `.gitattributes`

**Before (session time):**

```gitattributes
*.sh text eol=lf
```

**After (required end state):**

```gitattributes
*.sh text eol=lf
bin/* text eol=lf
```

**Exact `StrReplace` applied in chat:**

| Field | Value |
| --- | --- |
| File | `.gitattributes` (repo root) |
| `old_string` | `*.sh text eol=lf` |
| `new_string` | `*.sh text eol=lf`<br>`bin/* text eol=lf` |

If `.gitattributes` does not exist, create it with at least:

```gitattributes
bin/* text eol=lf
*.sh text eol=lf
```

### Step 4 — Verify (all must pass)

```bash
OPENCODE="${OPENCODE:-$HOME/.config/opencode}"
cd "$OPENCODE"

file bin/link-spec-repo bin/new-spec-repo
# Expected: Bourne-Again shell script text executable, UTF-8 text
# Must NOT say: "with CRLF line terminators"

rg $'\r' bin/link-spec-repo bin/new-spec-repo && echo FAIL || echo "No CR bytes — OK"

bash -n bin/link-spec-repo && echo "link-spec-repo syntax OK"
bash -n bin/new-spec-repo && echo "new-spec-repo syntax OK"

head -1 bin/new-spec-repo | od -c | head -2
# Expected: a s h \n  (no \r)

git ls-files bin/link-spec-repo bin/new-spec-repo
ls -la bin/link-spec-repo bin/new-spec-repo
```

**Expected `file` output after fix:**

```text
bin/link-spec-repo: Bourne-Again shell script text executable, Unicode text, UTF-8 text
bin/new-spec-repo:  Bourne-Again shell script text executable, Unicode text, UTF-8 text
```

### Step 5 — Commit (if operator requests)

```bash
cd "$OPENCODE"
git add bin/link-spec-repo bin/new-spec-repo .gitattributes
git commit -m "$(cat <<'EOF'
chore: normalize LF line endings for bin/link-spec-repo and bin/new-spec-repo

CRLF shebangs caused env: bash\r on macOS. Enforce bin/* eol=lf in .gitattributes.
EOF
)"
```

Commit observed in session (may not exist in all clones): `d159b06` — *chore: update .gitattributes to enforce LF line endings for bin directory*.

### Step 6 — Operator re-run

```bash
~/.config/opencode/bin/new-spec-repo mycelia-tree mycelia-tree-frontend mycelia-tree-api
```

If spec repo was never created (failure was on startup), no rollback needed.

---

## 4. Files touched (summary)

| Path | Change type | Detail |
| --- | --- | --- |
| `bin/new-spec-repo` | Line endings | CRLF → LF only; **no logic edits** |
| `bin/link-spec-repo` | Line endings | CRLF → LF only; **no logic edits** |
| `.gitattributes` | Content | Added `bin/* text eol=lf` |

**Not in scope:** `templates/spec-repo/bin/*`, sync scripts, architect permissions, `new-spec-repo` branch/git-flow logic.

---

## 5. Full script sources (post-fix, LF — restore if missing)

These are the **exact script bodies** at session time after normalization. Write with **LF** line endings only.

### 5.1 `bin/link-spec-repo` (41 lines)

```bash
#!/usr/bin/env bash
# Run inside a target implementation repo. Links docs/agents/issue-tracker.md to the spec repo and installs bin/feature-context.
# Usage: link-spec-repo <owner/name-of-spec-repo>
set -euo pipefail
SPEC_REPO="${1:?owner/name spec repo required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p docs/agents bin
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (see `git remote get-url origin`)

## Spec repository (parent PRDs)

- **SPEC_REPO:** __SPEC_REPO__

`bin/feature-context` reads **SPEC_REPO** from this file.
EOF
sed -i.bak "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md && rm -f docs/agents/issue-tracker.md.bak

if [[ ! -f bin/feature-context ]]; then
  install -m0755 "${ROOT}/templates/bin/feature-context" bin/feature-context
  echo "Installed bin/feature-context from OpenCode config."
else
  echo "bin/feature-context already exists — not overwriting."
fi

touch .gitignore
if ! grep -q '^tmp/' .gitignore 2>/dev/null; then
  printf '\n# OpenCode scratch\ntmp/\n.research/\n.qa/\n.plan/*.completed.md\n' >> .gitignore
  echo "Appended tmp/ and scratch paths to .gitignore"
fi

echo ""
echo "Linked SPEC_REPO=${SPEC_REPO}"
echo "Next: run setup-skills in OpenCode if you have not already, then:"
echo "  bin/feature-context <issue-number>"
```

### 5.2 `bin/new-spec-repo` (86 lines)

```bash
#!/usr/bin/env bash
# Create application spec repo from templates/spec-repo, seed labels, branch protection, optional GitHub Project.
# Usage: GH_ORG=roborew new-spec-repo <app-slug> [target-repo ...]
#   target-repo: short name (app-frontend) or full owner/repo
set -euo pipefail
ORG="${GH_ORG:-roborew}"
APP="${1:?app slug required}"
shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_NAME="${APP}-spec"
SPEC_REPO="${ORG}/${SPEC_NAME}"

if gh repo view "$SPEC_REPO" &>/dev/null; then
  echo "Repo $SPEC_REPO already exists — abort" >&2
  exit 1
fi

echo "Creating ${SPEC_REPO}..."
gh repo create "$SPEC_REPO" --private --description "Spec repo: PRDs + parent issues for ${APP}" --clone
cd "${SPEC_NAME}"

echo "Copying scaffold from ${ROOT}/templates/spec-repo ..."
cp -R "${ROOT}/templates/spec-repo/." .

# repos.md
{
  echo "repos:"
  for t in "$@"; do
    full="$t"
    if [[ "$t" != */* ]]; then
      full="${ORG}/${t}"
    fi
    echo "  - name: ${full}"
    echo "    role: target"
  done
} > docs/agents/repos.md

git add -A
git commit -m "chore: bootstrap ${SPEC_NAME} scaffold" || true
git push -u origin main || git push -u origin master || true

echo "Branch protection on default branch..."
DEFAULT_BRANCH=$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
gh api -X PUT "repos/${SPEC_REPO}/branches/${DEFAULT_BRANCH}/protection" \
  -F required_status_checks= \
  -F enforce_admins=false \
  -F required_pull_request_reviews.required_approving_review_count=0 \
  -F required_pull_request_reviews.dismiss_stale_reviews=true \
  -F restrictions= \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  -F required_linear_history=true 2>/dev/null || echo "(branch protection skipped — adjust permissions)"

seed_one() {
  local repo="$1"
  yq -o=json '.[]' .github/labels.yml 2>/dev/null | jq -c '.' | while read -r row; do
    name=$(echo "$row" | jq -r .name)
    color=$(echo "$row" | jq -r .color)
    desc=$(echo "$row" | jq -r '.description // ""')
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" --force 2>/dev/null || true
  done
}

if command -v yq &>/dev/null && command -v jq &>/dev/null; then
  echo "Seeding labels into ${SPEC_REPO}..."
  seed_one "$SPEC_REPO"
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    echo "Seeding labels into ${r}..."
    seed_one "$r"
  done < <(yq -r '.repos[].name' docs/agents/repos.md 2>/dev/null || true)
else
  echo "WARN: install yq + jq to seed labels from .github/labels.yml" >&2
fi

echo ""
echo "=== GitHub Project (optional) ==="
echo "Create a Project v2 board in the browser: https://github.com/orgs/${ORG}/projects — link repos ${SPEC_REPO} $@"
echo "Automated field setup is not fully available via gh in all versions; enable **Auto-add to project** per repo in project settings."
echo ""
echo "=== LABEL_SYNC_PAT ==="
echo "Add a fine-grained PAT (Issues: write) for sibling repos:"
echo "  gh secret set LABEL_SYNC_PAT --repo ${SPEC_REPO}"
echo ""
echo "Done. Spec repo: https://github.com/${SPEC_REPO}"
```

**Restore one-liner (writes LF, marks executable):**

```bash
OPENCODE="${OPENCODE:-$HOME/.config/opencode}"
install -d "$OPENCODE/bin"
# Paste each script body above into the paths, then:
sed -i '' 's/\r$//' "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo" 2>/dev/null || \
  sed -i 's/\r$//' "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo"
chmod +x "$OPENCODE/bin/link-spec-repo" "$OPENCODE/bin/new-spec-repo"
```

---

## 6. Chat timeline (what happened, in order)

| Step | Action |
| --- | --- |
| 1 | User ran `new-spec-repo mycelia-tree …` → `env: bash\r` |
| 2 | Agent read `bin/new-spec-repo`; confirmed CRLF shebang |
| 3 | `sed -i '' 's/\r$//'` on `bin/new-spec-repo` only |
| 4 | User asked to fix **both** scripts (still showing as plain text) |
| 5 | `file` showed `link-spec-repo` still *with CRLF line terminators* |
| 6 | `sed` on **both** + `chmod +x` + verification (`file`, `rg`, `bash -n`) |
| 7 | Read root `.gitattributes` — only `*.sh text eol=lf` |
| 8 | Added `bin/* text eol=lf` via `StrReplace` |
| 9 | User staged changes; files “disappeared” from Source Control |
| 10 | Agent verified: files on disk, `git status` clean, both tracked |
| 11 | TO REVIEW doc authored (this file) |

---

## 7. Editor / Git UX — “files disappeared”

After staging (and especially after commit), **Source Control only lists pending diffs**. When `git status` is clean:

- Files **remain** at `bin/link-spec-repo` and `bin/new-spec-repo`
- They **vanish from the changes list** — not from disk
- `git ls-files bin/link-spec-repo bin/new-spec-repo` should still list both

Sanity check:

```bash
cd ~/.config/opencode
git status
git ls-files bin/link-spec-repo bin/new-spec-repo
ls -la bin/link-spec-repo bin/new-spec-repo
```

---

## 8. Prevention (ongoing)

| Layer | Action |
| --- | --- |
| Git | Keep `bin/* text eol=lf` in root `.gitattributes` |
| Editor | VS Code/Cursor **Files: Eol** → `\n` for this repo |
| CI | If `scripts/check-crlf.sh` exists, ensure it scans `bin/` (see [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md)) |
| Spec sync | Prefer `strip_crlf` in `bin/stack/sync_spec_tooling.sh` when copying templates to spec repos |

---

## 9. Acceptance checklist

- [ ] `bin/new-spec-repo` and `bin/link-spec-repo` exist and are executable (`755`)
- [ ] Neither file contains `\r` bytes (`rg $'\r'` silent)
- [ ] `file` identifies both as Bourne-Again shell scripts (**no** CRLF mention)
- [ ] `bash -n` passes on both
- [ ] Shebang `od -c` shows `bash` then `\n` only
- [ ] Root `.gitattributes` includes `bin/* text eol=lf`
- [ ] `new-spec-repo` runs without `env: bash\r` from the opencode config path
- [ ] After commit, Source Control is clean; scripts still open from `bin/` in the tree

---

## 10. Follow-ups (optional, not done in this chat)

| Item | Notes |
| --- | --- |
| Rename `mycelia-tree-frontend` → `mycelia-tree-web` | Naming convention in later README sessions |
| Bulk CRLF audit of entire config repo | [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) |
| `new-spec-repo` create-or-sync / git-flow | [`2026-06-01-new-spec-repo-git-flow-main-develop.md`](2026-06-01-new-spec-repo-git-flow-main-develop.md) |
| Consolidation into `setup-project` | Port LF policy to active stack entrypoint if `bin/new-spec-repo` is removed |
