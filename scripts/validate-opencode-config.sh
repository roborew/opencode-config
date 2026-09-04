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

echo "Checking checkout guardrails in orchestrate + coder + execution hosts..."
GUARDRAIL_FILES="agents/orchestrate.md agents/coder.md skills/orchestrate/SKILL.md skills/ticket-lifecycle/SKILL.md agents/developer.md agents/frontend-dev.md"
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

echo "Checking WRONG_BASE transcript audit (.opencode/audit/worktree-manager/)..."
AUDIT_DIR=".opencode/audit/worktree-manager"
if [[ -d "$AUDIT_DIR" ]]; then
  WRONG_BASE_HITS=$(grep -R -l 'WRONG_BASE' "$AUDIT_DIR" 2>/dev/null || true)
  if [[ -n "$WRONG_BASE_HITS" ]]; then
    echo "  FAIL: WRONG_BASE blocker_code found in worktree-manager transcripts (invented value — not in canonical blocker_code table):"
    echo "$WRONG_BASE_HITS" | sed 's/^/    /'
    ERR=1
  else
    echo "  OK: no WRONG_BASE hits in worktree-manager transcripts"
  fi
else
  echo "  WARN: $AUDIT_DIR does not exist — audit is a no-op until worktree-manager transcripts are captured. Scaffold with: mkdir -p $AUDIT_DIR"
fi

echo "Checking session-manager plugin wiring..."
if [[ ! -f plugins/session-manager.js ]]; then
  echo "  MISSING: plugins/session-manager.js"
  ERR=1
elif ! node --check plugins/session-manager.js >/dev/null 2>&1; then
  echo "  FAIL: plugins/session-manager.js syntax check"
  ERR=1
fi
for tool in session_create session_list session_notify session_kickoff session_delete; do
  if ! grep -qE "^[[:space:]]*${tool}:[[:space:]]*\{" plugins/session-manager.js 2>/dev/null; then
    echo "  MISSING: $tool registration in plugins/session-manager.js"
    ERR=1
  fi
done
if ! grep -q "\[session-manager-plugin\] messaging tools loaded" plugins/session-manager.js 2>/dev/null; then
  echo "  MISSING: session-manager boot log line in plugins/session-manager.js"
  ERR=1
fi
# session_create envelope must surface directory_match + agent_match inside the create body
# (synchronous bind check — eliminates the follow-up-list race). Use a brace-counter to
# scope the needles to the session_create execute block so a stray match in another tool
# body doesn't satisfy the check too loosely.
extract_tool_block() {
  local file="$1" tool="$2" out="$3"
  python3 - "$file" "$tool" "$out" <<'PY'
import sys, re
path, tool, out = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read().splitlines(keepends=False)
start = None
for i, line in enumerate(src):
  m = re.match(r'^(\s*)' + re.escape(tool) + r':\s*\{$', line)
  if m:
    start = i; indent = m.group(1); break
if start is None:
  open(out, 'w').close(); sys.exit(0)
end = None
depth = 0
for j in range(start, len(src)):
  opens = src[j].count('{')
  closes = src[j].count('}')
  depth += opens - closes
  if depth == 0:
    end = j + 1; break
open(out, 'w').write('\n'.join(src[start:end or start+1]))
PY
}
extract_tool_block plugins/session-manager.js session_create /tmp/sm_create_block.$$
for needle in directory_match agent_match bind_failed; do
  if ! grep -q "$needle" /tmp/sm_create_block.$$ 2>/dev/null; then
    echo "  MISSING: $needle inside session_create envelope in plugins/session-manager.js"
    ERR=1
  fi
done
if grep -Eq 'bind_failed:\s*!\(\s*!directoryMatch\s*\|\|\s*!agentMatch\s*\)' /tmp/sm_create_block.$$; then
  echo "  REGRESSION: plugins/session-manager.js session_create computes bind_failed as !( !d || !a ) — inverts the spec truth table"
  ERR=1
