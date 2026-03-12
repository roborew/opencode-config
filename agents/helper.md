---
description: Recovery replanner for blocked or failed stages
mode: subagent
model: openrouter/openai/gpt-5.3-codex
tools:
  write: false
  edit: false
  bash: true
  skill: true
permission:
  edit: deny
  skill: { "*": "allow" }
  task:
    "*": deny
    scribe: allow
prompt: "{file:~/.config/opencode/prompts/helper.md}"
---
