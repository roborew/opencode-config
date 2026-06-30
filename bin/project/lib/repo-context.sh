# shellcheck shell=bash
# Shared repo context for central project scripts (invoked via opencode-run).
# Usage: opencode_project_init spec|impl
opencode_project_init() {
  local kind="${1:?spec or impl}"
  OC="${OPENCODE_CONFIG_DIR:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
  BIN_DIR="${OC}/bin/project/${kind}"
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: must run inside a git repository (use opencode-run from repo cwd)" >&2
    exit 2
  }
  cd "$ROOT"
  [[ -d "$BIN_DIR" ]] || {
    echo "ERROR: missing OpenCode project tooling at ${BIN_DIR}" >&2
    exit 8
  }
}
