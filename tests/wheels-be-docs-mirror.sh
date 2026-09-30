#!/usr/bin/env bash
# Exercises the offline-docs mirror in the `wheels` wrapper that
# Formula/wheels-be.rb writes at install time. The wrapper used to delete and
# re-copy ./public/wheels-docs on every command run from an app root
# (hardlinked to the shared ~/.wheels/docs cache), and a failed fallback copy
# could abort the user's command (#705). Same cases as the Linux package
# launcher's test in wheels-dev/wheels (tools/test-linux-launcher-docs-mirror.sh).
#
# The block between the wrapper's `docs-mirror begin/end` markers is rendered
# the way Homebrew renders it (a Ruby <<~EOS heredoc, so escaping and
# interpolation mistakes show up here), then run under `bash -euo pipefail`
# inside a temp app root with a fake docs cache as WHEELS_DOCS_DST. A line after
# the block proves the rest of the wrapper still runs.
#
# Needs only bash and ruby. FORMULA overrides the formula under test; BASH_BIN
# the shell the block runs under (macOS runs the wrapper with /bin/bash 3.2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SRC="${FORMULA:-Formula/wheels-be.rb}"
BASH_BIN="${BASH_BIN:-$(command -v bash)}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# render <sed range start> <sed range end> [sed filter]: print that part of the
# formula as the Ruby heredoc would produce it, with stand-ins for the
# interpolations. eval only ever sees this repo's own formula text.
render() {
  sed -n "$1,$2p" "${SRC}" | sed "${3:-}" > "${TMP}/raw.txt"
  ruby -e '
    MODULE_VERSION = "0.0.0-test"
    SQLITE_JDBC_VERSION = "0.0.0-test"
    opt_prefix = "/opt/test/wheels-be"
    java_home = "/opt/test/java"
    body = File.read(ARGV[0])
    puts eval("<<~EOS\n#{body}EOS\n")
  ' "${TMP}/raw.txt"
}

BLOCK="${TMP}/block.sh"
render '/^ *# --- docs-mirror begin/' '/^ *# --- docs-mirror end/' > "${BLOCK}"
if ! grep -q 'docs-mirror end' "${BLOCK}"; then
  echo "FAIL: could not extract the docs-mirror block from ${SRC}"
  exit 1
fi

fail=0
n=0

# new_case: fresh app root + docs cache at version 1.0.0.
new_case() {
  n=$((n + 1))
  CASE="${TMP}/case${n}"
  APP="${CASE}/app"
  CACHE="${CASE}/cache"
  mkdir -p "${APP}/vendor/wheels" "${APP}/public" "${CASE}/bin"
  echo '{}' > "${APP}/vendor/wheels/wheels.json"
  make_cache 1.0.0
}

# make_cache <version>: the unpacked bundle for <version> at ${CACHE}/<version>.
make_cache() {
  mkdir -p "${CACHE}/$1/guides"
  echo "{\"version\":\"$1\"}" > "${CACHE}/$1/manifest.json"
  echo "guide $1" > "${CACHE}/$1/guides/index.html"
}

# run_case <version>  -> sets RC, ERR, AFTER
run_case() {
  {
    printf 'WHEELS_DOCS_DST=%q\n' "${CACHE}/$1"
    cat "${BLOCK}"
    printf 'echo after-block\n'
  } > "${CASE}/wrapper.sh"
  AFTER="$(cd "${APP}" && PATH="${CASE}/bin:${PATH}" "${BASH_BIN}" -euo pipefail "${CASE}/wrapper.sh" 2>"${CASE}/stderr")"
  RC=$?
  ERR="$(cat "${CASE}/stderr")"
}

check() { # <description> <condition-result 0/1>
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "     rc=${RC} after='${AFTER}'"; echo "     stderr: ${ERR}"; fail=1
  fi
}
is() { [ "$1" = "$2" ]; echo $?; }
has() { case "$1" in *"$2"*) echo 0 ;; *) echo 1 ;; esac; }
yes() { if "$@"; then echo 0; else echo 1; fi; }

MIRROR_REL="public/wheels-docs"

# 1. First run creates the mirror.
new_case
run_case 1.0.0
M="${APP}/${MIRROR_REL}"
check "first run creates the mirror" "$(yes [ -f "${M}/guides/index.html" ])"
check "first run exits 0 and the wrapper continues" "$(is "${RC}:${AFTER}" "0:after-block")"
check "first run prints nothing" "$(is "${ERR}" "")"

# 2. The mirror is a copy, not hardlinked to the shared cache: an edit in the
#    app must not reach ~/.wheels/docs.
check "mirror files are not hardlinks of the cache" \
  "$(yes [ ! "${M}/guides/index.html" -ef "${CACHE}/1.0.0/guides/index.html" ])"
echo "edited" > "${M}/guides/index.html" 2>/dev/null || true
check "editing the mirror leaves the cache intact" \
  "$(is "$(cat "${CACHE}/1.0.0/guides/index.html")" "guide 1.0.0")"

# 3. A second run at the same version (identical manifest.json) leaves the
#    mirror in place: a sentinel written into it survives.
echo keep > "${M}/sentinel"
run_case 1.0.0
check "same-version rerun keeps the existing mirror" "$(yes [ -f "${M}/sentinel" ])"
check "same-version rerun exits 0 and continues" "$(is "${RC}:${AFTER}" "0:after-block")"

