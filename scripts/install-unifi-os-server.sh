#!/usr/bin/env bash
# =============================================================================
# install-unifi-os-server.sh
# -----------------------------------------------------------------------------
# Installs UniFi OS Server (Linux x64) on Ubuntu 24.04 LTS or 26.04 LTS.
# Official method: Podman plus running the downloaded installer.
#
# UPDATE: the script detects an existing installation automatically (the
# 'uosserver' service exists) and adjusts its output accordingly ("update"
# instead of "installation"). For an update simply run it again with the new
# download URL - the installer itself upgrades an existing installation rather
# than creating a new one.
#
# USAGE (three ways, one is enough):
#
#   1) Pass the URL directly (recommended, fully automatic):
#        sudo ./install-unifi-os-server.sh "https://fw-download.ubnt.com/data/unifi-os-server/....-x64"
#
#   2) Pass the URL as an environment variable:
#        sudo UOS_URL="https://fw-download.ubnt.com/data/unifi-os-server/....-x64" ./install-unifi-os-server.sh
#
#   3) Start without a URL -> the script asks for it interactively.
#
# Where do I get the URL? (takes 10 seconds)
#   -> open https://ui.com/download/releases/unifi-os-server
#   -> right-click the download of the "Linux (x64)" entry
#   -> "Copy link address"
#   The URL looks like this:
#     https://fw-download.ubnt.com/data/unifi-os-server/1856-linux-x64-5.1.21-....-x64
#
# Why is there no fixed "always latest" URL in the script?
#   Ubiquiti does not publish a stable "latest" link for the Linux installer;
#   the file name contains the version plus a checksum and changes with every
#   release. Copying the link is the only reliable way to get the current one.
#
# LOG: the complete output is appended to /var/log/unifi-install.log
# (nothing is overwritten) - useful for troubleshooting after the fact, e.g.
# when the installation fails and the terminal output is gone.
# =============================================================================
set -euo pipefail

# --- Must run as root -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please start with sudo:  sudo $0 ${*:-}"
  exit 1
fi

# --- Logging ----------------------------------------------------------------
LOGFILE="/var/log/unifi-install.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') - install-unifi-os-server.sh started ====="

# The user who may run 'uosserver' commands later on
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# Detect an existing installation -> update instead of fresh install. The
# Podman installer upgrades an existing installation by itself when run again;
# only the wording of this script's output changes here.
UPDATE_MODE=0
if systemctl cat uosserver >/dev/null 2>&1; then
  UPDATE_MODE=1
fi

if [[ "$UPDATE_MODE" -eq 1 ]]; then
  echo "==> UniFi OS Server update (existing installation detected)"
else
  echo "==> UniFi OS Server installation"
fi
echo "    Target user for the uosserver group: $TARGET_USER"
echo "    Log:                                 $LOGFILE"
echo

# --- Determine the download URL ---------------------------------------------
UOS_URL="${1:-${UOS_URL:-}}"
if [[ -z "${UOS_URL}" ]]; then
  echo "No download URL was passed."
  echo "Please open https://ui.com/download/releases/unifi-os-server, right-click"
  echo "the Linux (x64) download, choose 'Copy link address' and paste it here:"
  read -r -p "UniFi OS Server URL: " UOS_URL
fi

case "$UOS_URL" in
  https://fw-download.ubnt.com/*|https://*ubnt.com/*|https://*ui.com/*) : ;;
  *) echo "ERROR: this does not look like a valid Ubiquiti URL:"; echo "  $UOS_URL"; exit 1 ;;
esac

# --- 1. System and dependencies ---------------------------------------------
echo
echo "==> [1/5] Refreshing package lists and making sure dependencies are present"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# podman >= 4.9.3 and slirp4netns >= 1.2 are mandatory (both ship with 24.04 and 26.04)
apt-get install -y podman slirp4netns curl ca-certificates

echo "    podman version: $(podman --version 2>/dev/null || echo 'NOT found')"

# --- 2. Download the installer ----------------------------------------------
echo
echo "==> [2/5] Downloading the installer"
# NOTE: /var/tmp on purpose, not /tmp. On some Ubuntu versions (e.g. 26.04)
# systemd mounts /tmp as a tmpfs (RAM backed); the installer is large enough
# that this causes "curl: (23) Failure writing output to destination" (out of
# space) on smaller VMs. /var/tmp always lives on disk.
WORKDIR="$(mktemp -d --tmpdir=/var/tmp)"
INSTALLER="$WORKDIR/uos-server-installer"

