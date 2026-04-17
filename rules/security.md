<!-- Scope: auth, API, middleware -->

# Security

- Authenticate and authorize on the server; never rely on UI-only checks for sensitive actions.
- Secrets only via environment or secret store—never commit real keys; use `.env.example` for names only.
- JWT: verify algorithm allowlist; check `aud`/`iss` when tokens cross services.
- CORS: avoid `origin: true` with credentials in production unless explicitly justified.
- Rate-limit or abuse-protect auth and expensive endpoints.
