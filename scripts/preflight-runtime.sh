#!/usr/bin/env bash
# Resolve project vs host Node for preflight. Flexible: mise / asdf / fnm / nvm / volta / PATH.
# Sandbox mode: when the opencode-server Sysbox sibling is the runtime
#   (OPENCODE_SANDBOX_ENABLED=1|true|yes, or `sandbox` CLI on PATH, or docker.sock + OPENCODE_SANDBOX_MODE set),
#   host toolchain detection is skipped and the pinned toolchain is validated inside the sibling
#   via `sandbox create/exec/destroy`. See execution_env / sandbox_toolchain / sandbox_id in the JSON.
# Usage: preflight-runtime.sh [--repair]
#   --repair  once: mise trust / mise install when a mise pin exists and the tool is available
#             (sandbox mode: no host repair; the sibling probe performs mise trust/install inside the sibling)
# Emits JSON on stdout. Does not print secrets.
# Exit 0: ok | ok_with_notes | skipped_no_node_project
# Exit 1: project toolchain missing / engines mismatch on project node
# Exit 2: missing jq
set -euo pipefail

REPAIR=false
if [[ "${1:-}" == "--repair" ]]; then
  REPAIR=true
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "preflight-runtime: jq is required" >&2
  exit 2
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
fi

ROOT="$(pwd)"
notes=()
commands_run=()
add_cmd() { commands_run+=("$1"); }
add_note() { notes+=("$1"); }

json_escape_array() {
  # stdin: lines → JSON string array
  jq -Rnc '[inputs]'
}

# --- Execution environment: sandbox sibling vs local host ---
execution_env="local"
if [[ "${OPENCODE_SANDBOX_ENABLED:-}" == "1" || "${OPENCODE_SANDBOX_ENABLED:-}" == "true" || "${OPENCODE_SANDBOX_ENABLED:-}" == "yes" ]] || command -v sandbox >/dev/null 2>&1 || { [[ -e /var/run/docker.sock ]] && [[ -n "${OPENCODE_SANDBOX_MODE:-}" ]]; }; then
  execution_env="sandbox"
fi

version_maj() {
  local v="${1#v}"
  echo "${v%%.*}"
}