fi
rm -f /tmp/sm_create_block.$$
# session_notify must wrap its GET /session lookup in a bounded retry (EVENTUAL_CONSISTENCY_RETRY
# marker) — the server commits POST /session before it surfaces in GET /session, so a freshly-created
# id can miss the first list attempt for ~250-1000 ms.
extract_tool_block plugins/session-manager.js session_notify /tmp/sm_notify_block.$$
if ! grep -q "EVENTUAL_CONSISTENCY_RETRY" /tmp/sm_notify_block.$$ 2>/dev/null; then
  echo "  MISSING: EVENTUAL_CONSISTENCY_RETRY marker inside session_notify execute body in plugins/session-manager.js"
  ERR=1
fi
# session_notify's inject call must carry `init.query = { directory: ... }` so the POST URL is
# `/session/{id}/prompt_async?directory=...` — matches the poller's working pattern at
# scripts/dev-loop-poller.sh and is defense-in-depth against server builds that scope sessions
# to the directory query param (the historical bug that motivated this guard).
if ! grep -qE 'query[[:space:]]*[:=][[:space:]]*\{\s*directory:\s*targetDir' /tmp/sm_notify_block.$$ 2>/dev/null; then
  echo "  REGRESSION: session_notify inject call missing init.query = { directory: targetDir } (Bug A — un-scope inject URL)"
  ERR=1
fi
rm -f /tmp/sm_notify_block.$$
# session_notify's sessionID branch does a single bounded GET /session lookup (EVENTUAL_CONSISTENCY_RETRY)
# to resolve the target row's directory for the `?directory=` inject URL. This is intentional and
# differs from the pre-fix design (which trusted the sessionID without listing). The old check
# forbade any listWithRetry in the sessionID branch; the new design's bounded lookup is allowed
# because (a) it is bounded (3 attempts / 250-500-1000 ms), (b) it feeds the inject URL, not
# stale-row validation. Guard: there must be NO unbounded retry / sleep loops in the sessionID
# branch between the `if (sessionID)` keyword and the matching `} else {`.
extract_tool_block plugins/session-manager.js session_notify /tmp/sm_notify_block.$$
if awk '/if \(sessionID\)/{f=1; next} f && /^[[:space:]]*\} else \{/{f=0} f' /tmp/sm_notify_block.$$ | grep -qE "while\s*\(\s*true|for\s*\(\s*[^;]*;\s*[^;]*;\s*[^)]*\)"; then
  echo "  REGRESSION: session_notify sessionID branch contains an unbounded loop (single bounded listWithRetry is allowed)"
  ERR=1
fi
rm -f /tmp/sm_notify_block.$$
# session_kickoff must use the create envelope's exact id for the inject — never any other id
# (the previous design's failure mode was the model scanning the global list and picking a
# stale row to inject into, which is structurally impossible when the inject id comes from
# the create envelope inline).
extract_tool_block plugins/session-manager.js session_kickoff /tmp/sm_kickoff_block.$$
if ! grep -q "session_kickoff" /tmp/sm_kickoff_block.$$ 2>/dev/null; then
  echo "  MISSING: session_kickoff tool body in plugins/session-manager.js"
  ERR=1
fi
if ! grep -qE "scopedListInit|query:\s*\{\s*directory\s*\}" /tmp/sm_kickoff_block.$$ 2>/dev/null; then
  echo "  REGRESSION: session_kickoff must use a scoped list (?directory=) — never unfiltered global"
  ERR=1
fi
if ! grep -qE "create_if_absent|NO_SESSION_FOR_WORKTREE" /tmp/sm_kickoff_block.$$ 2>/dev/null; then
  echo "  REGRESSION: session_kickoff must honor create_if_absent and surface NO_SESSION_FOR_WORKTREE"
  ERR=1
fi
if ! grep -qE "session_id:\s*targetId|targetId\s*=\s*sessionId\(chosen\)" /tmp/sm_kickoff_block.$$ 2>/dev/null; then
  echo "  REGRESSION: session_kickoff must inject using the chosen session id (create envelope's id or the reuse list row's id) — never a model-picked id"
  ERR=1
fi
rm -f /tmp/sm_kickoff_block.$$
# session_delete args must include force (orphan-cleanup path). Scope to the args block
# (the session_delete tool body, not the whole module).
extract_tool_block plugins/session-manager.js session_delete /tmp/sm_delete_block.$$
if ! grep -qE "^[[:space:]]+force:" /tmp/sm_delete_block.$$ 2>/dev/null; then
  echo "  MISSING: force arg in session_delete args in plugins/session-manager.js"
  ERR=1
