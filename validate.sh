#!/usr/bin/env bash
# =============================================================================
# validate.sh
# Local and CI checks for this repository. Reports every problem and exits
# non-zero if any check failed.
#   - Bash syntax check of every *.sh
#   - ShellCheck (if installed)
#   - YAML validation of autoinstall/user-data + mandatory fields
#   - Consistency between scripts/manifest.txt and scripts/*.sh
# Usage:  ./validate.sh
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")" || exit 1

fail=0
note() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# --- 1. Bash syntax ---------------------------------------------------------
note "Bash syntax check (bash -n)"
while IFS= read -r -d '' f; do
  if bash -n "$f"; then
    echo "  OK   $f"
  else
    echo "  FAIL $f"; fail=1
  fi
done < <(find . -type f -name '*.sh' -not -path './.git/*' -print0)

# --- 2. ShellCheck (optional) ----------------------------------------------
note "ShellCheck"
if command -v shellcheck >/dev/null 2>&1; then
  # SC1091: external sources cannot be resolved -> tolerated
  find . -type f -name '*.sh' -not -path './.git/*' -print0 \
    | xargs -0 shellcheck -e SC1091 || fail=1
  echo "  ShellCheck finished"
else
  echo "  shellcheck is not installed - skipped"
fi

# --- 3. Autoinstall YAML ----------------------------------------------------
note "Validating autoinstall/user-data"

# Primary path: Python with PyYAML (this is how the CI runs it too).
validate_with_python() {
  "$1" - <<'PY'
import sys, yaml
try:
    doc = yaml.safe_load(open('autoinstall/user-data'))
except Exception as e:
    print("  FAIL: YAML is not parseable:", e); sys.exit(1)
ai = doc.get('autoinstall')
if not isinstance(ai, dict):
    print("  FAIL: 'autoinstall' is missing or is not a mapping"); sys.exit(1)
required = ['version','locale','keyboard','identity','ssh','network','storage','packages']
missing = [k for k in required if k not in ai]
if missing:
    print("  FAIL: mandatory fields are missing:", missing); sys.exit(1)
pw = ai['identity'].get('password','')
if not str(pw).startswith('$6$'):
    print("  FAIL: identity.password is not a SHA-512 hash ($6$...)"); sys.exit(1)

# The user name appears in identity.username AND in the late-commands. Both
# must match, otherwise the loader is copied to a home that does not exist.
user = ai['identity'].get('username')
raw = open('autoinstall/user-data', encoding='utf-8').read()
if 'TARGET_USER="%s"' % user not in raw:
    print("  FAIL: TARGET_USER in late-commands does not match identity.username"
          " (%s)" % user); sys.exit(1)
print("  OK: user-data is valid (user:", user, ")")

# meta-data must be valid YAML as well
yaml.safe_load(open('autoinstall/meta-data'))
print("  OK: meta-data is valid YAML")
PY
}

# Fallback without Python (e.g. Windows/Git Bash): npx fetches the YAML parser,
# converts to JSON, and Node does the mandatory-field check itself.
validate_with_node() {
  local tmp rc=0
  tmp="$(mktemp)"
  # --strict is mandatory: without it the parser only reports errors on stderr
  # and still exits with 0.
  if ! npx --yes yaml@2 --json --strict --single < autoinstall/user-data > "$tmp"; then
    echo "  FAIL: user-data is not valid YAML"; rm -f "$tmp"; return 1
  fi
  UD_JSON="$tmp" node - <<'JS' || rc=1
const fs = require('fs');
const raw = fs.readFileSync(process.env.UD_JSON, 'utf8');
// Strip a leading BOM (U+FEFF), otherwise JSON.parse chokes on it.
const doc = JSON.parse(raw.charCodeAt(0) === 0xFEFF ? raw.slice(1) : raw);
const bail = (m) => { console.log('  FAIL: ' + m); process.exit(1); };
const ai = doc && doc.autoinstall;
if (!ai || typeof ai !== 'object' || Array.isArray(ai)) {
  bail("'autoinstall' is missing or is not a mapping");
}
const required = ['version','locale','keyboard','identity','ssh','network','storage','packages'];
const missing = required.filter((k) => !(k in ai));
if (missing.length) bail('mandatory fields are missing: ' + missing.join(', '));
const id = ai.identity || {};
if (!String(id.password || '').startsWith('$6$')) {
  bail('identity.password is not a SHA-512 hash ($6$...)');
}
const src = fs.readFileSync('autoinstall/user-data', 'utf8');
if (!src.includes('TARGET_USER="' + id.username + '"')) {
  bail('TARGET_USER in late-commands does not match identity.username (' + id.username + ')');
}
console.log('  OK: user-data is valid (user: ' + id.username + ' )');
JS
  rm -f "$tmp"
  if ! npx --yes yaml@2 valid --strict --single < autoinstall/meta-data; then
    echo "  FAIL: meta-data is not valid YAML"; return 1
  fi
  echo "  OK: meta-data is valid YAML"
  return "$rc"
}

py_bin=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import yaml' >/dev/null 2>&1; then
    py_bin="$c"; break
  fi
