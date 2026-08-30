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

echo "Checking worktree-manager + worktree plugin wiring..."
if [[ ! -f plugins/worktree.js ]]; then
  echo "  MISSING: plugins/worktree.js"
  ERR=1
elif ! node --check plugins/worktree.js >/dev/null 2>&1; then
  echo "  FAIL: plugins/worktree.js syntax check"
  ERR=1
fi
if ! grep -q '/experimental/worktree' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: /experimental/worktree route in plugins/worktree.js"
  ERR=1
fi
if ! grep -q 'OPENCODE_APPS_DIR' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: OPENCODE_APPS_DIR self-guard in plugins/worktree.js"
  ERR=1
fi
for tool in worktree_create worktree_list worktree_delete worktree_reset; do
  if ! grep -q "$tool:" plugins/worktree.js 2>/dev/null; then
    echo "  MISSING: $tool registration in plugins/worktree.js"
    ERR=1
  fi
done
if ! grep -q 'async execute({ directory }, context)' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: context in worktree_delete/reset execute signature in plugins/worktree.js"
  ERR=1
fi
if ! grep -q 'v2.worktree.remove({' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: v2.worktree.remove call in plugins/worktree.js"
  ERR=1
fi
if ! grep -q 'directory: (context && context.directory) || undefined' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: project directory query param passed to remove/reset in plugins/worktree.js"
  ERR=1
fi
if ! grep -q 'scheduleGitCleanup' plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: scheduleGitCleanup defense-in-depth cleanup in plugins/worktree.js"
  ERR=1
fi
if [[ ! -f agents/worktree-manager.md ]]; then
  echo "  MISSING: agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q '"worktree-manager"' opencode.json 2>/dev/null; then
  echo "  MISSING: worktree-manager agent entry in opencode.json"
  ERR=1
fi
if ! grep -q 'worktree-manager: allow' agents/orchestrate.md 2>/dev/null; then
  echo "  MISSING: worktree-manager in orchestrate task allow-list"
  ERR=1
fi
if grep -q 'git worktree add' skills/feature-worktree/SKILL.md 2>/dev/null; then
  echo "  ERROR: feature-worktree SKILL still documents raw git worktree fallback"
  ERR=1
fi
if ! grep -q 'recover' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: recover action in agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q 'WORKTREE_RECOVERY_FAILED' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: WORKTREE_RECOVERY_FAILED blocker code in agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q 'rewrite-worktree-gitdirs.py' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: sanctioned cleanup script reference in agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q 'recover' skills/feature-worktree/SKILL.md 2>/dev/null; then
  echo "  MISSING: recover action in skills/feature-worktree/SKILL.md"
  ERR=1
fi
if ! grep -q 'do not recommend upgrading the Docker/base Node' scripts/preflight-runtime.sh 2>/dev/null; then
  echo "  MISSING: Docker/image Node policy note in preflight-runtime.sh"
  ERR=1
fi

echo "Checking ticket-session kickoff reliability wiring..."
for needle in 'session_notify:' 'session.promptAsync' 'opencode-ticket-brief.json' 'kickoff_message'; do
  if ! grep -q "$needle" plugins/worktree.js 2>/dev/null; then
    echo "  MISSING: $needle in plugins/worktree.js"
    ERR=1
  fi
done
for needle in 'kickoff' 'KICKOFF_FAILED' 'session_notify: true'; do
  if ! grep -q "$needle" agents/worktree-manager.md 2>/dev/null; then
    echo "  MISSING: $needle in agents/worktree-manager.md"
    ERR=1
  fi
done
for needle in 'ticket_report:' 'Bootstrap' 'opencode-ticket-brief.json'; do
  if ! grep -q "$needle" skills/ticket-lifecycle/SKILL.md 2>/dev/null; then
    echo "  MISSING: $needle in skills/ticket-lifecycle/SKILL.md"
    ERR=1
  fi
done
for f in skills/github-issue-run/lib/dev-loop-watch.sh scripts/dev-loop-poller.sh; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    ERR=1
  elif [[ ! -x "$f" ]]; then
    echo "  NOT EXECUTABLE: $f"
    ERR=1
  fi
done
for agent in developer.md frontend-dev.md ux-dev.md; do
  if ! grep -q 'session_notify: true' "agents/$agent" 2>/dev/null; then
    echo "  MISSING: session_notify in agents/$agent"
    ERR=1
  fi
done
if ! grep -q '"worktree-manager"' opencode.json 2>/dev/null; then
  echo "  MISSING: worktree-manager agent entry in opencode.json"
  ERR=1
fi

if [[ $ERR -ne 0 ]]; then
  echo "validate-opencode-config: FAILED"
  exit 1
fi
echo "validate-opencode-config: OK"
exit 0
