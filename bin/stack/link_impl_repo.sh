#!/usr/bin/env bash
# Link one implementation repo to a spec repo (internal; use setup-project).
# Usage: link_impl_repo.sh <impl-repo-dir> <owner/name-spec-repo>
set -euo pipefail
IMPL_DIR="${1:?implementation repo directory}"
SPEC_REPO="${2:?owner/name spec repo}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$IMPL_DIR"
mkdir -p docs/agents bin
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (see `git remote get-url origin`)

## Spec repository (parent PRDs)

- **SPEC_REPO:** __SPEC_REPO__
- **SPEC_PRD_REF:** (optional — Git branch for `docs/prd/` when fetching via API, e.g. `develop`; if omitted, uses local spec checkout branch or tries develop/main)

`bin/feature-context` and `bin/issue-expand-bundle` read **SPEC_REPO** / **SPEC_PRD_REF** from this file.
EOF
if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md
else
  sed -i "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md
fi

if [[ ! -f bin/feature-context ]]; then
  install -m0755 "${ROOT}/templates/bin/feature-context" bin/feature-context
  echo "Installed bin/feature-context in $(basename "$IMPL_DIR")."
fi

touch .gitignore
if ! grep -q '^tmp/' .gitignore 2>/dev/null; then
  printf '\n# OpenCode scratch\ntmp/\n.research/\n.qa/\n.plan/*.completed.md\n' >> .gitignore
  echo "Appended OpenCode scratch paths to .gitignore in $(basename "$IMPL_DIR")."
fi

echo "Linked $(basename "$IMPL_DIR") → SPEC_REPO=${SPEC_REPO}"
