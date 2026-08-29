#!/usr/bin/env bash
# Validates agent files vs opencode.json and skills vs agent permissions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ERR=0

if ! python3 -m json.tool opencode.json >/dev/null 2>&1; then
  echo "ERROR: opencode.json is not valid JSON"
  exit 1
fi

echo "Checking agents/*.md have keys in opencode.json agent block..."
for f in agents/*.md; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f" .md)
  if ! grep -q "\"$base\"" opencode.json; then
    echo "  MISSING: agent key for $base"
    ERR=1
  fi
done

echo "Checking skills referenced in agents exist..."
if ! python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path(".")
missing = []

for agent in sorted((root / "agents").glob("*.md")):
    text = agent.read_text()
    parts = text.split("---", 2)
    if len(parts) < 3:
        continue
    frontmatter = parts[1]
    for match in re.finditer(r'"([a-z0-9-]+)"\s*:\s*"allow"', frontmatter):
        skill = match.group(1)
        if skill == "*":
            continue
        if not (root / "skills" / skill / "SKILL.md").is_file():
            missing.append((agent, skill))

for agent, skill in missing:
    print(f"  MISSING skill: skills/{skill}/SKILL.md (referenced in {agent})")

sys.exit(1 if missing else 0)
PY
then
  ERR=1
fi

echo "Checking scribe write-only (edit: false)..."
scribe_fm=$(awk '/^---$/{n++; if(n==2) exit} n==1' agents/scribe.md 2>/dev/null || true)
if echo "$scribe_fm" | grep -qE '^[[:space:]]*edit:[[:space:]]*false'; then
  edit_lines=$(echo "$scribe_fm" | grep -cE '^[[:space:]]*edit:')
  if [ "$edit_lines" -gt 1 ]; then
    echo "  ERROR: scribe has edit: false but still defines permission.edit"
    ERR=1
  fi
fi

echo "Checking migrate_repos_registry unit tests..."
if ! python3 -m unittest bin/lib/test_migrate_repos_registry.py -q; then
  echo "  FAILED: migrate_repos_registry tests"
  ERR=1
fi

echo "Checking existing_issue unit tests..."
if ! python3 -m unittest templates/spec-repo/bin/lib/test_existing_issue.py -q; then
  echo "  FAILED: existing_issue tests"
  ERR=1
fi

echo "Checking checkout guardrails in orchestrate and execution agents..."
GUARDRAIL_FILES="agents/orchestrate.md skills/orchestrate-execution/SKILL.md agents/developer.md agents/frontend-dev.md"
for needle in "Checkout identity gate" "CHECKOUT_CONTRACT_FAILED" "checkout-contract.sh"; do
  if ! grep -q "$needle" $GUARDRAIL_FILES 2>/dev/null; then
    echo "  MISSING guardrail reference: $needle"
    ERR=1
  fi
done

if ! grep -qE 'git[[:space:]]+switch' scripts/block-dangerous-git.sh 2>/dev/null; then
  echo "  MISSING: git switch block in block-dangerous-git.sh"
  ERR=1
fi

if [[ -n "${GH_PROJECT:-}" ]] && command -v gh >/dev/null 2>&1; then
  echo "Checking GH_PROJECT scope (warn only)..."
  if ! gh auth status 2>&1 | grep -q 'project'; then
    echo "  WARN: GH_PROJECT is set but gh token may lack project scope — run: gh auth refresh -s project"
  fi
fi

if [[ ! -f skills/github-issue-run/lib/checkout-contract.sh ]]; then
  echo "  MISSING: skills/github-issue-run/lib/checkout-contract.sh"
  ERR=1
fi

echo "Checking feature workflow contracts..."
for f in agents/code-review.md skills/code-review/SKILL.md agents/test-writer.md skills/test-writer/SKILL.md skills/feature-worktree/SKILL.md; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    ERR=1
  fi
done
if [[ -f agents/verifier.md || -f skills/verifier/SKILL.md ]]; then
  echo "  ERROR: verifier role must be removed"
  ERR=1
fi
if grep -R -n '```opencode-task-json' bin/project/spec templates/spec-repo/bin templates/bin >/dev/null 2>&1; then
  echo "  ERROR: JSON task fences remain in builders or validators"
  ERR=1
fi
if ! grep -q 'feature-worktree' agents/orchestrate.md; then
  echo "  MISSING: feature-worktree orchestrate routing"
  ERR=1
fi
if ! grep -q 'gh pr checks' skills/orchestrate-completion/SKILL.md || ! grep -q 'pr_stabilization' skills/orchestrate-completion/SKILL.md; then
  echo "  MISSING: CI stabilization loop language in orchestrate-completion"
  ERR=1
fi
if ! grep -q 'code-review' skills/docker-sandbox/SKILL.md || ! grep -q 'APPROVED' skills/docker-sandbox/SKILL.md || ! grep -q 'BLOCKED' skills/docker-sandbox/SKILL.md; then
  echo "  MISSING: lifecycle-aware destroy language in docker-sandbox Hard Rule 5"
  ERR=1
fi
if ! grep -q 'pr_stabilization_fix' agents/developer.md; then
  echo "  MISSING: pr_stabilization_fix execution mode in developer agent"
  ERR=1
fi
if ! grep -q 'sandbox_id' agents/code-review.md; then
  echo "  MISSING: sandbox_id reuse language in code-review agent"
  ERR=1
fi

echo "Checking worktree-env / preflight bootstrap scripts..."
for f in scripts/worktree-env.sh scripts/preflight-worktree-verify.sh scripts/preflight-runtime.sh; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    ERR=1
  elif [[ ! -x "$f" ]]; then
    echo "  NOT EXECUTABLE: $f"
    ERR=1
  fi
done
if ! grep -q 'scripts/worktree-env.sh' agents/worktree-env.md skills/worktree-env/SKILL.md 2>/dev/null; then
  echo "  MISSING: worktree-env.sh reference in worktree-env agent/skill"
  ERR=1
fi
if ! grep -q 'scripts/preflight-worktree-verify.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
  echo "  MISSING: preflight-worktree-verify.sh reference in preflight agent/skill"
  ERR=1
fi
if ! grep -q 'scripts/preflight-runtime.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
  echo "  MISSING: preflight-runtime.sh reference in preflight agent/skill"
  ERR=1
fi
if ! grep -q 'do not recommend upgrading the Docker/base Node' scripts/preflight-runtime.sh 2>/dev/null; then
  echo "  MISSING: Docker/image Node policy note in preflight-runtime.sh"
  ERR=1
fi

if [[ $ERR -ne 0 ]]; then
  echo "validate-opencode-config: FAILED"
  exit 1
fi
echo "validate-opencode-config: OK"
exit 0
