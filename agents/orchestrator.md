---
description: Non-writing execution orchestrator for artifact-driven stage flow
mode: primary
tools:
  write: false
  edit: false
  bash: true
permission:
  edit: deny
  task:
    "*": deny
    scribe: allow
    build: allow
    designer: allow
    verifier: allow
    helper: allow
prompt: "{file:../skills/orchestrator/SKILL.md}"
---
