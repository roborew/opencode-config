---
description: Non-writing execution orchestrator for artifact-driven stage flow
mode: primary
model: openrouter/inception/mercury-2
tools:
  write: false
  edit: false
  bash: false
  skill: true
permission:
  edit: deny
  skill: { "*": "allow" }
  task:
    "*": deny
    scribe: allow
    implementor: allow
    designer: allow
    verifier: allow
    helper: allow
prompt: "{file:~/.config/opencode/prompts/orchestrator.md}"
---