fi
rm -f /tmp/sm_delete_block.$$

echo "Checking session-manager blocker_code allowlist + obsolete NO_SESSION_IN_DIRECTORY sweep..."
SESSION_KNOWN_BLOCKER_CODES='SESSION_TOOLS_NOT_REGISTERED|SESSION_API_FAILED|NO_SESSION_FOR_WORKTREE|SESSION_NOT_FOUND|LIST_SCOPE_INCOMPLETE|AMBIGUOUS_TARGET|CREATE_BIND_MISMATCH|KICKOFF_FAILED|KICKOFF_DIRECTORY_BIND_FAILED|KICKOFF_AGENT_BIND_MISMATCH|KICKOFF_BIND_CONFIRMATION_MISSING|KICKOFF_ALREADY_DELIVERED|KICKOFF_RESOLVED_TO_SELF|WORKTREE_API_FAILED|WORKTREE_TOOLS_NOT_REGISTERED|WORKTREE_NAME_COLLISION|WORKTREE_NOT_CLEAN_OR_PUSHED|WORKTREE_PREFLIGHT_FAILED|WORKTREE_SESSION_ATTEMPTS_EXCEEDED|BASE_NOT_PUSHED|PROTECTED_PROJECT_ROOT|NOT_A_GIT_WORKTREE|WORKTREE_RECOVERY_FAILED|HANDSHAKE_PUSH_FAILED|HANDSHAKE_FEATURE_BRANCH_CREATE_FAILED|TICKET_NOT_FORKED_FROM_FEATURE|directory_bind_failed|agent_bind_mismatch|no_session_in_directory|session_not_found|ambiguous_target|list_scope_incomplete|create_response_missing_id'
SESSION_FILES="agents/worktree-manager.md skills/orchestrate/SKILL.md skills/ticket-lifecycle/SKILL.md skills/feature-review/SKILL.md"
for f in $SESSION_FILES; do
  [[ -f "$f" ]] || continue
  CODE_LINES=$(grep -nE '"blocker_code":[[:space:]]*"[A-Za-z_0-9]+"' "$f" 2>/dev/null || true)
  if [[ -n "$CODE_LINES" ]]; then
    LISTED=$(echo "$CODE_LINES" | grep -oE '"[A-Za-z_0-9]+"' | grep -v '"blocker_code"' | tr -d '"' | sort -u)
    for code in $LISTED; do
      if ! echo "$code" | grep -qE "^($SESSION_KNOWN_BLOCKER_CODES)$"; then
        echo "  INVENTED blocker_code: \"$code\" in $f (not in canonical blocker_code allowlist)"
        ERR=1
      fi
    done
  fi
done
if grep -R -n --exclude-dir=.git --exclude-dir=.kilo 'NO_SESSION_IN_DIRECTORY' agents skills >/dev/null 2>&1; then
  echo "  ERROR: obsolete NO_SESSION_IN_DIRECTORY literal must be removed from agents/ and skills/ (replaced by NO_SESSION_FOR_WORKTREE + create_if_absent:false opt-in)"
  ERR=1
fi

echo "Checking moved lib scripts exist under scripts/..."
for f in scripts/checkout-contract.sh scripts/issue-state-transition.sh scripts/dev-loop-batch.sh scripts/dev-loop-watch.sh scripts/pr-stabilize-watch.sh scripts/feature-finish-pr.sh scripts/dev-loop-poller.sh; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    ERR=1
  elif [[ ! -x "$f" ]]; then
    echo "  NOT EXECUTABLE: $f"
    ERR=1
  fi
done

echo "Checking feature workflow contracts..."
for f in agents/code-review.md skills/code-review/SKILL.md agents/test-writer.md skills/test-writer/SKILL.md skills/orchestrate/SKILL.md; do
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
if ! grep -q 'stabilization' skills/orchestrate/SKILL.md || ! grep -q 'stabilization' skills/feature-review/SKILL.md; then
  echo "  MISSING: stabilization loop language in orchestrate or feature-review"
  ERR=1