done

if [[ -n "$py_bin" ]]; then
  validate_with_python "$py_bin" || fail=1
elif command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  echo "  Python with PyYAML is unavailable - using Node (npx yaml)"
  validate_with_node || fail=1
else
  echo "  WARN: neither Python+PyYAML nor Node/npx present - check skipped"
  echo "        (the CI runs it with PyYAML; locally: pip install pyyaml)"
fi

# --- 4. Manifest consistency ------------------------------------------------
# Every entry in scripts/manifest.txt must have a matching file, and every
# script in scripts/ (except the loader itself) must be listed in the manifest.
# Otherwise get-scripts.sh would offer downloads that fail, or silently hide
# scripts that exist in the repository.
note "Checking scripts/manifest.txt"

MANIFEST="scripts/manifest.txt"
LOADER="get-scripts.sh"

if [[ ! -f "$MANIFEST" ]]; then
  echo "  FAIL: $MANIFEST is missing"; fail=1
else
  listed=()
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue
    if [[ "$line" != *"|"* ]]; then
      echo "  FAIL: line without a '|' separator: $line"; fail=1; continue
    fi
    name="${line%%|*}"
    desc="${line#*|}"
    name="$(printf '%s' "$name" | tr -d '[:space:]')"
    desc="$(printf '%s' "$desc" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ "$name" != *.sh ]]; then
      echo "  FAIL: '$name' does not end in .sh"; fail=1; continue
    fi
    if [[ "$name" == "$LOADER" ]]; then
      echo "  FAIL: the loader '$LOADER' must not be listed in the manifest"; fail=1; continue
    fi
    if [[ -z "$desc" ]]; then
      echo "  FAIL: '$name' has no description"; fail=1; continue
    fi
    if [[ ! -f "scripts/$name" ]]; then
      echo "  FAIL: '$name' is listed but scripts/$name does not exist"; fail=1; continue
    fi
    listed+=("$name")
    echo "  OK   $name"
  done < "$MANIFEST"

  # The other way round: scripts present but not listed
  shopt -s nullglob
  for f in scripts/*.sh; do
    base="$(basename "$f")"
    [[ "$base" == "$LOADER" ]] && continue
    found=0
    for n in "${listed[@]:-}"; do
      [[ "$n" == "$base" ]] && found=1 && break
    done
    if [[ "$found" -eq 0 ]]; then
      echo "  FAIL: scripts/$base exists but is not listed in $MANIFEST"; fail=1
    fi
  done
  shopt -u nullglob

  # The loader must exist - the seed ISO build depends on it
  if [[ ! -f "scripts/$LOADER" ]]; then
    echo "  FAIL: scripts/$LOADER is missing"; fail=1
  fi
fi

# --- 5. Documentation -------------------------------------------------------
# The wiki is generated from docs/, so a broken relative link or a page that
# build-wiki.sh does not know about would only surface after the push. Catch
# both here.
note "Checking the documentation"

# 5a. Rendering the wiki also verifies that docs/ and the page order in
#     build-wiki.sh agree in both directions.
BUILD_WIKI=".github/scripts/build-wiki.sh"
if [[ ! -f "$BUILD_WIKI" ]]; then
  echo "  FAIL: $BUILD_WIKI is missing"; fail=1
else
  wiki_tmp="$(mktemp -d)"
  if bash "$BUILD_WIKI" "$wiki_tmp" >/dev/null; then
    echo "  OK   wiki pages render ($(find "$wiki_tmp" -maxdepth 1 -name '*.md' | wc -l) pages)"
  else
    echo "  FAIL: $BUILD_WIKI reported a problem (run it directly to see it)"; fail=1
  fi
  rm -rf "$wiki_tmp"
fi

# 5b. Every relative link in README.md and docs/*.md must resolve to a file
#     that exists. External links (http/https/mailto) and pure anchors are
#     skipped - only local targets can be checked here.
check_links() {
  local file="$1" dir target resolved
  dir="$(dirname "$file")"
  while IFS= read -r target; do
    # Strip an anchor and any link title
    target="${target%%#*}"
    target="${target%% *}"
    [[ -z "$target" ]] && continue
    case "$target" in
      http://*|https://*|mailto:*|\<*) continue ;;
    esac
    resolved="$dir/$target"
    if [[ ! -e "$resolved" ]]; then
      echo "  FAIL: $file links to '$target', which does not exist"
      return 1
    fi
  done < <(grep -o '](\([^)]*\))' "$file" | sed 's/^](//; s/)$//')
  return 0
}

link_fail=0
shopt -s nullglob
for f in README.md SECURITY.md CHANGELOG.md docs/*.md; do
  [[ -f "$f" ]] || continue
  if check_links "$f"; then
    echo "  OK   links in $f"
  else
    link_fail=1
  fi
done
shopt -u nullglob
[[ "$link_fail" -eq 0 ]] || fail=1

# --- Result -----------------------------------------------------------------
echo
if [[ "$fail" -ne 0 ]]; then
  echo "VALIDATION FAILED"; exit 1
fi
echo "ALL CHECKS PASSED"
