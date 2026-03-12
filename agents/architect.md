---
description: High-level planner for serious features and refactors. Plans only, delegates scribe to persist .plan artifact, then hands off to orchestrator.
mode: primary
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
    debugger: allow
    refactor: allow
    review: allow
    document: allow
    scribe: allow
prompt: "{file:~/.config/opencode/prompts/architect.md}"
---
