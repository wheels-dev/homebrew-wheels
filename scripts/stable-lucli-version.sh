#!/usr/bin/env bash
# Print the LuCLI runtime the stable `wheels` formula should ship for a module.
#
# Usage: stable-lucli-version.sh <module-version> <lucli-tested.json> <tag-lucli.json>
#
# The stable formula ships a released module, so it must ship a LuCLI tested
# with that release line, not develop's tools/lucli.json pin (which moves ahead
# to the next line's runtime). Picks the highest version listed for the module's
# major.minor line in wheels-dev/wheels' tools/lucli-tested.json; with no entry
# (or no readable file), falls back to the pin in tools/lucli.json at the
# release's own tag. Exits non-zero if neither yields a valid version.
set -euo pipefail
MODULE="${1:?module version}"
TESTED_JSON="${2:-}"
TAG_JSON="${3:-}"
VER_RE='^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'
LINE="$(printf '%s' "$MODULE" | cut -d. -f1,2)"

PICK=""
if [ -n "$TESTED_JSON" ] && [ -s "$TESTED_JSON" ]; then
  PICK="$(jq -r --arg l "$LINE" --arg re "$VER_RE" \
    '(.lines // {})[$l] // [] | map(select(type == "string" and test($re)))
     | sort_by(split(".") | map(tonumber)) | last // empty' "$TESTED_JSON")"
fi
if [ -z "$PICK" ]; then
  [ -n "$TAG_JSON" ] && [ -s "$TAG_JSON" ] || { echo "no tested entry for $LINE and no tag pin file" >&2; exit 1; }
  PICK="$(jq -er --arg re "$VER_RE" '.LUCLI_VERSION | select(type == "string" and test($re))' "$TAG_JSON")"
fi
printf '%s\n' "$PICK"