if [[ "$execution_env" == "sandbox" ]]; then
  # Sibling (opencode-server Sysbox) is the runtime: host toolchain detection is skipped entirely.
  # Sibling id: worktree basename → DNS label (docker-sandbox skill ID hygiene).
  sandbox_id="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-{2,}/-/g; s/^-+//; s/-+$//')"
  [[ -n "$sandbox_id" ]] || sandbox_id="preflight"

  sb_created=false
  sandbox_teardown() {
    if [[ "$sb_created" == true ]]; then
      sandbox destroy --id "$sandbox_id" >/dev/null 2>&1 || true
    fi
  }
  trap sandbox_teardown EXIT

  sb_pin_file=""
  if [[ -f .mise.toml ]]; then sb_pin_file=".mise.toml"
  elif [[ -f mise.toml ]]; then sb_pin_file="mise.toml"
  elif [[ -f .tool-versions ]]; then sb_pin_file=".tool-versions"
  elif [[ -f .node-version ]]; then sb_pin_file=".node-version"
  elif [[ -f .nvmrc ]]; then sb_pin_file=".nvmrc"
  elif [[ -f package.json ]] && jq -e '.volta.node // empty' package.json >/dev/null 2>&1; then sb_pin_file="package.json#volta"
  fi
  sb_via="path"
  [[ -f .mise.toml || -f mise.toml ]] && sb_via="mise"

  sb_toolchain_status="ready"
  sb_engines_status="skipped_no_engines"
  sb_overall="ok"
  sb_exit=0
  sb_blocker=""
  sb_recommended=""
  sb_node=""
  sb_ruby=""
  sb_yarn=""
  sb_engines=""

  add_note "execution_env: sandbox — toolchain validated inside sibling 'opencode-sandbox-$sandbox_id'; host toolchain not inspected."
  if [[ "$REPAIR" == true ]]; then
    add_note "--repair performs no host repair in sandbox mode; the sibling probe runs mise trust/install inside the sibling."
  fi

  # Probe — gating in sandbox mode (unavailable is the only sandbox capability path that Blocks).
  probe_ok=false
  probe_out=""
  if command -v sandbox >/dev/null 2>&1; then
    add_cmd "sandbox probe"
    if probe_out="$(sandbox probe 2>&1)"; then
      if printf '%s' "$probe_out" | jq -e '.available == true' >/dev/null 2>&1; then
        probe_ok=true
      elif ! printf '%s' "$probe_out" | jq -e 'has("available")' >/dev/null 2>&1; then
        if ! printf '%s' "$probe_out" | grep -q "SANDBOX_UNAVAILABLE"; then
          probe_ok=true
        fi
      fi
    fi
  else
    add_note "sandbox CLI not found on PATH."
  fi

  if [[ "$probe_ok" != true ]]; then
    sb_toolchain_status="sandbox_unavailable"
    sb_engines_status="sandbox_unavailable"
    sb_overall="blocked"
    sb_exit=1
    sb_blocker="ENV_BLOCKED"
    sb_recommended="sandbox CLI unavailable — start opencode-server sandbox or unset OPENCODE_SANDBOX_ENABLED"
  else
    # Create or reuse (status guard avoids double-create).
    add_cmd "sandbox status --id $sandbox_id"
    if sandbox status --id "$sandbox_id" >/dev/null 2>&1; then
      add_note "Reusing existing sandbox '$sandbox_id'; preflight does not destroy sandboxes it did not create."
    else
      add_cmd "sandbox create --id $sandbox_id --worktree $ROOT"
      if sandbox create --id "$sandbox_id" --worktree "$ROOT" >/dev/null 2>&1 || sandbox create --id "$sandbox_id" --worktree "$ROOT" >/dev/null 2>&1; then
        sb_created=true
      else
        sb_toolchain_status="sandbox_error"
        sb_engines_status="sandbox_error"
        sb_overall="blocked"
        sb_exit=1
        sb_blocker="ENV_BLOCKED"
        sb_recommended="sibling could not run pinned toolchain — run \`sandbox exec --id $sandbox_id -- mise install\` manually and re-run preflight"
      fi
    fi
  fi

  # One in-sibling probe covering the project pin in a single round trip.
  if [[ "$sb_exit" -eq 0 ]]; then
    sb_probe_script='set -e
if [ -f .mise.toml ] || [ -f mise.toml ]; then mise trust --yes >/dev/null 2>&1 || true
  mise install
  mise exec -- bash -lc "node -v; (bundle -v 2>/dev/null || true); (yarn -v 2>/dev/null || true)"
else
  node -v; (bundle -v 2>/dev/null || true); (yarn -v 2>/dev/null || true)
