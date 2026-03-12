---
description: Generates documentation content from completed plan artifacts. Read-only; returns content for scribe to write.
mode: subagent
model: openrouter/minimax/minimax-m2.5
tools:
  write: false
  edit: false
  bash: true
  skill: true
permission:
  edit: deny
  skill: { "*": "allow" }
prompt: "{file:~/.config/opencode/prompts/document.md}"
---
