#!/usr/bin/env bash
# =============================================================================
# get-scripts.sh
# -----------------------------------------------------------------------------
# Script loader for Ubuntu-Autoinstall.
#
# This is the ONLY script that is placed on the system during the unattended
# installation (it is copied from the seed ISO into the home directory of the
# user). Everything else is downloaded from GitHub on demand, so new scripts
# become available without rebuilding the seed ISO.
#
# USAGE:
#   sudo ./get-scripts.sh                       interactive menu (default)
#   sudo ./get-scripts.sh --list                list available scripts and exit
#   sudo ./get-scripts.sh --all                 download every script, no prompts
#   sudo ./get-scripts.sh <script.sh> [args]    download one script and run it
#   sudo ./get-scripts.sh -d <script.sh>        download one script, do not run
#   sudo ./get-scripts.sh --self-update         update this loader itself
#   ./get-scripts.sh --help                     show this help
#
# Downloaded scripts are stored in ~/scripts (of the invoking user) and made
# executable. Re-running the loader always fetches the current version.
#
# The list of available scripts comes from scripts/manifest.txt in the
# repository. If that file cannot be reached, the loader falls back to the
# GitHub API and lists the *.sh files in the scripts/ directory directly.
# =============================================================================
set -euo pipefail

# --- Configuration ----------------------------------------------------------
REPO_OWNER="sven-reichelt"
REPO_NAME="Ubuntu-Autoinstall"
REPO_BRANCH="main"
REPO_PATH="scripts"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${REPO_PATH}"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${REPO_PATH}?ref=${REPO_BRANCH}"
PROJECT_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"

SELF_NAME="get-scripts.sh"          # never offered as a downloadable script
MANIFEST_NAME="manifest.txt"

# Where the downloaded scripts end up. When started via sudo this must be the
# home of the ORIGINAL user, not /root - otherwise the files land somewhere the
# user does not expect.
INVOKING_USER="${SUDO_USER:-$(id -un)}"
INVOKING_HOME="$(getent passwd "$INVOKING_USER" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "$INVOKING_HOME" ]] || INVOKING_HOME="$HOME"
TARGET_DIR="$INVOKING_HOME/scripts"

# --- Parallel arrays holding the manifest -----------------------------------
SCRIPT_NAMES=()
SCRIPT_DESCS=()

# --- Helpers ----------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '/^# USAGE:/,/^# =====/p' "$0" | sed 's/^#\{1,\} \{0,1\}//' | sed '$d'
}

need_curl() {
  command -v curl >/dev/null 2>&1 \
    || die "curl is not installed. Run: sudo apt-get install -y curl"
}

# Fetch a URL to stdout. Returns non-zero on any HTTP error (curl -f).
fetch() {
  curl -fsSL --retry 3 --connect-timeout 10 "$1"
}

