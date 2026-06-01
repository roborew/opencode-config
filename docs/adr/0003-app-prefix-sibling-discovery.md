# `${APP}-*` prefix filtering for stack discovery

`setup-project` discovers implementation repos as git siblings matching `${APP}-*` (case-insensitive) by default, excluding `*-spec`. Use `--all` to adopt every sibling git repo under the project parent. This prevents unrelated clones in a shared parent folder from being linked into the stack.

**Considered:** Discover all `.git` siblings (original behavior). Rejected — blast radius when parent folders hold multiple products.
