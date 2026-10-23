#!/usr/bin/env bash
# Imports the project, then runs every tests/*.gd headless. Exits non-zero on any failure.
# Usage: pvpve/tools/run_tests.sh [test_file.gd ...]   (default: all)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="$DIR/godot.sh"

"$GODOT" --headless --import >/dev/null 2>&1

if [ "$#" -gt 0 ]; then
	tests=("$@")
else
	tests=()
	for path in "$DIR"/../tests/*.gd; do tests+=("$(basename "$path")"); done
fi

failed=0
for name in "${tests[@]}"; do
	output=$(timeout 300 "$GODOT" --headless --script "res://tests/$name" 2>&1)
	code=$?
	if [ "$code" -ne 0 ] || grep -qE 'SCRIPT ERROR|Parse Error|^ERROR:' <<<"$output"; then
		failed=1
		echo "FAIL $name (exit $code)"
		echo "$output" | tail -60
	else
		echo "PASS $name"
	fi
done
exit $failed