# Reads scripts/manifest.txt. Format (one script per line):
#   name.sh|short description
# Lines starting with a hash and empty lines are ignored.
load_manifest_from_repo() {
  local raw line name desc
  raw="$(fetch "${RAW_BASE}/${MANIFEST_NAME}" 2>/dev/null)" || return 1
  [[ -n "$raw" ]] || return 1

  while IFS= read -r line; do
    line="${line%$'\r'}"                       # tolerate CRLF
    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *"|"* ]] || continue
    name="${line%%|*}"
    desc="${line#*|}"
    name="$(printf '%s' "$name" | tr -d '[:space:]')"
    desc="$(printf '%s' "$desc" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$name" ]] || continue
    [[ "$name" == "$SELF_NAME" ]] && continue
    [[ "$name" == *.sh ]] || continue
    SCRIPT_NAMES+=("$name")
    SCRIPT_DESCS+=("${desc:-no description}")
  done <<< "$raw"

  [[ ${#SCRIPT_NAMES[@]} -gt 0 ]]
}

# Fallback: ask the GitHub API which *.sh files live in scripts/. Used when the
# manifest is missing or unreachable. Parsed with grep/sed so that no jq is
# required on a freshly installed minimal system.
load_manifest_from_api() {
  local raw name
  raw="$(fetch "$API_URL" 2>/dev/null)" || return 1
  [[ -n "$raw" ]] || return 1

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" == "$SELF_NAME" ]] && continue
    SCRIPT_NAMES+=("$name")
    SCRIPT_DESCS+=("no description (manifest unavailable)")
  done < <(printf '%s' "$raw" \
             | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*\.sh"' \
             | sed 's/.*"\([^"]*\.sh\)"/\1/')

  [[ ${#SCRIPT_NAMES[@]} -gt 0 ]]
}

load_manifest() {
  SCRIPT_NAMES=()
  SCRIPT_DESCS=()
  if load_manifest_from_repo; then
    return 0
  fi
  echo "Note: manifest could not be read - falling back to the GitHub API." >&2
  SCRIPT_NAMES=()
  SCRIPT_DESCS=()
  if load_manifest_from_api; then
    return 0
  fi
  die "Could not reach GitHub. Check network connection and DNS, then retry. Project: $PROJECT_URL"
}

# Prints the description of a script name, empty string when unknown.
describe() {
  local wanted="$1" i
  for i in "${!SCRIPT_NAMES[@]}"; do
    if [[ "${SCRIPT_NAMES[$i]}" == "$wanted" ]]; then
      printf '%s\n' "${SCRIPT_DESCS[$i]}"
      return 0
    fi
  done
  printf '\n'
}

# Returns 0 when the given name is part of the manifest.
is_known() {
  local wanted="$1" n
  for n in "${SCRIPT_NAMES[@]}"; do
    [[ "$n" == "$wanted" ]] && return 0
  done
  return 1
}

# Downloads one script into TARGET_DIR, verifies it looks like a shell script
# and makes it executable. Prints the resulting path on stdout.
download_one() {
  local name="$1" dest tmp group
  dest="$TARGET_DIR/$name"
  tmp="$(mktemp)"

  if ! fetch "${RAW_BASE}/${name}" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "Download of '$name' failed (not found or no network): ${RAW_BASE}/${name}"
  fi

  # Sanity checks: an error page or an empty file would silently "succeed".
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    die "Downloaded file '$name' is empty."
  fi
  if ! head -n1 "$tmp" | grep -q '^#!'; then
    rm -f "$tmp"
    die "Downloaded file '$name' is not a shell script."
  fi

  mkdir -p "$TARGET_DIR"
  mv "$tmp" "$dest"
  chmod +x "$dest"

  # Files must belong to the user, not to root, when started via sudo.
  group="$(id -gn "$INVOKING_USER" 2>/dev/null || printf '%s' "$INVOKING_USER")"
  chown "$INVOKING_USER:$group" "$dest" 2>/dev/null || true
  chown "$INVOKING_USER:$group" "$TARGET_DIR" 2>/dev/null || true

  printf '%s\n' "$dest"
}

# Runs a downloaded script. Elevates via sudo when the loader itself was not
# started as root - all shipped scripts need root privileges.
run_script() {
  local path="$1"
  shift
  echo
  echo "==> Running $(basename "$path") ..."
  echo
  if [[ $EUID -eq 0 ]]; then
    "$path" "$@"
  else
    sudo "$path" "$@"
  fi
}

print_list() {
  local i
  echo
  echo "Available scripts ($PROJECT_URL):"
  echo
  for i in "${!SCRIPT_NAMES[@]}"; do
    printf '  %2d) %-28s %s\n' "$((i + 1))" "${SCRIPT_NAMES[$i]}" "${SCRIPT_DESCS[$i]}"
  done
  echo
}

interactive_menu() {
  local choice reply name path i
  while true; do
    print_list
    echo "   a) download all      r) refresh list      q) quit"
    echo
    read -r -p "Selection: " choice

    if [[ -z "$choice" || "$choice" == "q" || "$choice" == "Q" ]]; then
      echo "Nothing to do."
      return 0
    fi

    case "$choice" in
      r|R)
        load_manifest
        continue
        ;;
      a|A)
        for i in "${!SCRIPT_NAMES[@]}"; do
          download_one "${SCRIPT_NAMES[$i]}" >/dev/null
          echo "  OK  ${SCRIPT_NAMES[$i]}"
        done
        echo
        echo "All scripts are in $TARGET_DIR."
        return 0
        ;;
    esac

    if [[ "$choice" =~ ^[0-9]+$ ]] \
       && (( choice >= 1 )) && (( choice <= ${#SCRIPT_NAMES[@]} )); then
      name="${SCRIPT_NAMES[$((choice - 1))]}"
      echo
      echo "-> downloading $name ..."
      path="$(download_one "$name")"
      echo "   saved to $path"
      read -r -p "Run it now? [Y/n]: " reply
      case "$reply" in
        n|N|no|NO) echo "Not started. Run it later with:  sudo $path" ;;
        *)         run_script "$path" ;;
      esac
      return 0
    fi

    echo "Invalid selection - enter a number, 'a', 'r' or 'q'."
  done
}

self_update() {
  local tmp
  tmp="$(mktemp)"
  if ! fetch "${RAW_BASE}/${SELF_NAME}" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "Self-update failed - could not download ${SELF_NAME}."
  fi
  if ! head -n1 "$tmp" | grep -q '^#!'; then
    rm -f "$tmp"
    die "Self-update failed - downloaded file is not a shell script."
  fi
  if cmp -s "$tmp" "$0"; then
    rm -f "$tmp"
    echo "Already up to date: $0"
    return 0
  fi
  cat "$tmp" > "$0"        # keeps owner and permissions of the existing file
  rm -f "$tmp"
  chmod +x "$0"
  echo "Updated: $0"
}

# --- Argument handling ------------------------------------------------------
need_curl

DOWNLOAD_ONLY=0
ACTION="menu"
TARGET_SCRIPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)          usage; exit 0 ;;
    -l|--list)          ACTION="list"; shift ;;
    -a|--all)           ACTION="all"; shift ;;
    -d|--download-only) DOWNLOAD_ONLY=1; shift ;;
    --self-update)      ACTION="self-update"; shift ;;
    --)                 shift ;;
    -*)                 die "Unknown option: $1  (see --help)" ;;
    *)                  TARGET_SCRIPT="$1"; ACTION="one"; shift; break ;;
  esac
