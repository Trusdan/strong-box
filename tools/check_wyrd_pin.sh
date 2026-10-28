#!/usr/bin/env bash
# Checks that addons/wyrd/ is an unmodified copy of the Wyrd release pinned in tools/wyrd-pin.env:
# the tag must point at the pinned commit, and the folder must match that commit's addons/wyrd/
# byte for byte (no missing, extra or changed files). Needs git and network access to GitHub.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck disable=SC1091
source tools/wyrd-pin.env

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --branch "$WYRD_TAG" "https://github.com/${WYRD_REPO}.git" "$work/wyrd" 2>/dev/null
actual="$(git -C "$work/wyrd" rev-parse HEAD)"
if [[ "$actual" != "$WYRD_COMMIT" ]]; then
	echo "Tag ${WYRD_TAG} of ${WYRD_REPO} points at ${actual}, but tools/wyrd-pin.env pins ${WYRD_COMMIT}." >&2
	exit 1
fi

# Compare the committed copy (not the working tree, so editor-generated files do not count).
mkdir -p "$work/vendored"
git archive HEAD addons/wyrd | tar -x -C "$work/vendored"
if ! diff -r -q "$work/wyrd/addons/wyrd" "$work/vendored/addons/wyrd"; then
	echo "addons/wyrd/ does not match ${WYRD_REPO}@${WYRD_TAG} (${WYRD_COMMIT}). Re-vendor it from that tag." >&2
	exit 1
fi
echo "addons/wyrd/ matches ${WYRD_REPO}@${WYRD_TAG} (${WYRD_COMMIT})."