fi
if ! grep -q 'gh pr checks' skills/ticket-lifecycle/SKILL.md; then
  echo "  MISSING: gh pr checks language in ticket-lifecycle"
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

echo "Checking worktree-sandbox plugin + agent wiring..."
if [[ ! -f plugins/sandbox.js ]]; then
  echo "  MISSING: plugins/sandbox.js"
  ERR=1
elif ! node --check plugins/sandbox.js >/dev/null 2>&1; then
  echo "  FAIL: plugins/sandbox.js syntax check"
  ERR=1
fi
for tool in sandbox_probe env_copy sandbox_create sandbox_build sandbox_warm sandbox_run_test sandbox_status sandbox_destroy; do
  if ! grep -qE "^[[:space:]]*${tool}:[[:space:]]*\{" plugins/sandbox.js 2>/dev/null; then
    echo "  MISSING: $tool registration in plugins/sandbox.js"
    ERR=1
  fi
done
if ! grep -q "\[sandbox-plugin\] compose-test backend tools loaded" plugins/sandbox.js 2>/dev/null; then
  echo "  MISSING: sandbox-plugin boot log line in plugins/sandbox.js"
  ERR=1
fi
if [[ ! -f agents/worktree-sandbox.md ]]; then
  echo "  MISSING: agents/worktree-sandbox.md"
  ERR=1
fi
if [[ ! -f skills/worktree-sandbox/SKILL.md ]]; then
  echo "  MISSING: skills/worktree-sandbox/SKILL.md"
  ERR=1
fi
if ! grep -q '"worktree-sandbox"' opencode.json 2>/dev/null; then
  echo "  MISSING: worktree-sandbox agent entry in opencode.json"
  ERR=1
fi
if ! grep -q 'worktree-sandbox: allow' agents/coder.md 2>/dev/null; then
  echo "  MISSING: worktree-sandbox in coder task allow-list"
  ERR=1
fi
if ! grep -q 'worktree-sandbox: allow' agents/orchestrate.md 2>/dev/null; then
  echo "  MISSING: worktree-sandbox in orchestrate task allow-list"
  ERR=1
fi
if ! grep -q 'sandbox_run_test' skills/ticket-lifecycle/SKILL.md 2>/dev/null; then
  echo "  MISSING: sandbox_run_test reference in skills/ticket-lifecycle/SKILL.md"
  ERR=1
fi
if ! grep -q 'sandbox_run_test' skills/feature-review/SKILL.md 2>/dev/null; then
  echo "  MISSING: sandbox_run_test reference in skills/feature-review/SKILL.md"
  ERR=1
fi
echo "Checking legacy worktree-env / preflight scripts removed..."
for f in scripts/worktree-env.sh scripts/preflight-worktree-verify.sh scripts/preflight-runtime.sh; do
  if [[ -f "$f" ]]; then
    echo "  ERROR: legacy script must be removed: $f (replaced by plugins/sandbox.js env_copy)"
    ERR=1
  fi
done
for f in agents/worktree-env.md agents/preflight.md skills/worktree-env/SKILL.md skills/preflight/SKILL.md; do
  if [[ -f "$f" ]]; then
    echo "  ERROR: legacy agent/skill must be removed: $f (replaced by agents/worktree-sandbox.md + skills/worktree-sandbox/SKILL.md)"
    ERR=1
  fi
done
if ! grep -q 'worktree-env.sh' agents/worktree-env.md skills/worktree-env/SKILL.md 2>/dev/null; then
  : # legacy agent/skill already gone — gate satisfied
elif ! grep -q 'scripts/worktree-env.sh' agents/worktree-env.md skills/worktree-env/SKILL.md 2>/dev/null; then
  echo "  MISSING: worktree-env.sh reference in worktree-env agent/skill"
  ERR=1
fi
if ! grep -q 'scripts/preflight-worktree-verify.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
  : # legacy agent/skill already gone — gate satisfied
elif ! grep -q 'scripts/preflight-worktree-verify.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
  echo "  MISSING: preflight-worktree-verify.sh reference in preflight agent/skill"
  ERR=1