# Rough preflight check: is there enough free disk space for the download?
MIN_FREE_BYTES=2000000000
FREE_BYTES=$(df --output=avail -B1 "$WORKDIR" 2>/dev/null | tail -n1 | tr -d ' ')
if [[ -n "${FREE_BYTES:-}" && "$FREE_BYTES" -lt "$MIN_FREE_BYTES" ]]; then
  echo "ERROR: not enough free disk space in $WORKDIR ($((FREE_BYTES/1024/1024)) MB free,"
  echo "       at least $((MIN_FREE_BYTES/1024/1024)) MB are needed for the installer download)."
  echo "       Please enlarge the disk of the VM and try again."
  exit 1
fi

curl -fL --retry 3 --progress-bar -o "$INSTALLER" "$UOS_URL"

# Rough sanity check: the file should be neither tiny nor HTML
BYTES=$(stat -c%s "$INSTALLER" 2>/dev/null || echo 0)
if [[ "$BYTES" -lt 1000000 ]]; then
  echo "ERROR: the downloaded file is only ${BYTES} bytes."
  echo "       The URL may have expired or be wrong. Please copy the link again."
  exit 1
fi
if head -c 512 "$INSTALLER" | grep -qi "<html\|<!doctype"; then
  echo "ERROR: an HTML page was downloaded instead of the installer."
  echo "       Please copy the download URL again via right-click."
  exit 1
fi
chmod +x "$INSTALLER"
echo "    Downloaded: $((BYTES/1024/1024)) MB"

# --- 3. Run the installer (unattended) --------------------------------------
echo
if [[ "$UPDATE_MODE" -eq 1 ]]; then
  echo "==> [3/5] Updating UniFi OS Server (this can take a few minutes)"
else
  echo "==> [3/5] Installing UniFi OS Server (this can take a few minutes)"
fi
# 'yes' answers any prompts of the installer with 'y'. The installer detects an
# existing installation itself and then updates it instead of reinstalling. It
# sometimes reports a timeout or an error although it keeps running in the
# background - the exit code alone is therefore not a reliable success
# indicator. That is why the systemd service is checked right afterwards.
yes | "$INSTALLER" || true

if ! systemctl cat uosserver >/dev/null 2>&1; then
  echo
  echo "ERROR: the service 'uosserver' was not found."
  echo "       The installation/update failed (see the installer output above"
  echo "       or the log: $LOGFILE)."
  echo "       Common causes: wrong or expired URL, too little RAM, network problem."
  exit 1
fi

# --- 4. Group membership and service -----------------------------------------
echo
echo "==> [4/5] Permissions and service"
if getent group uosserver >/dev/null 2>&1; then
  usermod -aG uosserver "$TARGET_USER" 2>/dev/null || true
  echo "    User '$TARGET_USER' added to the 'uosserver' group."
fi
# Enable the service so UniFi starts automatically after every reboot
systemctl enable uosserver 2>/dev/null || true
systemctl start  uosserver 2>/dev/null || true

# --- 5. Firewall note and waiting for the web UI -----------------------------
echo
echo "==> [5/5] Service is starting - waiting for the web interface (port 11443)"
# Ubuntu Server ships with ufw INACTIVE -> no ports blocked.
# If ufw is active, open the most important UniFi ports:
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  for p in 11443/tcp 8080/tcp 8443/tcp 8843/tcp 8880/tcp 6789/tcp 443/tcp 3478/udp 10001/udp; do
    ufw allow "$p" >/dev/null 2>&1 || true
  done
  echo "    ufw rules for the UniFi ports added."
fi

# Wait for the UI (up to ~5 minutes; the first start takes a while on weak hardware)
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
UI_REACHABLE=0
for _ in $(seq 1 60); do
  if curl -ks "https://127.0.0.1:11443" -o /dev/null 2>/dev/null; then
    UI_REACHABLE=1
    break
  fi
  sleep 5
done

echo
if [[ "$UPDATE_MODE" -eq 1 ]]; then
  ACTION_DONE="update"
else
  ACTION_DONE="installation"
fi

if [[ "$UI_REACHABLE" -eq 1 ]]; then
  echo "============================================================"
  echo " UniFi OS Server $ACTION_DONE finished."
  echo "------------------------------------------------------------"
  echo " Web interface:   https://${IP:-<SERVER-IP>}:11443"
  echo " (The certificate warning in the browser is expected - accept it.)"
  echo
  echo " Notes:"
  echo "  - Log out and back in once for 'uosserver' commands (group update)."
  echo "  - Log of this run: $LOGFILE"
  echo "  - To update later, run this script again with a new download URL."
  echo "============================================================"
else
  echo "============================================================"
  echo " WARNING: the $ACTION_DONE ran, but the web interface did not"
  echo " answer within 5 minutes."
  echo "------------------------------------------------------------"
  echo " Please check:"
  echo "  - Service status:  systemctl status uosserver"
  echo "  - On weak hardware the first start can take longer -"
  echo "    just try again in a few minutes:"
  echo "    https://${IP:-<SERVER-IP>}:11443"
  echo "  - Log of this run: $LOGFILE"
  echo "============================================================"
fi
