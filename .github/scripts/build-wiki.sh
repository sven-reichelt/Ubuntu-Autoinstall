#!/usr/bin/env bash
# =============================================================================
# build-wiki.sh
# -----------------------------------------------------------------------------
# Renders docs/ into a set of GitHub wiki pages.
#
# docs/ is the single source of truth; the wiki is only a mirror. This script
# does the three things that differ between the two:
#
#   1. docs/README.md becomes the wiki landing page 'Home.md'. Every other
#      docs/<Name>.md keeps its name - wiki page names are the file names.
#   2. Links between pages lose their '.md' suffix, because the wiki resolves
#      '[Scripts](Scripts)' but not '[Scripts](Scripts.md)'. A link to
#      README.md becomes a link to Home.
#   3. Links that point out of docs/ ('../autoinstall/user-data') become
#      absolute URLs into the repository - relative paths have no meaning in
#      the wiki, which lives in a separate repository.
#
# It also generates the navigation chrome (_Sidebar.md, _Footer.md) from the
# fixed page order below.
#
# USAGE:
#   .github/scripts/build-wiki.sh <output-directory>
#
# The output directory is created if needed and emptied of *.md first, so the
# result is exactly the set of pages the wiki should contain.
# =============================================================================
set -euo pipefail

REPO_OWNER="sven-reichelt"
REPO_NAME="Ubuntu-Autoinstall"
REPO_BRANCH="main"
BLOB_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/${REPO_BRANCH}"

# Page order for the sidebar. Every file in docs/ must appear here (README.md
# is the Home page and is handled separately), otherwise the script fails -
# that way a new page cannot silently be missing from the navigation.
PAGE_ORDER=(
  "Installation"
  "Scripts"
  "Configuration"
  "Troubleshooting"
  "Development"
)

# --- Arguments --------------------------------------------------------------
OUT_DIR="${1:-}"
if [[ -z "$OUT_DIR" ]]; then
  echo "Usage: $0 <output-directory>" >&2
  exit 1
fi

# Resolve the repository root from the location of this script, so the script
# works no matter where it is called from.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

[[ -d "$DOCS_DIR" ]] || { echo "ERROR: $DOCS_DIR does not exist." >&2; exit 1; }
[[ -f "$DOCS_DIR/README.md" ]] || { echo "ERROR: docs/README.md is missing." >&2; exit 1; }

# --- Check that docs/ and PAGE_ORDER agree ----------------------------------
# Both directions, like the script manifest: a listed page must exist, and an
# existing page must be listed.
fail=0
for page in "${PAGE_ORDER[@]}"; do
  if [[ ! -f "$DOCS_DIR/$page.md" ]]; then
    echo "ERROR: PAGE_ORDER lists '$page' but docs/$page.md does not exist." >&2
    fail=1
  fi
done

shopt -s nullglob
for f in "$DOCS_DIR"/*.md; do
  base="$(basename "$f" .md)"
  [[ "$base" == "README" ]] && continue
  found=0
  for page in "${PAGE_ORDER[@]}"; do
    [[ "$page" == "$base" ]] && found=1 && break
  done
  if [[ "$found" -eq 0 ]]; then
    echo "ERROR: docs/$base.md exists but is not in PAGE_ORDER in $0." >&2
    fail=1
  fi
done
shopt -u nullglob

[[ "$fail" -eq 0 ]] || exit 1

# --- Prepare the output directory -------------------------------------------
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.md

# Rewrites the links of one page. Reads from $1, writes to $2.
render_page() {
  local src="$1" dest="$2"
  BLOB_BASE="$BLOB_BASE" perl -pe '
    # 1. Links out of docs/ -> absolute repository URLs.
    #    ](../autoinstall/user-data)  ->  ](https://github.com/.../autoinstall/user-data)
    s{\]\(\.\./}{"](" . $ENV{BLOB_BASE} . "/"}ge;

    # 2. Links to sibling pages -> wiki page names without the .md suffix.
    #    ](Scripts.md#anchor)  ->  ](Scripts#anchor)
    #    ](README.md)          ->  ](Home)
    #    Absolute URLs are left alone.
    s{
      \]\(                          # opening of the link target
      (?!https?://)                 # not an absolute URL
      (?:\./)?                      # optional leading ./
      ([A-Za-z0-9._-]+)\.md         # the page file name
      (\#[^)]*)?                    # optional anchor
      \)
    }{"](" . ($1 eq "README" ? "Home" : $1) . ($2 // "") . ")"}gex;
  ' < "$src" > "$dest"
}

echo "Rendering docs/ -> $OUT_DIR"

render_page "$DOCS_DIR/README.md" "$OUT_DIR/Home.md"
echo "  docs/README.md      -> Home.md"

for page in "${PAGE_ORDER[@]}"; do
  render_page "$DOCS_DIR/$page.md" "$OUT_DIR/$page.md"
  echo "  docs/$page.md -> $page.md"
done

# --- Navigation chrome ------------------------------------------------------
{
  echo "### Ubuntu-Autoinstall"
  echo
  echo "* [[Home]]"
  for page in "${PAGE_ORDER[@]}"; do
    # Wiki page names use hyphens where the title has spaces; ours have none,
    # so the file name doubles as the link target and the label.
    echo "* [[$page]]"
  done
  echo
  echo "---"
  echo
  echo "* [Repository]($BLOB_BASE/README.md)"
  echo "* [Releases](https://github.com/$REPO_OWNER/$REPO_NAME/releases)"
  echo "* [Changelog]($BLOB_BASE/CHANGELOG.md)"
  echo "* [Security]($BLOB_BASE/SECURITY.md)"
} > "$OUT_DIR/_Sidebar.md"
echo "  generated           -> _Sidebar.md"

{
  echo "Generated from [\`docs/\`](https://github.com/$REPO_OWNER/$REPO_NAME/tree/$REPO_BRANCH/docs)"
  echo "in the repository - edit the files there, not the wiki."
} > "$OUT_DIR/_Footer.md"
echo "  generated           -> _Footer.md"

echo
echo "Done: $(find "$OUT_DIR" -maxdepth 1 -name '*.md' | wc -l) pages in $OUT_DIR"