fi
if ! grep -q 'scripts/preflight-runtime.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
  : # legacy agent/skill already gone — gate satisfied
elif ! grep -q 'scripts/preflight-runtime.sh' agents/preflight.md skills/preflight/SKILL.md 2>/dev/null; then
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
# Worktree plugin's tool set: 4 specific tools (worktree_create_feature,
# worktree_create_ticket, worktree_reset, worktree_list) + worktree_delete.
# The previous generic worktree_create shape was removed by the strip-back.
for tool in worktree_create_feature worktree_create_ticket worktree_list worktree_delete worktree_reset; do
  if ! grep -qE "^[[:space:]]*${tool}:[[:space:]]*\{" plugins/worktree.js 2>/dev/null; then
    echo "  MISSING: $tool registration in plugins/worktree.js"
    ERR=1
  fi
done
# The stripped-back worktree plugin must reject feature_branch values that don't
# start with `opencode/feat-` (the safety link that prevents tickets from being
# forked off develop/main/sibling tickets).
if ! grep -q "opencode/feat-" plugins/worktree.js 2>/dev/null; then
  echo "  MISSING: opencode/feat- feature_branch guard in plugins/worktree.js"
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
if ! grep -q 'recover' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: recover action in agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q 'WORKTREE_RECOVERY_FAILED' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: WORKTREE_RECOVERY_FAILED blocker code in agents/worktree-manager.md"
  ERR=1
fi
# Readiness check gate (Global Invariant #12) lives inside worktree-manager's create_ticket
# step 8.5. The needle is the literal step header so any future rename is caught here.
if ! grep -q 'Preflight check' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: Preflight check step 8.5 in agents/worktree-manager.md"
  ERR=1
fi
# KICKOFF_ALREADY_DELIVERED precondition moved from worktree-manager.kickoff step 2a to
# orchestrate SKILL §5a-iii (delegated developer Task — gh issue view against durable
# ticket_report: comments). The literal still appears in the develop loop, but the
# validator checks the orchestrator's skill, not the worktree-manager agent.
if ! grep -q 'KICKOFF_ALREADY_DELIVERED' skills/orchestrate/SKILL.md 2>/dev/null; then
  echo "  MISSING: KICKOFF_ALREADY_DELIVERED precondition literal in skills/orchestrate/SKILL.md"
  ERR=1
fi
# Global Invariant #11's per-worktree session-create cap lives in the orchestrator's
# lifecycle-log entry shape — the counter field name must appear in agents/orchestrate.md
# so a future rename is caught before a runaway kickoff storm.
if ! grep -q 'session_create_attempts' agents/orchestrate.md 2>/dev/null; then
  echo "  MISSING: session_create_attempts counter in agents/orchestrate.md lifecycle log"
  ERR=1
fi
if ! grep -q 'rewrite-worktree-gitdirs.py' agents/worktree-manager.md 2>/dev/null; then
  echo "  MISSING: sanctioned cleanup script reference in agents/worktree-manager.md"
  ERR=1
fi
if ! grep -q 'recover' skills/orchestrate/SKILL.md 2>/dev/null; then
  echo "  MISSING: recover action in skills/orchestrate/SKILL.md"
  ERR=1
fi
if ! grep -q 'do not recommend upgrading the Docker/base Node' docs/RUNBOOK.md skills/docker-sandbox/SKILL.md 2>/dev/null; then
  echo "  MISSING: Docker/image Node policy note in docs/RUNBOOK.md or skills/docker-sandbox/SKILL.md"
  ERR=1
fi

echo "Checking ticket-session kickoff reliability wiring (session_kickoff in session-manager)..."
# The actual kickoff machinery now lives in plugins/session-manager.js (the new
# session_kickoff composite tool), not in plugins/worktree.js. The worktree plugin
# was stripped back — it no longer holds session_notify, session.promptAsync, the
# brief-file machinery, or kickoff_message state. Coder holds session_notify
# directly; orchestrator holds session_kickoff directly. The pre-strip-back
# needles below are intentionally removed because the worktree plugin was simplified.
if ! grep -q 'session_kickoff:' plugins/session-manager.js 2>/dev/null; then
  echo "  MISSING: session_kickoff registration in plugins/session-manager.js"
  ERR=1
