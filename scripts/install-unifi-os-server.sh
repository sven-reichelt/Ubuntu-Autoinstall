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
# OPERATOR ACCOUNT: membership in the 'uosserver' group is what allows running
# uosserver commands without root. By default that would be the account you are
# logged in with - normally the general-purpose admin of the machine. On a box
# that exists only to run UniFi, a separate account keeps system administration
# and UniFi operation apart, so the script offers to create one.
#
# USAGE (three ways to pass the URL, one is enough):
#
#   1) Pass the URL directly (recommended, fully automatic):
#        sudo ./install-unifi-os-server.sh "https://fw-download.ubnt.com/data/unifi-os-server/....-x64"
#
#   2) Pass the URL as an environment variable:
#        sudo UOS_URL="https://fw-download.ubnt.com/data/unifi-os-server/....-x64" ./install-unifi-os-server.sh
#
#   3) Start without a URL -> the script asks for it interactively.
#
# OPTIONS:
#   --operator <name>       account for the 'uosserver' group; created if it
#                           does not exist yet
#   --operator-password <p> its password (only used when the account is created)
#   --keep-current-user     also keep the calling user in the group
#   --no-operator           do not touch group membership at all
#   -y, --yes               no questions; keeps the calling user in the group
#   -h, --help              show this help
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

# --- Help works without root ------------------------------------------------
# The root check below would otherwise make "--help" fail for the one case
# where it is needed most: finding out how to call the script.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '/^# USAGE/,/^# PROTOCOL\|^# LOG:/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
      exit 0
      ;;
  esac
done

# --- Must run as root -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please start with sudo:  sudo $0 ${*:-}"
  exit 1
fi

# --- Arguments ---------------------------------------------------------------
# The URL may be given as a positional argument, so options and the URL are
# parsed together here.
UOS_URL_ARG=""
OPERATOR_USER=""
OPERATOR_PASSWORD=""
OPERATOR_PASSWORD_GIVEN=0
OPERATOR_MODE=""          # ask | current | separate | both | none
KEEP_CURRENT_USER=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operator)          OPERATOR_USER="${2:-}"; OPERATOR_MODE="separate"; shift 2 ;;
    --operator-password) OPERATOR_PASSWORD="${2:-}"; OPERATOR_PASSWORD_GIVEN=1; shift 2 ;;
    --keep-current-user) KEEP_CURRENT_USER=1; shift ;;
    --no-operator)       OPERATOR_MODE="none"; shift ;;
    -y|--yes)            ASSUME_YES=1; shift ;;
    -h|--help)           exit 0 ;;   # already handled above
    -*)                  echo "Unknown option: $1  (see --help)"; exit 1 ;;
    *)                   UOS_URL_ARG="$1"; shift ;;
  esac
done

if [[ "$OPERATOR_MODE" == "separate" && "$KEEP_CURRENT_USER" -eq 1 ]]; then
  OPERATOR_MODE="both"
fi

# --- Logging ----------------------------------------------------------------
LOGFILE="/var/log/unifi-install.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') - install-unifi-os-server.sh started ====="

# The account that invoked sudo - the default candidate for the uosserver group
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
echo "    Log: $LOGFILE"
echo

# --- Determine the download URL ---------------------------------------------
UOS_URL="${UOS_URL_ARG:-${UOS_URL:-}}"
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

# --- Who may run uosserver commands? -----------------------------------------
# Asked here, before the installation, so the download and install can run
# unattended afterwards. The group itself only exists once the installer has
# run, so the membership is applied later in step 4.

# A valid Linux user name: starts with a letter or underscore, then letters,
# digits, underscore or hyphen. Same rule adduser enforces.
valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

DEFAULT_OPERATOR="unifi"

if [[ -z "$OPERATOR_MODE" ]]; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    OPERATOR_MODE="current"
  else
    echo "==> Which Linux account should be allowed to run 'uosserver' commands?"
    echo
    echo "    Membership in the 'uosserver' group grants that without root."
    echo "    On a machine dedicated to UniFi it is worth keeping this apart"
    echo "    from the general admin account."
    echo
    echo "      1) $TARGET_USER (the account you are using now)"
    echo "      2) a separate account, created now"
    echo "      3) both"
    echo "      4) nobody for now - I will set the group membership myself"
    while true; do
      read -r -p "    Selection [1-4, Enter = 1]: " reply
      case "${reply:-1}" in
        1) OPERATOR_MODE="current";  break ;;
        2) OPERATOR_MODE="separate"; break ;;
        3) OPERATOR_MODE="both";     break ;;
        4) OPERATOR_MODE="none";     break ;;
        *) echo "    Please enter 1, 2, 3 or 4." ;;
      esac
    done
    echo
  fi
fi

