<!-- Scope: Next.js App Router, React (`**/app/**`, `**/*.tsx`, `**/components/**`) -->

# Next.js / React frontend

- Prefer Server Components where interactivity is not required; mark Client Components only when needed (`'use client'`).
- Preserve accessibility: semantic HTML, labels for inputs, keyboard focus for interactive elements.
- Avoid `dangerouslySetInnerHTML` unless content is sanitized; document the sanitizer.
- List keys use stable IDs, not array index, for reorderable lists.
- Avoid inline object/array literals in Context `value` when they cause broad re-renders.
