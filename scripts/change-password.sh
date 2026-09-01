#!/usr/bin/env bash
# =============================================================================
# change-password.sh
# -----------------------------------------------------------------------------
# Changes the password of a local user account (default: the user that invoked
# sudo, i.e. normally 'ubuntu-admin').
#
# Two ways to enter the new password:
#   1) Normal, hidden entry via 'passwd' (default, recommended).
#   2) Plain-text entry - for the case where the keyboard layout causes
#      trouble (e.g. special characters on a different layout) and you want to
#      see what was actually typed.
#
# USAGE:
#   sudo ./change-password.sh              change the password of the calling
#                                          (sudo) user
#   sudo ./change-password.sh <username>   change a different account
# =============================================================================
set -euo pipefail

# --- Must run as root -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please start with sudo:  sudo $0 ${*:-}"
  exit 1
fi

TARGET_USER="${1:-${SUDO_USER:-$(logname 2>/dev/null || echo root)}}"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "ERROR: user '$TARGET_USER' does not exist."
  exit 1
fi

echo "==> Change password for user: $TARGET_USER"
echo

echo "How do you want to enter the new password?"
echo "  1) Normal, hidden entry (default, recommended)"
echo "  2) Plain text (if the keyboard layout causes trouble or you are"
echo "     unsure about special characters)"
read -r -p "Selection [1/2, Enter = 1]: " MODE
MODE="${MODE:-1}"

case "$MODE" in
  2)
    # --- Plain-text entry ---------------------------------------------------
    NEW_PW=""
    while true; do
      read -r -p "New password (plain text): " NEW_PW
      read -r -p "Repeat new password (plain text): " NEW_PW_CONFIRM
      if [[ -z "$NEW_PW" ]]; then
        echo "The password must not be empty. Please try again."
        echo
        continue
      fi
      if [[ "$NEW_PW" != "$NEW_PW_CONFIRM" ]]; then
        echo "The two entries do not match. Please try again."
        echo
        continue
      fi
      break
    done
    echo "$TARGET_USER:$NEW_PW" | chpasswd
    echo
    echo "============================================================"
    echo " Password changed successfully."
    echo " User:       $TARGET_USER"
    echo " Password:   $NEW_PW"
    echo "============================================================"
    ;;
  *)
    # --- Normal, hidden entry (the standard 'passwd' way) -------------------
    passwd "$TARGET_USER"
    echo
    echo "============================================================"
    echo " Password for user '$TARGET_USER' changed successfully."
    echo "============================================================"
    ;;
esac
