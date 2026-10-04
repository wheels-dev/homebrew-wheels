#!/usr/bin/env bash
# Exercises the version-gated module/framework sync in the `wheels` wrapper
# that Formula/wheels.rb and Formula/wheels-be.rb write at install time.
#
# The sync used to `cp -R` the new module over ~/.wheels/modules/wheels, so a
# file an older version shipped and a newer one dropped stayed there forever,
# and `wheels new` copied it into every new app: an old generator template in
# templates/app/app/snippets/ overrode the current one, and old framework
# files landed in vendor/wheels/.
#
# The wrapper's variable block and its sync block are rendered the way Homebrew
# renders them (a Ruby <<~EOS heredoc), with opt_prefix pointing at a fake
# package and HOME at a temp dir, so nothing touches the real ~/.wheels. The
# rendered text runs under `bash -euo pipefail` against an "installed" 1.0
# copy, then the test checks what a 2.0 upgrade left behind.
#
# Needs only bash and ruby. FORMULAS overrides the formulae under test;
# BASH_BIN the shell the blocks run under (macOS runs the wrapper with
# /bin/bash 3.2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FORMULAS="${FORMULAS:-Formula/wheels.rb Formula/wheels-be.rb}"
BASH_BIN="${BASH_BIN:-$(command -v bash)}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# render <formula> <out>: the wrapper's variable lines (BREW_PREFIX through
# WHEELS_VERSION_DST) plus the `if [ -f "$WHEELS_VERSION_SRC" ]` sync block,
# as the Ruby heredoc produces them. eval only ever sees this repo's own
# formula text.
render() {
  awk '
    /BREW_PREFIX="#\{opt_prefix\}"/ { vars = 1 }
    vars { print; if ($0 ~ /WHEELS_VERSION_DST=/) vars = 0; next }
    /if \[ -f "\$WHEELS_VERSION_SRC" \]; then/ { sync = 1; match($0, /^ */); indent = RLENGTH }
    sync { print; match($0, /^ */); if (RLENGTH == indent && $0 ~ /^ *fi$/) sync = 0 }
  ' "$1" > "${TMP}/raw.txt"
  ruby -e '
    MODULE_VERSION = "0.0.0-test"
    SQLITE_JDBC_VERSION = "0.0.0-test"
    opt_prefix = ARGV[1]
    body = File.read(ARGV[0])
    puts eval("<<~EOS\n#{body}EOS\n")
  ' "${TMP}/raw.txt" "$3" > "$2"
}

for formula in ${FORMULAS}; do
  name="$(basename "${formula}")"
  case_dir="${TMP}/${name}"
  prefix="${case_dir}/prefix"
  home="${case_dir}/home"
  installed="${home}/.wheels/modules/wheels"

  # The new package (2.0): no snippets templates, model mixins as .cfm.
  mkdir -p "${prefix}/share/wheels/module/templates/app/app/snippets" \
           "${prefix}/share/wheels/framework/wheels/model"
  echo "readme" > "${prefix}/share/wheels/module/templates/app/app/snippets/README.md"
  echo "new" > "${prefix}/share/wheels/framework/wheels/model/associations.cfm"
  echo "2.0" > "${prefix}/share/wheels/.module-version"

  # What 1.0 left in ~/.wheels.
  mkdir -p "${installed}/templates/app/app/snippets" "${installed}/vendor/wheels/model"
  echo "old" > "${installed}/templates/app/app/snippets/ApiControllerContent.txt"
  echo "old" > "${installed}/vendor/wheels/model/associations.cfc"
  echo "1.0" > "${installed}/.module-version"

  render "${formula}" "${case_dir}/sync.sh" "${prefix}"
  if ! grep -q 'cp -R "\$WHEELS_MODULE_SRC/"' "${case_dir}/sync.sh"; then
    fail "${name}: could not find the module sync block"
    continue
  fi

  if ! HOME="${home}" "${BASH_BIN}" -euo pipefail "${case_dir}/sync.sh" > "${case_dir}/out.txt" 2>&1; then
    fail "${name}: the sync block exited non-zero: $(cat "${case_dir}/out.txt")"
    continue
  fi

  [ ! -e "${installed}/templates/app/app/snippets/ApiControllerContent.txt" ] \
    && pass "${name}: a module file the new version dropped is removed" \
    || fail "${name}: a module file the new version dropped is still installed"
  [ ! -e "${installed}/vendor/wheels/model/associations.cfc" ] \
    && pass "${name}: a framework file the new version dropped is removed" \
    || fail "${name}: a framework file the new version dropped is still installed"
  [ -f "${installed}/templates/app/app/snippets/README.md" ] \
    && pass "${name}: the new module files are installed" \
    || fail "${name}: the new module files are missing"
  [ -f "${installed}/vendor/wheels/model/associations.cfm" ] \
    && pass "${name}: the new framework files are installed" \
    || fail "${name}: the new framework files are missing"
  [ "$(cat "${installed}/.module-version" 2>/dev/null)" = "2.0" ] \
    && pass "${name}: the installed version is recorded" \
    || fail "${name}: the installed version is not recorded"

  # Same version again: nothing is replaced (the sync is version-gated).
  echo "kept" > "${installed}/marker.txt"
  HOME="${home}" "${BASH_BIN}" -euo pipefail "${case_dir}/sync.sh" > /dev/null 2>&1
  [ -f "${installed}/marker.txt" ] \
    && pass "${name}: an unchanged version leaves the installed copy alone" \
    || fail "${name}: an unchanged version replaced the installed copy"
done

echo
if [ "${failures}" -gt 0 ]; then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "all checks passed"