# Ask for the name of the separate account, unless --operator supplied one.
if [[ "$OPERATOR_MODE" == "separate" || "$OPERATOR_MODE" == "both" ]]; then
  if [[ -z "$OPERATOR_USER" ]]; then
    while true; do
      read -r -p "    Name of the account [Enter = $DEFAULT_OPERATOR]: " reply
      reply="${reply:-$DEFAULT_OPERATOR}"
      if valid_username "$reply"; then
        OPERATOR_USER="$reply"
        break
      fi
      echo "    Invalid user name. Lower-case letters, digits, '_' and '-',"
      echo "    starting with a letter or '_'."
    done
  fi

  if ! valid_username "$OPERATOR_USER"; then
    echo "ERROR: '$OPERATOR_USER' is not a valid user name."
    exit 1
  fi
  if [[ "$OPERATOR_USER" == "root" ]]; then
    echo "ERROR: 'root' is already allowed to do everything - pick another name."
    exit 1
  fi
  # Asking for a separate account and then naming the current one is not an
  # error, it just means option 1.
  if [[ "$OPERATOR_USER" == "$TARGET_USER" ]]; then
    echo "    '$OPERATOR_USER' is the account you are already using."
    OPERATOR_MODE="current"
  fi
fi

# Ask for the password of an account that does not exist yet. An existing
# account keeps its password - this script has no business changing it.
OPERATOR_CREATE=0
if [[ "$OPERATOR_MODE" == "separate" || "$OPERATOR_MODE" == "both" ]]; then
  if id "$OPERATOR_USER" >/dev/null 2>&1; then
    echo "    Account '$OPERATOR_USER' already exists - only the group is added,"
    echo "    the password stays as it is."
  else
    OPERATOR_CREATE=1
    if [[ "$OPERATOR_PASSWORD_GIVEN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
      echo
      echo "    Password for the new account '$OPERATOR_USER'."
      echo "    Press Enter twice to create it without one - it can then not be"
      echo "    used to log in directly, only via 'sudo -iu $OPERATOR_USER'."
      while true; do
        read -r -s -p "    Password: " OPERATOR_PASSWORD
        echo
        read -r -s -p "    Repeat:   " OPERATOR_PASSWORD_CONFIRM
        echo
        if [[ "$OPERATOR_PASSWORD" != "$OPERATOR_PASSWORD_CONFIRM" ]]; then
          echo "    The two entries do not match. Please try again."
          continue
        fi
        break
      done
    fi
  fi
  echo
fi

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

# Everything below only makes sense once the installer has created the group.
GROUP_MEMBERS=()
if ! getent group uosserver >/dev/null 2>&1; then
  echo "    The 'uosserver' group does not exist - skipping group membership."
else
  # Create the separate account if it was asked for and is not there yet.
  if [[ "$OPERATOR_CREATE" -eq 1 ]]; then
    if useradd --create-home --shell /bin/bash --comment "UniFi OS Server operator" \
               "$OPERATOR_USER"; then
      echo "    Account '$OPERATOR_USER' created."
      if [[ -n "$OPERATOR_PASSWORD" ]]; then
        echo "$OPERATOR_USER:$OPERATOR_PASSWORD" | chpasswd
        echo "    Password set."
      else
        # No password means no direct login - lock it explicitly rather than
        # leaving an account with an empty password behind.
        passwd -l "$OPERATOR_USER" >/dev/null 2>&1 || true
        echo "    No password set - the account is locked for direct login."
        echo "    Use it with:  sudo -iu $OPERATOR_USER"
      fi
    else
      echo "    WARNING: could not create the account '$OPERATOR_USER'."
      OPERATOR_MODE="current"
    fi
  fi

  case "$OPERATOR_MODE" in
    current)  GROUP_MEMBERS=("$TARGET_USER") ;;
    separate) GROUP_MEMBERS=("$OPERATOR_USER") ;;
    both)     GROUP_MEMBERS=("$TARGET_USER" "$OPERATOR_USER") ;;
    none)     GROUP_MEMBERS=() ;;
  esac

  if [[ ${#GROUP_MEMBERS[@]} -eq 0 ]]; then
    echo "    No account added to the 'uosserver' group (as requested)."
    echo "    Add one later with:  sudo usermod -aG uosserver <account>"
  else
    for member in "${GROUP_MEMBERS[@]}"; do
      if usermod -aG uosserver "$member" 2>/dev/null; then
        echo "    User '$member' added to the 'uosserver' group."
      else
        echo "    WARNING: could not add '$member' to the 'uosserver' group."
      fi
    done
  fi

  # When the calling user is deliberately NOT a member, say so - otherwise the
  # first 'uosserver' command after the installation fails without explanation.
  if [[ "$OPERATOR_MODE" == "separate" ]]; then
    echo "    Note: '$TARGET_USER' is deliberately NOT in the group."
  fi
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
  if [[ ${#GROUP_MEMBERS[@]} -gt 0 ]]; then
    echo "  - 'uosserver' commands: ${GROUP_MEMBERS[*]}"
    echo "    Log out and back in once so the new group membership applies."
  fi
  if [[ "$OPERATOR_CREATE" -eq 1 && -z "$OPERATOR_PASSWORD" ]]; then
    echo "  - '$OPERATOR_USER' has no password - switch to it with:"
    echo "      sudo -iu $OPERATOR_USER"
  fi
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
