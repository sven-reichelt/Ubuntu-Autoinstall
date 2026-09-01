#!/usr/bin/env bash
# =============================================================================
# system-update.sh
# -----------------------------------------------------------------------------
# Updates all packages of the system:
#   apt-get update -> full-upgrade -> autoremove -> autoclean
# and afterwards reports whether a reboot is required.
#
# USAGE:
#   sudo ./system-update.sh            ask before rebooting (if required)
#   sudo ./system-update.sh --reboot   reboot automatically when required
#   sudo ./system-update.sh --no-reboot  never reboot, only report
#
# LOG: the complete output is appended to /var/log/system-update.log
# (nothing is overwritten) - useful for troubleshooting after the fact.
# =============================================================================
set -euo pipefail

# --- Help works without root ------------------------------------------------
# The root check below would otherwise make "--help" fail for the one case
# where it is needed most: finding out how to call the script.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '/^# USAGE:/,/^# LOG:/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
      exit 0
      ;;
  esac
done

# --- Must run as root -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please start with sudo:  sudo $0 ${*:-}"
  exit 1
fi

REBOOT_MODE="ask"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reboot)    REBOOT_MODE="yes"; shift ;;
    --no-reboot) REBOOT_MODE="no"; shift ;;
    -h|--help)   sed -n '/^# USAGE:/,/^# LOG:/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *)           echo "Unknown option: $1  (see --help)"; exit 1 ;;
  esac
done

# --- Logging -----------------------------------------------------------------
LOGFILE="/var/log/system-update.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') - system-update.sh started ====="

export DEBIAN_FRONTEND=noninteractive

echo
echo "==> [1/4] Refreshing package lists"
apt-get update

echo
echo "==> [2/4] Installing available updates (full-upgrade)"
# full-upgrade also handles updates that need to install or remove packages
# (e.g. a new kernel ABI) - a plain 'upgrade' would silently hold them back.
# The dpkg options keep existing configuration files without asking, which is
# what an unattended run needs.
apt-get -y \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  full-upgrade

echo
echo "==> [3/4] Removing packages that are no longer needed"
apt-get -y autoremove --purge
apt-get -y autoclean

echo
echo "==> [4/4] Checking whether a reboot is required"
REBOOT_REQUIRED=0
if [[ -f /var/run/reboot-required ]]; then
  REBOOT_REQUIRED=1
fi

echo
echo "============================================================"
echo " System update finished."
echo "------------------------------------------------------------"
echo " Log:  $LOGFILE"
if [[ "$REBOOT_REQUIRED" -eq 1 ]]; then
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo " A reboot is required because of:"
    sort -u /var/run/reboot-required.pkgs | sed 's/^/   - /'
  else
    echo " A reboot is required."
  fi
else
  echo " No reboot required."
fi
echo "============================================================"

if [[ "$REBOOT_REQUIRED" -eq 0 ]]; then
  exit 0
fi

case "$REBOOT_MODE" in
  no)
    echo "Reboot suppressed (--no-reboot). Reboot later with:  sudo reboot"
    ;;
  yes)
    echo "Rebooting now (--reboot) ..."
    sleep 3
    reboot
    ;;
  *)
    read -r -p "Reboot now? [y/N]: " reply
    case "$reply" in
      y|Y|j|J) echo "Rebooting ..."; sleep 3; reboot ;;
      *)       echo "Not rebooting. Reboot later with:  sudo reboot" ;;
    esac
    ;;
esac
