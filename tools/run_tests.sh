#!/usr/bin/env bash
# Import the project and run GUT headless.
# Exits non-zero if Godot fails or GUT does not report "All tests passed!".
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

godot --headless --path . --import

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
godot --headless --path . -s res://addons/gut/gut_cmdln.gd >"$log" 2>&1
code=$?
set -e
cat "$log"
if [[ "$code" -ne 0 ]]; then
	echo "GUT exited ${code}." >&2
	exit "$code"
fi
if ! grep -q "All tests passed!" "$log"; then
	echo "GUT did not report that all tests passed." >&2
	exit 1
fi