fi
for needle in 'kickoff' 'KICKOFF_ALREADY_DELIVERED' 'session_delete: true'; do
  if ! grep -q "$needle" agents/worktree-manager.md 2>/dev/null; then
    echo "  MISSING: $needle in agents/worktree-manager.md"
    ERR=1
  fi
done
for needle in 'ticket_report:' 'Bootstrap' 'opencode-task-yaml'; do
  if ! grep -q "$needle" skills/ticket-lifecycle/SKILL.md 2>/dev/null; then
    echo "  MISSING: $needle in skills/ticket-lifecycle/SKILL.md"
    ERR=1
  fi
done
for f in scripts/dev-loop-watch.sh scripts/dev-loop-poller.sh; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    ERR=1
  elif [[ ! -x "$f" ]]; then
    echo "  NOT EXECUTABLE: $f"
    ERR=1
  fi
done

echo "Checking coder primary agent wiring..."
if [[ ! -f agents/coder.md ]]; then
  echo "  MISSING: agents/coder.md"
  ERR=1
fi
if ! grep -q '"coder"' opencode.json 2>/dev/null; then
  echo "  MISSING: coder agent entry in opencode.json"
  ERR=1
fi
if ! grep -q 'session_notify: true' agents/coder.md 2>/dev/null; then
  echo "  MISSING: session_notify in coder agent"
  ERR=1
fi
if ! grep -q 'ticket-lifecycle: allow' agents/coder.md 2>/dev/null; then
  echo "  MISSING: ticket-lifecycle allow in coder agent"
  ERR=1
fi
if ! grep -q '"worktree-manager"' opencode.json 2>/dev/null; then
  echo "  MISSING: worktree-manager agent entry in opencode.json"
  ERR=1
fi

echo "Checking orchestrate bootstrap delegation (bash-less host)..."
for needle in 'You have no bash tool' '## §0 Bootstrap' 'Task developer load: minimal' 'scripts/checkout-contract.sh'; do
  if ! grep -q "$needle" skills/orchestrate/SKILL.md 2>/dev/null; then
    echo "  MISSING: $needle in skills/orchestrate/SKILL.md"
    ERR=1
  fi
done
if ! grep -q 'You have no bash tool' agents/coder.md 2>/dev/null; then
  echo "  MISSING: no-bash banner in agents/coder.md"
  ERR=1
fi
if grep -q 'preflight_skipped_on_protected_branch' skills/orchestrate/SKILL.md agents/orchestrate.md 2>/dev/null; then
  echo "  ERROR: preflight_skipped_on_protected_branch needle must be removed from orchestrate"
  ERR=1
fi
if grep -E 'preflight|worktree-env' agents/orchestrate.md skills/orchestrate/SKILL.md >/dev/null 2>&1; then
  echo "  ERROR: preflight/worktree-env must not appear in agents/orchestrate.md or skills/orchestrate/SKILL.md"
  ERR=1
fi
if grep -q 'Run preflight now' agents/orchestrate.md docs/RUNBOOK.md 2>/dev/null; then
  echo "  ERROR: orchestrate must never prompt for preflight (coder-owned)"
  ERR=1
fi

echo "Checking session_notify reverted from implementer agents..."
for agent in developer.md frontend-dev.md ux-dev.md; do
  if grep -q '^[[:space:]]*session_notify:[[:space:]]*true' "agents/$agent" 2>/dev/null; then
    echo "  ERROR: session_notify must not be set in agents/$agent (only coder holds it)"
    ERR=1
  fi
done

echo "Checking dead skills removed + new host skills present..."
for dead in orchestrate-execution orchestrate-verification orchestrate-recovery orchestrate-completion orchestrate-bootstrap orchestrate-develop-loop feature-worktree github-issue-run orchestrate-sandbox architect-feature-signoff architect-review architect-plan helper; do
  if [[ -d "skills/$dead" ]]; then
    echo "  ERROR: dead skill dir still present: skills/$dead"
    ERR=1
  fi
done
if [[ ! -f skills/orchestrate/SKILL.md ]]; then
  echo "  MISSING: skills/orchestrate/SKILL.md"
  ERR=1
