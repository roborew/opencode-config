<!-- Scope: Python API, workers, services (`**/*.py`, `**/api/**`, `**/workers/**`) -->

# Python / FastAPI backend

- Validate inputs at HTTP boundaries (Pydantic models or equivalent).
- Use parameterized queries / ORM bindings—no string interpolation of user input into SQL.
- Propagate `context`/`request_id` for tracing; avoid logging secrets or full PII.
- Prefer explicit dependency injection over hidden globals for testability.
- For async routes, avoid blocking I/O in the event loop; use async clients or thread pools when needed.
