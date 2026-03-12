---
description: Non-writing execution orchestrator for artifact-driven stage flow
mode: primary
model: openrouter/inception/mercury-2
tools:
  write: false
  edit: false
  bash: false
permission:
  edit: deny
  task:
    "*": deny
    scribe: allow
    build: allow
    designer: allow
    verifier: allow
    helper: allow
prompt: "{file:~/.config/opencode/skills/orchestrator/SKILL.md}"
---