# 4. A new docs version refreshes the mirror.
make_cache 2.0.0
run_case 2.0.0
check "version change refreshes the mirror" "$(is "$(cat "${M}/guides/index.html")" "guide 2.0.0")"
check "version change drops the old mirror's files" "$(yes [ ! -e "${M}/sentinel" ])"
check "version change leaves no temp dirs in public/" \
  "$(is "$(cd "${APP}/public" && ls -A)" "wheels-docs")"

# 5. A public/wheels-docs that is not a docs mirror (no manifest.json) is the
#    user's own: left alone on the same version and after an upgrade.
new_case
mkdir -p "${APP}/${MIRROR_REL}"
echo mine > "${APP}/${MIRROR_REL}/notes.txt"
run_case 1.0.0
check "user-owned public/wheels-docs is untouched" \
  "$(is "$(ls -A "${APP}/${MIRROR_REL}"):$(cat "${APP}/${MIRROR_REL}/notes.txt")" "notes.txt:mine")"
make_cache 2.0.0
run_case 2.0.0
check "user-owned public/wheels-docs is untouched after an upgrade" \
  "$(is "$(ls -A "${APP}/${MIRROR_REL}")" "notes.txt")"

# 5b. A mirror made by the old wrapper (or `wheels docs`): manifest.json, no
#     other marker, hardlinked to the cache. Same version: left as-is.
new_case
cp -R -l "${CACHE}/1.0.0" "${APP}/${MIRROR_REL}"
M="${APP}/${MIRROR_REL}"
check "setup: old-wrapper mirror is hardlinked to the cache" \
  "$(yes [ "${M}/guides/index.html" -ef "${CACHE}/1.0.0/guides/index.html" ])"
echo keep > "${M}/sentinel"
run_case 1.0.0
check "same-version old-wrapper mirror is left as-is" \
  "$([ -f "${M}/sentinel" ] && [ "${M}/guides/index.html" -ef "${CACHE}/1.0.0/guides/index.html" ]; echo $?)"
check "same-version old-wrapper mirror: exits 0 and continues" "$(is "${RC}:${AFTER}" "0:after-block")"

# 5c. ...and a brew upgrade refreshes it (plus clears temp dirs a killed run
#     left behind), without touching the old version's cache.
make_cache 2.0.0
mkdir -p "${APP}/public/.wheels-docs-new.99999/x" "${APP}/public/.wheels-docs-old.99999/x"
run_case 2.0.0
check "old-wrapper mirror is refreshed on a version change" \
  "$(is "$(cat "${M}/guides/index.html")" "guide 2.0.0")"
check "refreshed mirror is not hardlinked to the cache" \
  "$(yes [ ! "${M}/guides/index.html" -ef "${CACHE}/2.0.0/guides/index.html" ])"
check "replacing the hardlinked mirror leaves the old cache intact" \
  "$(is "$(cat "${CACHE}/1.0.0/guides/index.html"):$(cat "${CACHE}/1.0.0/manifest.json")" \
    'guide 1.0.0:{"version":"1.0.0"}')"
check "leftover temp dirs from killed runs are cleared" \
  "$(is "$(cd "${APP}/public" && ls -A)" "wheels-docs")"

# 6. A copy failure warns on stderr but does not abort the user's command.
new_case
printf '#!%s\nexit 1\n' "${BASH_BIN}" > "${CASE}/bin/cp"
chmod +x "${CASE}/bin/cp"
run_case 1.0.0
check "copy failure exits 0 and the wrapper continues" "$(is "${RC}:${AFTER}" "0:after-block")"
check "copy failure prints a warning" "$(has "${ERR}" "could not copy the offline docs")"
check "copy failure leaves public/ clean" "$(is "$(ls -A "${APP}/public")" "")"

# 7. A failed refresh keeps the previous mirror rather than deleting it.
new_case
run_case 1.0.0
make_cache 2.0.0
printf '#!%s\nexit 1\n' "${BASH_BIN}" > "${CASE}/bin/cp"
chmod +x "${CASE}/bin/cp"
run_case 2.0.0
check "failed refresh keeps the previous mirror" \
  "$(is "$(cat "${APP}/${MIRROR_REL}/guides/index.html" 2>/dev/null)" "guide 1.0.0")"
check "failed refresh exits 0 and continues" "$(is "${RC}:${AFTER}" "0:after-block")"

# 8. Outside an app root nothing is created.
new_case
rm -rf "${APP}/vendor"
run_case 1.0.0
check "no mirror outside an app root" "$(yes [ ! -e "${APP}/${MIRROR_REL}" ])"

# 9. The rendered wrapper as a whole still parses.
RC=0; AFTER=""
render '/^    (bin\/"wheels").write <<~EOS$/' '/^    EOS$/' '1d;$d' > "${TMP}/wrapper.sh"
ERR="$("${BASH_BIN}" -n "${TMP}/wrapper.sh" 2>&1)" || RC=$?
check "rendered wrapper passes bash -n" "$(is "${RC}" "0")"
check "rendered wrapper starts with its shebang" "$(is "$(head -1 "${TMP}/wrapper.sh")" "#!/bin/bash")"

exit $fail
