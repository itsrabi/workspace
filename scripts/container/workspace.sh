#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  IMAGE=workspace:local WORKSPACE_CONTAINER=workspace HOST_USERNAME=<name> [WORKSPACE_ROOT=$HOME] \
    bash scripts/container/workspace.sh start

  IMAGE=... WORKSPACE_CONTAINER=... HOST_USERNAME=... \
    bash scripts/container/workspace.sh shell|stop|remove|sandbox

Env:
  WORKSPACE_ROOT   Mounted into the workspace container at the same absolute path. Defaults to $HOME.
  SOURCE_DIR       Used by sandbox action. Defaults to current directory.
EOF
  exit 64
}

action="${1:-}"
if [[ -z "${action}" ]]; then
  usage
fi

repo_root="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")"

IMAGE="${IMAGE:-}"
WORKSPACE_CONTAINER="${WORKSPACE_CONTAINER:-}"
HOST_USERNAME="${HOST_USERNAME:-}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME}"
SOURCE_DIR="${SOURCE_DIR:-$PWD}"

if [[ -z "$IMAGE" || -z "$WORKSPACE_CONTAINER" || -z "$HOST_USERNAME" ]]; then
  echo "Missing required env vars: IMAGE, WORKSPACE_CONTAINER, HOST_USERNAME" >&2
  exit 64
fi

ensure_container_running() {
  local name="$1"
  local status
  status="$(podman inspect --format '{{.State.Status}}' "$name" 2>/dev/null || true)"
  if [[ -z "$status" || "${status,,}" != "running" ]]; then
    echo "Workspace container '$name' is not running. Run make container-start first." >&2
    exit 1
  fi
}

parse_forward_ports() {
  local devcontainer_json="$repo_root/container/devcontainer.json"
  if [[ ! -f "$devcontainer_json" ]]; then
    return 0
  fi

  # Extract forwardPorts with minimal JSONC comment stripping.
  # Output is newline-delimited specs (e.g. 3000-3999 or 8080).
  python3 - "$devcontainer_json" <<'PY' || true
import json, re, sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    s = f.read()
lines = []
for line in s.splitlines():
    if re.match(r'^\s*//', line):
        continue
    lines.append(line)
try:
    cfg = json.loads('\n'.join(lines))
except Exception:
    sys.exit(0)
fp = cfg.get('forwardPorts')
if not fp:
    sys.exit(0)
for item in fp:
    print(item)
PY
}

publish_args_from_specs() {
  local spec
  while IFS= read -r spec; do
    [[ -z "$spec" ]] && continue
    if [[ "$spec" =~ ^[0-9]+$ ]]; then
      echo "--publish ${spec}:${spec}"
    elif [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      if (( end < start )); then
        echo "Invalid forwardPorts range: $spec" >&2
        exit 1
      fi
      echo "--publish ${start}-${end}:${start}-${end}"
    else
      echo "Unsupported forwardPorts entry: $spec" >&2
      exit 1
    fi
  done
}

podman_socket_mount_args() {
  local remote_socket remote_fs
  remote_socket="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)"
  if [[ -z "$remote_socket" ]]; then
    return 0
  fi

  remote_fs="$remote_socket"
  if [[ "$remote_socket" == unix://* ]]; then
    remote_fs="${remote_socket#unix://}"
  fi

  # Only mount if we can see the path. (Rootless backends can report transient paths.)
  if [[ -S "$remote_fs" || -e "$remote_fs" ]]; then
    echo "-v ${remote_fs}:/run/podman/podman.sock --env CONTAINER_HOST=unix:///run/podman/podman.sock"
  fi
}

if [[ "$action" == "start" ]]; then
  if ! command -v podman >/dev/null 2>&1; then
    echo "podman not found" >&2
    exit 1
  fi

  workspace_root_real="$(realpath "$WORKSPACE_ROOT")"

  # Workdir should be the mounted repo path when the repo lives under WORKSPACE_ROOT.
  workdir="/repo"
  if [[ "$repo_root" == "$workspace_root_real"* ]]; then
    workdir="$repo_root"
  fi

  podman rm -f "$WORKSPACE_CONTAINER" >/dev/null 2>&1 || true

  podman_args=(
    run -d
    --name "$WORKSPACE_CONTAINER"
    --hostname "$WORKSPACE_CONTAINER"
    -w "$workdir"
    --env "SANDBOX_IMAGE=$IMAGE"
    -v "$repo_root:/repo"
    -v "$workspace_root_real:$workspace_root_real"
  )

  # Forward ports from container/devcontainer.json when possible.
  if [[ -f "$repo_root/container/devcontainer.json" ]]; then
    mapfile -t forward_specs < <(parse_forward_ports || true)
    if [[ ${#forward_specs[@]} -gt 0 ]]; then
      mapfile -t publish_lines < <(printf '%s\n' "${forward_specs[@]}" | publish_args_from_specs || true)
      for line in "${publish_lines[@]}"; do
        # line format: --publish A:B
        opt="${line%% *}"
        arg="${line#* }"
        podman_args+=("$opt" "$arg")
      done
    fi
  fi

  # Mount rootless Podman socket if present.
  socket_mount_entry="$(podman_socket_mount_args || true)"
  if [[ -n "$socket_mount_entry" ]]; then
    # shellcheck disable=SC2206
    socket_mount_parts=( $socket_mount_entry )
    podman_args+=("${socket_mount_parts[@]}")
  else
    echo "[warn] Podman remote socket unavailable; sandbox creation may be unavailable from inside the workspace" >&2
  fi

  podman_args+=("$IMAGE" sleep infinity)

  podman "${podman_args[@]}" >/dev/null

  # Smoke the workspace using the mounted /repo.
  podman exec "$WORKSPACE_CONTAINER" bash -lc \
    "EXPECTED_USER='$HOST_USERNAME' bash '/repo/scripts/container/smoke-check.sh'"
  exit 0
fi

if [[ "$action" == "shell" ]]; then
  ensure_container_running "$WORKSPACE_CONTAINER"
  podman exec -it "$WORKSPACE_CONTAINER" bash
  exit $?
fi

if [[ "$action" == "stop" ]]; then
  if podman container exists "$WORKSPACE_CONTAINER" >/dev/null 2>&1; then
    podman stop "$WORKSPACE_CONTAINER" >/dev/null
  fi
  exit 0
fi

if [[ "$action" == "remove" ]]; then
  if podman container exists "$WORKSPACE_CONTAINER" >/dev/null 2>&1; then
    podman rm -f "$WORKSPACE_CONTAINER" >/dev/null
  fi
  exit 0
fi

if [[ "$action" == "sandbox" ]]; then
  ensure_container_running "$WORKSPACE_CONTAINER"

  workspace_root_real="$(realpath "$WORKSPACE_ROOT")"
  source_dir_real="$(realpath "$SOURCE_DIR")"

  if [[ "$source_dir_real" != "$workspace_root_real" && "$source_dir_real" != "$workspace_root_real"/* ]]; then
    echo "sandbox source directory must be under WORKSPACE_ROOT ($WORKSPACE_ROOT). Either widen WORKSPACE_ROOT or move the repo under it." >&2
    exit 2
  fi

  # In Linux workspaces, the bind-mount is at the same absolute host-visible path.
  podman exec -it "$WORKSPACE_CONTAINER" bash -lc \
    "export SANDBOX_WORKSPACE_ROOT='$workspace_root_real'; cd '$source_dir_real' && sandbox run"
  exit $?
fi

echo "Unknown action: $action" >&2
usage