done

case "$ACTION" in
  self-update)
    self_update
    ;;

  list)
    load_manifest
    print_list
    echo "Download and run with:  sudo $0 <script.sh>"
    echo
    ;;

  all)
    load_manifest
    echo "Downloading ${#SCRIPT_NAMES[@]} scripts to $TARGET_DIR ..."
    for name in "${SCRIPT_NAMES[@]}"; do
      download_one "$name" >/dev/null
      echo "  OK  $name"
    done
    echo
    echo "Done. Run for example:  sudo $TARGET_DIR/change-password.sh"
    ;;

  one)
    # Accept the name with or without the .sh suffix.
    [[ "$TARGET_SCRIPT" == *.sh ]] || TARGET_SCRIPT="${TARGET_SCRIPT}.sh"
    load_manifest
    if ! is_known "$TARGET_SCRIPT"; then
      echo "'$TARGET_SCRIPT' is not in the list of available scripts." >&2
      print_list >&2
      exit 1
    fi
    echo "-> downloading $TARGET_SCRIPT ..."
    SCRIPT_PATH="$(download_one "$TARGET_SCRIPT")"
    echo "   saved to $SCRIPT_PATH"
    DESC="$(describe "$TARGET_SCRIPT")"
    [[ -n "$DESC" ]] && echo "   $DESC"
    if [[ "$DOWNLOAD_ONLY" -eq 1 ]]; then
      echo
      echo "Run it with:  sudo $SCRIPT_PATH"
    else
      run_script "$SCRIPT_PATH" "$@"
    fi
    ;;

  menu)
    load_manifest
    echo
    echo "== Ubuntu-Autoinstall - script loader =="
    echo "   target directory: $TARGET_DIR"
    interactive_menu
    ;;
esac
