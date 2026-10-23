#!/usr/bin/env bash
# Runs Godot against the pvpve project. Usage: pvpve/tools/godot.sh [godot args...]
# Uses a local `godot` if present; otherwise falls back to the chroot at /opt/godot-root
# (the cloud dev container, where Godot 4.4.1 comes from an Ubuntu 25.10 chroot).
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PROJECT_DIR/.." && pwd)"

if command -v godot >/dev/null 2>&1; then
	exec godot --path "$PROJECT_DIR" "$@"
fi

ROOT=/opt/godot-root
[ -d "$ROOT" ] || { echo "No godot binary and no $ROOT chroot found" >&2; exit 127; }
mountpoint -q "$ROOT/work" || { mkdir -p "$ROOT/work"; mount --bind "$REPO_DIR" "$ROOT/work"; }
mountpoint -q "$ROOT/proc" || mount -t proc proc "$ROOT/proc"
mountpoint -q "$ROOT/dev" || mount --bind /dev "$ROOT/dev"
exec chroot "$ROOT" godot --path /work/pvpve "$@"
