---
description: Recovery replanner for blocked or failed stages
mode: subagent
model: openrouter/openai/gpt-5.3-codex
tools:
  write: false
  edit: false
  bash: true
permission:
  edit: deny
  task:
    "*": deny
    scribe: allow
prompt: "{file:~/.config/opencode/skills/helper/SKILL.md}"
---