fi
if [[ ! -f skills/feature-review/SKILL.md ]]; then
  echo "  MISSING: skills/feature-review/SKILL.md"
  ERR=1
fi

echo "Checking dead agents and docs removed..."
for dead in agents/helper.md docs/plan-artifact-schema.md; do
  if [[ -f "$dead" ]]; then
    echo "  ERROR: dead file still present: $dead"
    ERR=1
  fi
done

echo "Checking dead-name sweeps (repo-wide, excluding ADR history and the validator itself)..."
DEAD_NAME_EXCLUDES=( --exclude-dir=.git --exclude-dir=.kilo --exclude-dir=adr --exclude-dir=smoke --exclude=validate-opencode-config.sh )
for needle in orchestrate-sandbox architect-feature-signoff sandbox_feature_build HANDOFF_TO_FEATURE_ARCHITECT mode-f-accept-issues merge-feature-prs architect-plan architect-review archive_plan plan-artifact-schema github_feature_signoff orchestrate_coderabbit_gate; do
  if grep -R -n "${DEAD_NAME_EXCLUDES[@]}" -F "$needle" . >/dev/null 2>&1; then
    echo "  ERROR: dead name '$needle' must not appear in the source tree"
    ERR=1
  fi
done
if grep -R -n "${DEAD_NAME_EXCLUDES[@]}" -E '\.plan/|\.plan"' . >/dev/null 2>&1; then
  echo "  ERROR: .plan/ paths must not appear in the source tree"
  ERR=1
fi
if grep -R -n "${DEAD_NAME_EXCLUDES[@]}" -E 'Mode F|Mode B|Phase R' . >/dev/null 2>&1; then
  echo "  ERROR: Mode F / Mode B / Phase R must not appear in the source tree (outside ADR history)"
  ERR=1
fi

echo "Checking feature-review wiring..."
for needle in 'feature_report:' 'feature-finish-pr.sh' 'state:done' 'remediation:'; do
  if ! grep -q "$needle" skills/feature-review/SKILL.md 2>/dev/null; then
    echo "  MISSING: $needle in skills/feature-review/SKILL.md"
    ERR=1
  fi
done
for needle in 'feature-review: allow' 'code-review: allow' 'document: allow' 'scribe: allow'; do
  if ! grep -q "$needle" agents/coder.md 2>/dev/null; then
    echo "  MISSING: $needle in agents/coder.md"
    ERR=1
  fi
done
if grep -qE '^[[:space:]]*review:[[:space:]]*allow' agents/coder.md 2>/dev/null; then
  echo "  ERROR: coder must not dispatch review (architect-only analysis agent; CodeRabbit + completion summary run via code-review)"
  ERR=1
fi
if ! grep -q 'feature-review' agents/orchestrate.md 2>/dev/null; then
  echo "  MISSING: feature-review reference in agents/orchestrate.md"
  ERR=1
fi
if ! grep -q 'feature-review' skills/orchestrate/SKILL.md 2>/dev/null; then
  echo "  MISSING: feature-review reference in skills/orchestrate/SKILL.md"
  ERR=1
fi
if ! grep -q 'close-feature-issues' skills/feature-complete/SKILL.md 2>/dev/null; then
  echo "  MISSING: close-feature-issues reference in skills/feature-complete/SKILL.md"
  ERR=1
fi

echo "Checking review/code-review role boundary (review is architect-only analysis)..."
for f in agents/review.md skills/review/SKILL.md; do
  if grep -qE 'coderabbit review|CODERABBIT_|ticket_coderabbit_preflight|feature_coderabbit_gate' "$f" 2>/dev/null; then
    echo "  ERROR: $f must not run CodeRabbit or carry its execution modes (machine verification lives in the code-review agent; review is architect-only analysis)"
    ERR=1
  fi
done
for mode in ticket_coderabbit_preflight feature_coderabbit_gate; do
  if ! grep -q "$mode" skills/code-review/SKILL.md 2>/dev/null; then
    echo "  MISSING: $mode execution mode in skills/code-review/SKILL.md"
    ERR=1
  fi
done

