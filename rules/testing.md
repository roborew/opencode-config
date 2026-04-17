# Testing conventions

- Prefer behavior-focused tests over implementation details.
- Arrange–Act–Assert; one primary assertion per test when practical.
- Mock only at system boundaries (network, clock, filesystem); prefer real implementations elsewhere.
- After code changes, run the narrowest test that proves the fix (file or suite), not the whole repo unless needed.
- Do not skip or delete failing tests to “go green”—fix or mark explicit pending with reason.
