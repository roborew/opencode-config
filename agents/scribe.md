---
description: Writes plan artifacts and markdown docs only
mode: subagent
tools:
  write: true
  edit: true
  bash: false
  skill: true
permission:
  skill: { "*": "allow" }
  edit:
    "*": deny
    ".plan/*.md": allow
    ".plan/**/*.md": allow
    "*/.plan/*.md": allow
    "*/.plan/**/*.md": allow
    "docs/changelog/*.md": allow
    "docs/changelog/**/*.md": allow
    "docs/guides/*.md": allow
    "docs/guides/**/*.md": allow
    "docs/architecture/*.md": allow
    "docs/architecture/**/*.md": allow
    "*/docs/changelog/*.md": allow
    "*/docs/changelog/**/*.md": allow
    "*/docs/guides/*.md": allow
    "*/docs/guides/**/*.md": allow
    "*/docs/architecture/*.md": allow
    "*/docs/architecture/**/*.md": allow
prompt: "{file:~/.config/opencode/prompts/scribe.md}"
---
