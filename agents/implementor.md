---
description: Unified executor for .plan artifacts. Execute only stages with Owner: implementor.
mode: subagent
model: openrouter/minimax/minimax-m2.5
steps: 20
tools:
  write: true
  edit: true
  bash: true
  skill: true
permission:
  skill: { "*": "allow" }
prompt: "{file:~/.config/opencode/prompts/implementor.md}"
---
