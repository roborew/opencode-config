#!/usr/bin/env bash
# Install symlinks for OpenCode CLI tools into ~/.local/bin (add to PATH).
set -euo pipefail
OC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${HOME}/.local/bin"
mkdir -p "$DEST"
for cmd in setup-project feature-upgrade new-spec-repo link-spec-repo upgrade-spec-repo; do
  src="${OC}/bin/${cmd}"
  [[ -f "$src" ]] || continue
  ln -sf "$src" "${DEST}/${cmd}"
done
echo "Linked OpenCode CLI tools into ${DEST}"
echo "Ensure ${DEST} is on your PATH, e.g.:"
echo "  export PATH=\"${DEST}:\$PATH\""
