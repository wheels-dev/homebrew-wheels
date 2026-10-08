#!/usr/bin/env bash
# The stable formula must ship a LuCLI tested with its release line, even when
# develop's pin has moved to the next line's runtime (LuCLI 0.6.2.3 breaks
# Wheels 4.1.x MCP calls).
set -euo pipefail
cd "$(dirname "$0")/.."
BASH_BIN="${BASH_BIN:-bash}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { # <desc> <expected> <module> <tested.json|""> <tag.json|"">
  local got
  got="$("$BASH_BIN" scripts/stable-lucli-version.sh "$3" "$4" "$5" 2>/dev/null || echo "ERROR")"
  if [ "$got" = "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$2', got '$got'"; fail=1; fi
}
# develop as it will be after the 0.6.2.3 pin bump
echo '{"LUCLI_REPO":"wheels-dev/LuCLI","LUCLI_VERSION":"0.6.2.3"}' > "$T/develop-pin.json"
cat > "$T/tested.json" <<'J'
{ "_notes": "sibling key, ignored",
  "lines": { "4.1": ["0.6.2.2", "0.6.2.1", "0.6.2.10x", ""], "4.2": ["0.6.2.3"] } }
J
echo '{"LUCLI_VERSION":"0.6.2.1"}' > "$T/tag-412.json"
echo '{"LUCLI_VERSION":"0.6.3.0"}' > "$T/tag-430.json"

check "4.1.2 picks the highest tested 4.1 runtime, not develop's 0.6.2.3" "0.6.2.2" 4.1.2 "$T/tested.json" "$T/tag-412.json"
check "4.2.0 picks its own line's tested runtime"                        "0.6.2.3" 4.2.0 "$T/tested.json" "$T/tag-412.json"
check "a line with no entry falls back to its tag's pin"                  "0.6.3.0" 4.3.0 "$T/tested.json" "$T/tag-430.json"
check "a missing tested file falls back to the tag's pin"                 "0.6.2.1" 4.1.2 "" "$T/tag-412.json"
check "numeric, not lexical, ordering"                                     "0.6.2.10" 4.4.0 <(echo '{"lines":{"4.4":["0.6.2.9","0.6.2.10"]}}') "$T/tag-412.json"
check "no entry and no tag file is an error"                              "ERROR" 4.5.0 "$T/tested.json" ""
exit $fail