fi'
    add_cmd "sandbox exec --id $sandbox_id -- bash -lc '<pinned toolchain probe: mise trust/install + node/bundle/yarn versions>'"
    exec_ok=false
    exec_out=""
    if exec_out="$(sandbox exec --id "$sandbox_id" -- bash -lc "$sb_probe_script" 2>&1)"; then
      exec_ok=true
    elif exec_out="$(sandbox exec --id "$sandbox_id" -- bash -lc "$sb_probe_script" 2>&1)"; then
      exec_ok=true
    fi
    if [[ "$exec_ok" != true ]]; then
      sb_toolchain_status="sandbox_error"
      sb_engines_status="sandbox_error"
      sb_overall="blocked"
      sb_exit=1
      sb_blocker="ENV_BLOCKED"
      sb_recommended="sibling could not run pinned toolchain — run \`sandbox exec --id $sandbox_id -- mise install\` manually and re-run preflight"
      add_note "sandbox exec failed: $(printf '%s' "$exec_out" | head -c 200)"
    else
      sb_node="$(printf '%s\n' "$exec_out" | grep -Eo '^v[0-9]+(\.[0-9]+)*' | head -n1 | tr -d '\r')"
      sb_ruby="$(printf '%s\n' "$exec_out" | grep -i 'bundler version' | head -n1 | sed -E 's/.*[Bb]undler version[[:space:]]+([0-9.]+).*/\1/' | tr -d '\r')"
      sb_yarn="$(printf '%s\n' "$exec_out" | grep -Eo '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | head -n1 | tr -d '\r')"
      if [[ -z "$sb_node" ]]; then
        sb_toolchain_status="sandbox_error"
        sb_engines_status="sandbox_error"
        sb_overall="blocked"
        sb_exit=1
        sb_blocker="ENV_BLOCKED"
        sb_recommended="sibling could not run pinned toolchain — run \`sandbox exec --id $sandbox_id -- mise install\` manually and re-run preflight"
        add_note "sandbox exec succeeded but no node version was captured in its output."
      fi
    fi
  fi

  # engines.node compared against the sibling-reported node (same semantics as the local branch).
  if [[ "$sb_exit" -eq 0 ]]; then
    if [[ -f package.json ]]; then
      sb_engines="$(jq -r '.engines.node // empty' package.json 2>/dev/null || true)"
    fi
    if [[ -z "$sb_engines" ]]; then
      sb_engines_status="skipped_no_engines"
    else
      sb_maj="$(version_maj "$sb_node")"
      sb_engines_status="unknown_range"
      if [[ "$sb_engines" =~ \^([0-9]+) ]]; then
        if [[ "$sb_maj" == "${BASH_REMATCH[1]}" ]]; then sb_engines_status="sandbox_ok"; else sb_engines_status="mismatch_project"; fi
      elif [[ "$sb_engines" =~ ~([0-9]+) ]]; then
        if [[ "$sb_maj" == "${BASH_REMATCH[1]}" ]]; then sb_engines_status="sandbox_ok"; else sb_engines_status="mismatch_project"; fi
      elif [[ "$sb_engines" =~ \>\=?([0-9]+) ]]; then
        if [[ "$sb_maj" -ge "${BASH_REMATCH[1]}" ]]; then sb_engines_status="sandbox_ok"; else sb_engines_status="mismatch_project"; fi
      elif [[ "$sb_engines" =~ (^|[[:space:]])([0-9]+)(\.x|\.\*|\.0\.0)?($|[[:space:]]) ]]; then
        if [[ "$sb_maj" == "${BASH_REMATCH[2]}" ]]; then sb_engines_status="sandbox_ok"; else sb_engines_status="mismatch_project"; fi
      else
        add_note "Could not parse engines.node '$sb_engines' against sibling node $sb_node; not treating as failure."
      fi
      if [[ "$sb_engines_status" == "mismatch_project" ]]; then
        sb_overall="blocked"
        sb_exit=1
        sb_blocker="ENV_BLOCKED"
        sb_recommended="Sibling Node is $sb_node but package.json engines.node is '$sb_engines'. Fix the sibling pin${sb_pin_file:+ ($sb_pin_file)} and run \`sandbox exec --id $sandbox_id -- mise install\` — do not install Node on the host."
      elif [[ "$sb_engines_status" == "sandbox_ok" ]]; then
        add_note "Sibling Node $sb_node satisfies engines.node ($sb_engines)."
      fi
    fi
  fi

  if [[ "$sb_exit" -eq 0 && ${#notes[@]} -gt 0 ]]; then
    sb_overall="ok_with_notes"
  fi

  notes_json='[]'
  if [[ ${#notes[@]} -gt 0 ]]; then
    notes_json="$(printf '%s\n' "${notes[@]}" | json_escape_array)"
  fi
  cmds_json='[]'
  if [[ ${#commands_run[@]} -gt 0 ]]; then
    cmds_json="$(printf '%s\n' "${commands_run[@]}" | json_escape_array)"
  fi

  sb_toolchain_json="null"
  if [[ -n "$sb_node" ]]; then
    sb_toolchain_json="$(jq -nc --arg node "$sb_node" --arg ruby "$sb_ruby" --arg yarn "$sb_yarn" --arg via "$sb_via" \
      '{node: (if $node == "" then null else $node end), ruby: (if $ruby == "" then null else $ruby end), yarn: (if $yarn == "" then null else $yarn end), via: $via}')"
  fi

  jq -nc \
    --arg status "$sb_overall" \
    --arg root "$ROOT" \
    --arg execution_env "sandbox" \
    --arg sandbox_id "$sandbox_id" \
    --argjson sandbox_toolchain "$sb_toolchain_json" \
    --arg project_version "$sb_node" \
    --arg via "$sb_via" \
    --arg pin_file "$sb_pin_file" \
    --arg toolchain_status "$sb_toolchain_status" \
    --arg command_prefix "sandbox exec --id $sandbox_id --" \
    --arg engines_node "$sb_engines" \
    --arg engines_status "$sb_engines_status" \
    --argjson notes "$notes_json" \
    --argjson commands_run "$cmds_json" \
    --arg recommended_env_fix "$sb_recommended" \
    --arg blocker_code "$sb_blocker" \
    '{
      status: $status,
      root: $root,
      execution_env: $execution_env,
      sandbox_id: $sandbox_id,
      sandbox_toolchain: $sandbox_toolchain,
      host_node: {
        version: null,
        path: null,
        role: "host_or_image"
      },
      project_node: {
        version: (if $project_version == "" then null else $project_version end),
        path: null,
        via: (if $via == "" then null else $via end),
        pin_file: (if $pin_file == "" then null else $pin_file end),
        toolchain_status: $toolchain_status,
        command_prefix: $command_prefix,
        error: null
      },
      engines_node: (if $engines_node == "" then null else $engines_node end),
      engines_status: $engines_status,
      package_managers: {
        pnpm: null,
        npm: null
      },
      repair_applied: false,
      notes: $notes,
      commands_run: $commands_run,
      recommended_env_fix: (if $recommended_env_fix == "" then null else $recommended_env_fix end)
    }
    + (if $blocker_code == "" then {} else {blocker_code: $blocker_code} end)
    + {
        policy: "In execution_env: sandbox the opencode-server Sysbox sibling is the build/test runtime. Compare engines.node to sandbox_toolchain.node (project_node.version), never to host Node; never recommend installing toolchains on the host."
      }'

  exit "$sb_exit"
fi

# --- Host / image Node (OpenCode + MCP; may intentionally be 22) ---
host_version=""
host_path=""
if command -v node >/dev/null 2>&1; then
  add_cmd "command -v node; node -v"
  host_path="$(command -v node)"
  host_version="$(node -v 2>/dev/null || true)"
fi

# --- Detect project pin + runner (first match wins) ---
pin_file=""
via=""
prefix=()          # command prefix words, e.g. mise exec --
repair_hint=""
toolchain_status="none"  # none | ready | pin_without_tool | tool_error

find_mise() {
  local c
  for c in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  command -v mise 2>/dev/null || true
}

if [[ -f .mise.toml || -f mise.toml ]]; then
  pin_file="$([[ -f .mise.toml ]] && echo .mise.toml || echo mise.toml)"
  mise_bin="$(find_mise)"
  if [[ -n "$mise_bin" ]]; then
    via="mise"
    prefix=("$mise_bin" exec --)
    toolchain_status="ready"
    repair_hint="mise trust --yes && mise install && mise exec -- node -v"
  else
    via="mise"
    toolchain_status="pin_without_tool"
    repair_hint="Install mise (https://mise.jdx.dev), then: mise trust --yes && mise install"
  fi
elif [[ -f .tool-versions ]]; then
  pin_file=".tool-versions"
  if command -v asdf >/dev/null 2>&1; then
    via="asdf"
    prefix=(asdf exec)
    toolchain_status="ready"
    repair_hint="asdf install && asdf reshim node"
  elif [[ -n "$(find_mise)" ]]; then
    # mise also reads .tool-versions
    via="mise"
    mise_bin="$(find_mise)"
    prefix=("$mise_bin" exec --)
    toolchain_status="ready"
    repair_hint="mise trust --yes && mise install"
  else
    via="asdf_or_mise"
    toolchain_status="pin_without_tool"
    repair_hint="Install asdf or mise and install the Node version from .tool-versions"
  fi
elif [[ -f .node-version || -f .nvmrc ]]; then
  pin_file="$([[ -f .node-version ]] && echo .node-version || echo .nvmrc)"
  if command -v fnm >/dev/null 2>&1; then
    via="fnm"
    prefix=(fnm exec --)
    toolchain_status="ready"
    repair_hint="fnm install && fnm use"
  elif command -v nvm >/dev/null 2>&1 || [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    via="nvm"
    # nvm is a shell function — run via bash login-ish
    prefix=()
    toolchain_status="ready"
    repair_hint="nvm install && nvm use"
  elif command -v asdf >/dev/null 2>&1; then
    via="asdf"
    prefix=(asdf exec)
    toolchain_status="ready"
    repair_hint="asdf install node && asdf reshim node"
  elif [[ -n "$(find_mise)" ]]; then
    via="mise"
    mise_bin="$(find_mise)"
    prefix=("$mise_bin" exec --)
    toolchain_status="ready"
    repair_hint="mise install node && mise exec -- node -v"
  else
    via="fnm_nvm_or_asdf"
    toolchain_status="pin_without_tool"
    repair_hint="Install fnm, nvm, asdf, or mise so $pin_file is honored"
  fi
elif [[ -f package.json ]] && jq -e '.volta.node // empty' package.json >/dev/null 2>&1; then
  pin_file="package.json#volta"
  if command -v volta >/dev/null 2>&1; then
    via="volta"
    prefix=(volta run)
    toolchain_status="ready"
    repair_hint="volta install node"
  else
    via="volta"
    toolchain_status="pin_without_tool"
    repair_hint="Install volta so package.json volta.node is honored"
  fi
fi

# Optional repair for mise trust/install
repair_applied=false
if [[ "$REPAIR" == true && "$via" == "mise" && -n "$(find_mise)" ]]; then
  mise_bin="$(find_mise)"
  add_cmd "$mise_bin trust --yes"
  if "$mise_bin" trust --yes >/dev/null 2>&1; then
    repair_applied=true
  fi
  add_cmd "$mise_bin install"
  if "$mise_bin" install >/dev/null 2>&1; then
    repair_applied=true
    toolchain_status="ready"
  fi
fi

# --- Project Node ---
project_version=""
project_path=""
project_error=""

run_project_node() {
  if [[ "$via" == "nvm" ]]; then
    local nvm_script="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    if [[ -s "$nvm_script" ]]; then
      # shellcheck disable=SC1090
      bash -lc 'set -e; . "$1"; shift; nvm use >/dev/null; exec node "$@"' bash "$nvm_script" "$@"
      return $?
    fi
  fi
  if [[ ${#prefix[@]} -gt 0 ]]; then
    "${prefix[@]}" node "$@"
    return $?
  fi
  node "$@"
}

if [[ "$toolchain_status" == "ready" || "$toolchain_status" == "none" ]]; then
  if [[ "$toolchain_status" == "none" ]]; then
    via="${via:-path}"
    if [[ -n "$host_version" ]]; then
      project_version="$host_version"
      project_path="$host_path"
      add_note "No project Node pin (.mise.toml / .tool-versions / .node-version / .nvmrc / volta); using host PATH Node."
    fi
  else
    add_cmd "${prefix[*]+${prefix[*]} }node -v"
    if project_out="$(run_project_node -v 2>&1)"; then
      project_version="$(echo "$project_out" | tail -n1 | tr -d '\r')"
      if project_which="$(run_project_node -p 'process.execPath' 2>/dev/null)"; then
        project_path="$project_which"
      fi
    else
      project_error="$project_out"
      toolchain_status="tool_error"
      add_note "Project toolchain ($via) failed to run node: $(echo "$project_out" | head -c 200)"
    fi
  fi
fi

# --- engines.node ---
engines=""
if [[ -f package.json ]]; then
  engines="$(jq -r '.engines.node // empty' package.json 2>/dev/null || true)"
fi

# Compare version against a simple engines range (common cases).
# Returns 0 if satisfies / unknown-conservative ok; 1 if clear mismatch.
version_maj() {
  local v="${1#v}"
  echo "${v%%.*}"
}

engines_status="skipped_no_engines"
if [[ -z "$engines" ]]; then
  engines_status="skipped_no_engines"
elif [[ "$toolchain_status" == "pin_without_tool" ]]; then
  engines_status="project_toolchain_missing"
elif [[ "$toolchain_status" == "tool_error" || -n "$project_error" ]]; then
  engines_status="project_toolchain_error"
elif [[ -z "$project_version" ]]; then
  engines_status="no_project_node"
else
  # Prefer node+semver when available via project runner; else major heuristic for ^/~/>=
  set +e
  run_project_node -e "
    const range = process.argv[1];
    const ver = process.argv[2].replace(/^v/, '');
    try {
      const semver = require('semver');
      process.exit(semver.satisfies(ver, range) ? 0 : 1);
    } catch {
      process.exit(2);
    }
  " "$engines" "$project_version" >/dev/null 2>&1
  code=$?
  set -e
  if [[ $code -eq 0 ]]; then
    engines_status="ok"
  elif [[ $code -eq 1 ]]; then
    engines_status="mismatch_project"
  else
      # Heuristic: ^24 / ~24 / >=24 / 24.x
      maj="$(version_maj "$project_version")"
      want=""
      if [[ "$engines" =~ \^([0-9]+) ]]; then
        want="${BASH_REMATCH[1]}"
        if [[ "$maj" == "$want" ]]; then engines_status="ok"; else engines_status="mismatch_project"; fi
      elif [[ "$engines" =~ ~([0-9]+) ]]; then
        want="${BASH_REMATCH[1]}"
        if [[ "$maj" == "$want" ]]; then engines_status="ok"; else engines_status="mismatch_project"; fi
      elif [[ "$engines" =~ \>\=?([0-9]+) ]]; then
        want="${BASH_REMATCH[1]}"
        if [[ "$maj" -ge "$want" ]]; then engines_status="ok"; else engines_status="mismatch_project"; fi
      elif [[ "$engines" =~ (^|[[:space:]])([0-9]+)(\.x|\.\*|\.0\.0)?($|[[:space:]]) ]]; then
        want="${BASH_REMATCH[2]}"
        if [[ "$maj" == "$want" ]]; then engines_status="ok"; else engines_status="mismatch_project"; fi
      else
        engines_status="unknown_range"
        add_note "Could not parse engines.node '$engines' against $project_version; not treating as failure."
      fi
  fi
fi

# Host vs engines — informational only (never recommend upgrading image Node)
host_engines_note=false
if [[ -n "$engines" && -n "$host_version" ]]; then
  host_maj="$(version_maj "$host_version")"
  if [[ "$engines" =~ \^([0-9]+) ]]; then
    if [[ "$host_maj" != "${BASH_REMATCH[1]}" ]]; then host_engines_note=true; fi
  elif [[ "$engines" =~ \>\=?([0-9]+) ]]; then
    if [[ "$host_maj" -lt "${BASH_REMATCH[1]}" ]]; then host_engines_note=true; fi
  fi
fi

if [[ "$host_engines_note" == true ]]; then
  add_note "Host/PATH Node is $host_version (often the OpenCode/image runtime for MCP). Do not upgrade the image Node to silence engines.node ($engines). Use the project toolchain ($via) for installs and builds."
fi

if [[ "$engines_status" == "ok" && "$host_engines_note" == true ]]; then
  add_note "Project Node $project_version via $via satisfies engines.node ($engines)."
fi

# Package managers under project prefix
pnpm_version=""
npm_version=""
if [[ -n "$project_version" && "$toolchain_status" != "tool_error" ]]; then
  if [[ ${#prefix[@]} -gt 0 ]]; then
    add_cmd "${prefix[*]} pnpm -v"
    pnpm_version="$("${prefix[@]}" pnpm -v 2>/dev/null || true)"
    npm_version="$("${prefix[@]}" npm -v 2>/dev/null || true)"
  elif [[ "$via" == "nvm" ]]; then
    pnpm_version="$(bash -lc 'set -e; . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"; nvm use >/dev/null; pnpm -v' 2>/dev/null || true)"
    npm_version="$(bash -lc 'set -e; . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"; nvm use >/dev/null; npm -v' 2>/dev/null || true)"
  else
    pnpm_version="$(pnpm -v 2>/dev/null || true)"
    npm_version="$(npm -v 2>/dev/null || true)"
  fi
fi

# Overall status / fix
recommended=""
blocker=""
overall="ok"
exit_code=0

case "$engines_status" in
  project_toolchain_missing)
    overall="blocked"
    exit_code=1
    blocker="ENV_BLOCKED"
    recommended="$repair_hint"
    ;;
  project_toolchain_error)
    overall="blocked"
    exit_code=1
    blocker="ENV_BLOCKED"
    recommended="${repair_hint:-Fix $via so project node runs (mise trust / install, asdf install, etc.)}"
    ;;
  mismatch_project)
    overall="blocked"
    exit_code=1
    blocker="ENV_BLOCKED"
    recommended="Project Node is $project_version via $via but package.json engines.node is '$engines'. Install/activate the pinned version (${repair_hint:-see README}) — do not bump the OpenCode/image Node."
    ;;
  no_project_node)
    overall="blocked"
    exit_code=1
    blocker="ENV_BLOCKED"
    recommended="Node not found on PATH or via project toolchain. Install Node for this repo (mise/asdf/fnm/nvm/volta or system package manager)."
    ;;
  *)
    if [[ ${#notes[@]} -gt 0 ]]; then
      overall="ok_with_notes"
    else
      overall="ok"
    fi
    # Host-only mismatch without pin: advisory, not blocked if build tools exist
    if [[ "$toolchain_status" == "none" && "$host_engines_note" == true ]]; then
      overall="ok_with_notes"
      recommended="package.json engines.node is '$engines' but host PATH Node is $host_version. Prefer a project pin (.mise.toml / .tool-versions / .nvmrc) so builds use the right Node. Host/image Node may stay on 22 for OpenCode/MCP."
    fi
    ;;
esac

# command_prefix string for agents
command_prefix=""
if [[ ${#prefix[@]} -gt 0 ]]; then
  command_prefix="${prefix[*]}"
elif [[ "$via" == "nvm" ]]; then
  command_prefix="nvm-use-then"
fi

notes_json='[]'
if [[ ${#notes[@]} -gt 0 ]]; then
  notes_json="$(printf '%s\n' "${notes[@]}" | json_escape_array)"
fi
cmds_json='[]'
if [[ ${#commands_run[@]} -gt 0 ]]; then
  cmds_json="$(printf '%s\n' "${commands_run[@]}" | json_escape_array)"
fi

jq -nc \
  --arg status "$overall" \
  --arg root "$ROOT" \
  --arg execution_env "$execution_env" \
  --arg host_version "$host_version" \
  --arg host_path "$host_path" \
  --arg project_version "$project_version" \
  --arg project_path "$project_path" \
  --arg via "$via" \
  --arg pin_file "$pin_file" \
  --arg toolchain_status "$toolchain_status" \
  --arg command_prefix "$command_prefix" \
  --arg engines_node "$engines" \
  --arg engines_status "$engines_status" \
  --arg pnpm_version "$pnpm_version" \
  --arg npm_version "$npm_version" \
  --argjson notes "$notes_json" \
  --argjson commands_run "$cmds_json" \
  --argjson repair_applied "$repair_applied" \
  --arg recommended_env_fix "$recommended" \
  --arg blocker_code "$blocker" \
  --arg project_error "$project_error" \
  '{
    status: $status,
    root: $root,
    execution_env: $execution_env,
    sandbox_id: null,
    sandbox_toolchain: null,
    host_node: {
      version: (if $host_version == "" then null else $host_version end),
      path: (if $host_path == "" then null else $host_path end),
      role: "host_or_image"
    },
    project_node: {
      version: (if $project_version == "" then null else $project_version end),
      path: (if $project_path == "" then null else $project_path end),
      via: (if $via == "" then null else $via end),
      pin_file: (if $pin_file == "" then null else $pin_file end),
      toolchain_status: $toolchain_status,
      command_prefix: (if $command_prefix == "" then null else $command_prefix end),
      error: (if $project_error == "" then null else $project_error end)
    },
    engines_node: (if $engines_node == "" then null else $engines_node end),
    engines_status: $engines_status,
    package_managers: {
      pnpm: (if $pnpm_version == "" then null else $pnpm_version end),
      npm: (if $npm_version == "" then null else $npm_version end)
    },
    repair_applied: $repair_applied,
    notes: $notes,
    commands_run: $commands_run,
    recommended_env_fix: (if $recommended_env_fix == "" then null else $recommended_env_fix end)
  }
  + (if $blocker_code == "" then {} else {blocker_code: $blocker_code} end)
  + {
      policy: "Compare engines.node to project_node (via pin/toolchain), not host_or_image Node. Host/image Node may stay on 22 for OpenCode + claude-context; do not recommend upgrading the Docker/base Node to silence engines warnings."
    }'

exit "$exit_code"
