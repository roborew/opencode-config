---
description: Non-writing execution orchestrator for artifact-driven stage flow
mode: primary
model: openrouter/openai/gpt-5.3-codex
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
prompt: "{file:../skills/orchestrator/SKILL.md}"
---