echo "Checking dead skill names absent from live config and docs..."
if grep -R -n --exclude-dir=.git --exclude-dir=.kilo --exclude-dir=adr --exclude-dir=smoke --exclude=validate-opencode-config.sh -E 'orchestrate-(execution|verification|recovery|completion|bootstrap|develop-loop|orchestrate-sandbox)|`feature-worktree`|`github-issue-run`|architect-(feature-signoff|review|plan)' agents skills rules docs README.md CONTEXT.md >/dev/null 2>&1; then
  echo "  ERROR: references to removed skills must not appear in agents/, skills/, rules/, docs/, README.md, or CONTEXT.md"
  ERR=1
fi

echo "Checking coder default in session_kickoff..."
# The kickoff default agent is now `"coder"` (string literal) in
# `plugins/session-manager.js` `session_kickoff`'s `requestedAgent = (args && args.agent) || "coder"`.
if ! grep -q 'args.agent) || "coder"' plugins/session-manager.js 2>/dev/null; then
  echo "  ERROR: session_kickoff default agent must be coder in plugins/session-manager.js"
  ERR=1
fi

echo "Checking ORCHESTRATE_DEVELOP_LOOP flag fully removed..."
if grep -R -n --exclude-dir=.git --exclude-dir=.kilo --exclude=validate-opencode-config.sh 'ORCHESTRATE_DEVELOP_LOOP' . >/dev/null 2>&1; then
  echo "  ERROR: ORCHESTRATE_DEVELOP_LOOP must not appear anywhere in the repo"
  ERR=1
fi

echo "Checking old lib path skills/github-issue-run/lib removed from source tree..."
# bin/ and templates/ are the deployed wrapper scripts that probe the old path with
# `[[ -x ... ]] || [[ -f ... ]]` and silently no-op when the file is gone. They
# stay byte-identical per the "Explicitly NOT touched" scope of the refactor.
if grep -R -n --exclude-dir=.git --exclude-dir=.kilo --exclude-dir=bin --exclude-dir=templates --exclude=validate-opencode-config.sh 'skills/github-issue-run/lib' . >/dev/null 2>&1; then
  echo "  ERROR: old lib path skills/github-issue-run/lib must not appear in the source tree"
  ERR=1
fi

echo "Checking HANDOFF_TO_TICKET_SESSION marker removed..."
if grep -R -n --exclude-dir=.git --exclude-dir=.kilo --exclude=validate-opencode-config.sh 'HANDOFF_TO_TICKET_SESSION' . >/dev/null 2>&1; then
  echo "  ERROR: HANDOFF_TO_TICKET_SESSION must not appear anywhere"
  ERR=1
fi

echo "Checking verification backend contract..."
if ! grep -q 'docker-compose.test.yml' skills/ticket-lifecycle/SKILL.md 2>/dev/null; then
  echo "  MISSING: docker-compose.test.yml backend in skills/ticket-lifecycle/SKILL.md"
  ERR=1
fi
if ! grep -q 'ENV_BLOCKED' skills/ticket-lifecycle/SKILL.md 2>/dev/null; then
  echo "  MISSING: ENV_BLOCKED contract in skills/ticket-lifecycle/SKILL.md"
  ERR=1
fi
if ! grep -q 'all_stages: true' skills/code-review/SKILL.md 2>/dev/null; then
  echo "  MISSING: final-gate full-suite (all_stages: true) language in skills/code-review/SKILL.md"
  ERR=1
fi
if ! grep -q 'docker-compose.test.yml' skills/setup-skills/SKILL.md 2>/dev/null; then
  echo "  MISSING: docker-compose.test.yml scaffold step in skills/setup-skills/SKILL.md"
  ERR=1
fi
if ! grep -q 'compose_test_file' skills/setup-project/SKILL.md 2>/dev/null; then
  echo "  MISSING: compose_test_file registry schema in skills/setup-project/SKILL.md"
  ERR=1
fi
if ! grep -q 'docker-compose.test.yml' rules/testing.md 2>/dev/null; then
  echo "  MISSING: compose-only-backend line in rules/testing.md"
  ERR=1
fi

if [[ $ERR -ne 0 ]]; then
  echo "validate-opencode-config: FAILED"
  exit 1
fi
echo "validate-opencode-config: OK"
exit 0