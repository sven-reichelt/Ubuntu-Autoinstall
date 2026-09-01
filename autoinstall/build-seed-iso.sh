#!/usr/bin/env bash
# =============================================================================
# build-seed-iso.sh
# Builds the "cidata" seed ISO for the unattended Ubuntu installation.
# The ISO contains user-data, meta-data and the script loader get-scripts.sh.
# In the VM it is attached as a SECOND CD drive next to the Ubuntu ISO.
#
# Usage:   ./build-seed-iso.sh
# Result:  seed.iso  (in this directory)
#
# Requirements (one of these):
#   Linux : xorriso  OR  genisoimage  OR  mkisofs
#           (Ubuntu/Debian:  sudo apt-get install -y xorriso)
#   macOS : hdiutil (preinstalled)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

USER_DATA="user-data"
META_DATA="meta-data"
LOADER="../scripts/get-scripts.sh"
OUT="seed.iso"
LABEL="CIDATA"     # this volume label is mandatory (NoCloud datasource)

# --- Preflight checks -------------------------------------------------------
[[ -f "$USER_DATA" ]] || { echo "ERROR: $USER_DATA is missing."; exit 1; }
[[ -f "$META_DATA" ]] || { echo "ERROR: $META_DATA is missing."; exit 1; }
[[ -f "$LOADER"    ]] || { echo "ERROR: $LOADER is missing."; exit 1; }

# Assemble a work directory holding the seed files
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$USER_DATA" "$WORK/user-data"
cp "$META_DATA" "$WORK/meta-data"

# The loader is copied into the user's home by a late-command, so it is ready
# right after the first reboot. It is the only script on the seed ISO - all
# other scripts are fetched from GitHub on demand.
cp "$LOADER" "$WORK/get-scripts.sh"
echo "Info: get-scripts.sh is placed on the seed ISO."

echo "Building $OUT (label $LABEL) ..."

# --- Create the ISO (use whichever tool is available) -----------------------
if command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -output "$OUT" -volid "$LABEL" -joliet -rock "$WORK"
elif command -v genisoimage >/dev/null 2>&1; then
  genisoimage -output "$OUT" -volid "$LABEL" -joliet -rock "$WORK"
elif command -v mkisofs >/dev/null 2>&1; then
  mkisofs -output "$OUT" -volid "$LABEL" -joliet -rock "$WORK"
elif command -v hdiutil >/dev/null 2>&1; then
  # macOS
  hdiutil makehybrid -o "${OUT%.iso}" -hfs -joliet -iso -default-volume-name "$LABEL" "$WORK"
  [[ -f "${OUT%.iso}.iso" ]] && mv "${OUT%.iso}.iso" "$OUT"
else
  echo "ERROR: No ISO tool found."
  echo "  Linux:  sudo apt-get install -y xorriso"
  echo "  macOS:  hdiutil is preinstalled"
  exit 1
fi

echo
echo "Done:  $(pwd)/$OUT"
echo "Upload this file to the ESXi datastore / Hyper-V host and attach it as"
echo "the second CD drive."
echo
echo "Note: user 'ubuntu-admin' / password 'ubuntu' (for the first login only)."
echo "After the installation run 'sudo ~/get-scripts.sh change-password.sh'."
