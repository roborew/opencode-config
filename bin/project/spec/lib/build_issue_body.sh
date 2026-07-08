# shellcheck shell=bash
# Shared fanout issue body builder. Source from central opencode-run spec fanout and sync-fanout-bodies.

build_issue_body() {
  local parent="$1" slug="$2" meta_json="$3" blocked_line="$4" extra_md="$5"
  local user_stories_section="${6:-}"
  local implementation_plan_section="${7:-}"

  if [[ -z "$user_stories_section" ]]; then
    user_stories_section="_Map PRD user stories to this ticket during \`issue-expand\` in the implementation repo. If the PRD ticket lists \`covers_user_stories\`, include those._"
  fi
  if [[ -z "$implementation_plan_section" ]]; then
    implementation_plan_section="_Add files, TDD order, and risks during \`issue-expand\` before orchestrate._"
  fi

  cat <<EOF
Parent PRD: ${parent}

## User stories covered

${user_stories_section}

## Implementation plan

${implementation_plan_section}

## OpenCode task (machine-readable)
\`\`\`opencode-task-json
${meta_json}
\`\`\`

${blocked_line}

## Description

${extra_md}

---
Branch suggestion: feature/${slug}
EOF
}
