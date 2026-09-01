#!/usr/bin/env bash
# =============================================================================
# install-hfs.sh
# -----------------------------------------------------------------------------
# Installs or updates HFS (HTTP File Server, https://rejetto.com/hfs) as a
# Docker container on Ubuntu 24.04 LTS or 26.04 LTS.
#
# What the script does:
#   1. Installs Docker CE from the official Docker repository (if missing)
#   2. Creates /opt/hfs/docker-compose.yml plus the data and share directories
#   3. Sets up the admin account with a password of your choosing
#   4. Starts the container with 'docker compose up -d'
#
# The container uses host networking, as recommended by the HFS Docker wiki -
# that is the only way HFS sees the real client IP addresses in its log. The
# listening port is therefore not mapped but set through the HFS_PORT
# environment variable.
#
# ADMIN ACCOUNT: HFS lets you create an account through the Admin-panel only
# from localhost. On a headless server that is exactly where you are not, so
# the account has to be seeded through the configuration file:
#
#   accounts:
#     admin:
#       password: <password>
#       admin: true
#
# HFS reloads config.yaml as soon as it changes and replaces the plain
# 'password' with the hashed 'srp', so the clear-text password only exists on
# disk between writing the file and HFS reading it. This script writes the
# section, waits for the hash to appear and reports the result. Without it you
# would end up with a running server you cannot administer remotely.
#
# Deliberately NOT via the documented 'create-admin: <password>' shortcut: the
# HFS build inside the container image drops that key when it rewrites the
# configuration and creates nothing. That is also why the image's own bootstrap
# (which writes exactly that key) never produces a usable login.
#
# UPDATE: simply run the script again. An existing installation is detected,
# the image is pulled and the container recreated - the configuration under
# /opt/hfs/data and the existing accounts are kept.
#
# USAGE:
#   sudo ./install-hfs.sh                     interactive (asks for port + password)
#   sudo ./install-hfs.sh --port 8080         set the port, no question about it
#   sudo ./install-hfs.sh --admin-password X  set the admin password, no question
#   sudo ./install-hfs.sh --shares /srv/data  use a different share directory
#   sudo ./install-hfs.sh --yes               accept all defaults; generates a
#                                             random admin password and prints it
#
# LOG: the complete output is appended to /var/log/hfs-install.log.
#
# Source: https://github.com/rejetto/hfs/wiki/Docker
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

# --- Defaults ---------------------------------------------------------------
HFS_DIR="/opt/hfs"
DATA_DIR="$HFS_DIR/data"
SHARES_DIR="/srv/hfs/shares"
COMPOSE_FILE="$HFS_DIR/docker-compose.yml"
CONFIG_FILE="$DATA_DIR/config.yaml"
IMAGE="rejetto/hfs:latest"
CONTAINER_NAME="hfs"
HFS_PORT="80"
ADMIN_USER="admin"
ADMIN_PASSWORD=""
ASSUME_YES=0
PORT_GIVEN=0
ADMIN_PASSWORD_GIVEN=0
ADMIN_PASSWORD_GENERATED=0

# --- Arguments --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)   HFS_PORT="${2:-}"; PORT_GIVEN=1; shift 2 ;;
    -s|--shares) SHARES_DIR="${2:-}"; shift 2 ;;
    -A|--admin-password)
                 ADMIN_PASSWORD="${2:-}"; ADMIN_PASSWORD_GIVEN=1; shift 2 ;;
    -y|--yes)    ASSUME_YES=1; shift ;;
    -h|--help)   sed -n '/^# USAGE:/,/^# LOG:/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *)           echo "Unknown option: $1  (see --help)"; exit 1 ;;
  esac
done

# --- Logging -----------------------------------------------------------------
LOGFILE="/var/log/hfs-install.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') - install-hfs.sh started ====="

# The user who may run docker commands afterwards
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# Detect an existing installation -> update instead of fresh install
UPDATE_MODE=0
if [[ -f "$COMPOSE_FILE" ]]; then
  UPDATE_MODE=1
fi

if [[ "$UPDATE_MODE" -eq 1 ]]; then
  echo "==> HFS update (existing installation detected)"
else
  echo "==> HFS installation"
fi
echo "    Log: $LOGFILE"
echo

# --- Ask for the port --------------------------------------------------------
valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# On an update keep the port that is already configured, unless one was passed
# explicitly on the command line.
if [[ "$UPDATE_MODE" -eq 1 && "$PORT_GIVEN" -eq 0 ]]; then
  EXISTING_PORT="$(grep -oP 'HFS_PORT:\s*"\K[0-9]+' "$COMPOSE_FILE" 2>/dev/null | head -n1 || true)"
  if [[ -n "$EXISTING_PORT" ]]; then
    HFS_PORT="$EXISTING_PORT"
    echo "    Keeping the configured port: $HFS_PORT"
  fi
fi

if [[ "$ASSUME_YES" -eq 0 && "$PORT_GIVEN" -eq 0 ]]; then
  while true; do
    read -r -p "Port for the HFS web interface [Enter = $HFS_PORT]: " reply
    reply="${reply:-$HFS_PORT}"
    if valid_port "$reply"; then
      HFS_PORT="$reply"
      break
    fi
    echo "    Please enter a port between 1 and 65535."
  done
fi

if ! valid_port "$HFS_PORT"; then
  echo "ERROR: '$HFS_PORT' is not a valid port."
  exit 1
fi

# Warn when the port is already taken by something else on the host. Host
# networking means there is no port mapping that could avoid the clash.
if command -v ss >/dev/null 2>&1; then
  if ss -ltnH "sport = :$HFS_PORT" 2>/dev/null | grep -q . \
     && ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    echo
    echo "WARNING: port $HFS_PORT is already in use on this host. HFS uses host"
    echo "         networking, so it cannot start while another service holds"
    echo "         that port. Pick a different port or stop the other service."
    if [[ "$ASSUME_YES" -eq 0 ]]; then
      read -r -p "Continue anyway? [y/N]: " reply
      case "$reply" in
        y|Y|j|J) ;;
        *) echo "Aborted, nothing has been changed."; exit 0 ;;
      esac
    fi
  fi
fi

# --- 1. Install Docker -------------------------------------------------------
echo
echo "==> [1/5] Making sure Docker is available"
export DEBIAN_FRONTEND=noninteractive

install_docker_official() {
  local codename repo_base="https://download.docker.com/linux/ubuntu"

  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "$repo_base/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # VERSION_CODENAME of the running release. Directly after a new Ubuntu
  # release Docker does not always publish a matching suite yet - in that case
  # fall back to the newest LTS suite that is known to exist.
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
  if [[ -z "$codename" ]] \
     || ! curl -fsI "$repo_base/dists/$codename/Release" >/dev/null 2>&1; then
    echo "    Note: Docker has no repository for '$codename' yet - using 'noble'."
    codename="noble"
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $repo_base $codename stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io \
                     docker-buildx-plugin docker-compose-plugin
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "    Docker is already installed: $(docker --version)"
else
  echo "    Installing Docker CE from the official Docker repository ..."
  if ! install_docker_official; then
    echo
    echo "    Installation from the Docker repository failed - falling back to"
    echo "    the Ubuntu packages (docker.io + docker-compose-v2)."
    apt-get install -y docker.io docker-compose-v2
  fi
  echo "    Installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' is not available. Install the compose plugin"
  echo "       manually (apt-get install -y docker-compose-plugin) and retry."
  exit 1
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker  >/dev/null 2>&1 || true

# Let the user run docker without sudo (takes effect after the next login)
if getent group docker >/dev/null 2>&1 && [[ "$TARGET_USER" != "root" ]]; then
  usermod -aG docker "$TARGET_USER" 2>/dev/null || true
  echo "    User '$TARGET_USER' added to the 'docker' group."
fi

# --- 2. Directories and compose file ----------------------------------------
echo
echo "==> [2/5] Preparing directories and configuration"
mkdir -p "$DATA_DIR" "$SHARES_DIR"
echo "    Data directory:  $DATA_DIR"
echo "    Share directory: $SHARES_DIR"

cat > "$COMPOSE_FILE" <<EOF
# Generated by install-hfs.sh - adjust and run 'docker compose up -d' in
# $HFS_DIR to apply changes.
#
# network_mode: host is recommended by the HFS Docker wiki so that HFS sees
# the real client IP addresses. With host networking there is no port mapping,
# which is why the port is set through HFS_PORT.
services:
  hfs:
    image: $IMAGE
    container_name: $CONTAINER_NAME
    network_mode: host
    restart: unless-stopped
    environment:
      HFS_PORT: "$HFS_PORT"
    volumes:
      - $DATA_DIR:/data
      - $SHARES_DIR:/shares
EOF
echo "    Configuration written: $COMPOSE_FILE"

# --- 3. Admin account --------------------------------------------------------
echo
echo "==> [3/5] Admin account"

# Escapes a value for a single-quoted YAML scalar: the only character that
# needs handling there is the single quote itself, which is doubled.
yaml_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

# An account exists as soon as config.yaml has an 'accounts:' section. The
# container writes config.yaml itself on its very first start; if it is not
# there yet, this is a fresh installation.
ADMIN_EXISTS=0
if [[ -f "$CONFIG_FILE" ]] && grep -q '^accounts:' "$CONFIG_FILE"; then
  ADMIN_EXISTS=1
fi

if [[ "$ADMIN_EXISTS" -eq 1 ]]; then
  echo "    An account already exists in $CONFIG_FILE - leaving it alone."
  echo "    To reset the password, use the Admin-panel, or set a plain"
  echo "    'password:' on the account in that file - HFS hashes it on read."
else
  # Ask for the password unless it came from the command line. Hidden entry,
  # twice, so a typo does not lock you out of the Admin-panel.
  if [[ "$ADMIN_PASSWORD_GIVEN" -eq 0 ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      # Unattended run: generate one and print it at the end. 18 bytes of
      # base64 without the characters that are awkward to retype.
      ADMIN_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | cut -c1-20)"
      ADMIN_PASSWORD_GENERATED=1
      echo "    No password given (--yes) - generating one."
    else
      echo "    HFS allows creating an account through the Admin-panel only from"
      echo "    localhost, so the first account is seeded here."
      echo
      while true; do
        read -r -s -p "    Password for the '$ADMIN_USER' account: " ADMIN_PASSWORD
        echo
        read -r -s -p "    Repeat the password: " ADMIN_PASSWORD_CONFIRM
        echo
        if [[ -z "$ADMIN_PASSWORD" ]]; then
          echo "    The password must not be empty. Please try again."
          continue
        fi
        if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
          echo "    The two entries do not match. Please try again."
          continue
        fi
        break
      done
    fi
  fi

  if [[ -z "$ADMIN_PASSWORD" ]]; then
    echo "ERROR: the admin password must not be empty."
    exit 1
  fi

  # Write the account into the 'accounts:' section of config.yaml. HFS replaces
  # the plain 'password' with the hashed 'srp' as soon as it reads the file.
  #
  # NOT via the 'create-admin:' shortcut: the HFS build inside the container
  # image silently drops that key when it rewrites the configuration, leaving
  # no account behind - which is also why the image's own bootstrap default
  # never produces a usable login. The 'accounts:' section is HFS's primary,
  # long-standing mechanism and is honoured.
  #
  # Two cases:
  #   - No config.yaml yet: write it completely. The vfs entry mirrors what the
  #     image would generate itself, so /shares stays available, and writing it
  #     before the first start keeps the image from bootstrapping a default.
  #   - config.yaml exists but has no account: append the section. HFS reloads
  #     the file as soon as it changes, so this works whether the container is
  #     running or not.
  admin_account_block() {
    printf 'accounts:\n'
    printf '  %s:\n' "$ADMIN_USER"
    printf '    password: %s\n' "$(yaml_single_quote "$ADMIN_PASSWORD")"
    printf '    admin: true\n'
  }

  if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$DATA_DIR"
    {
      admin_account_block
      printf 'vfs:\n  source: /shares\n'
    } > "$CONFIG_FILE"
    echo "    Created $CONFIG_FILE with the '$ADMIN_USER' account."
  else
    # Clean up a leftover entry from an earlier version of this script, so it
    # cannot confuse the check further down.
    sed -i '/^create-admin:/d' "$CONFIG_FILE"
    # If the file does not end in a newline, the new key would be glued onto
    # the last line and break the YAML.
    if [[ -s "$CONFIG_FILE" && -n "$(tail -c1 "$CONFIG_FILE")" ]]; then
      printf '\n' >> "$CONFIG_FILE"
    fi
    admin_account_block >> "$CONFIG_FILE"
    echo "    Added the '$ADMIN_USER' account to the existing $CONFIG_FILE."
  fi
fi

# --- 4. Pull the image and start the container ------------------------------
echo
if [[ "$UPDATE_MODE" -eq 1 ]]; then
  echo "==> [4/5] Pulling the image and recreating the container"
else
  echo "==> [4/5] Pulling the image and starting the container"
fi
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d

# --- 5. Wait for the web interface and the account --------------------------
echo
echo "==> [5/5] Waiting for the web interface (port $HFS_PORT)"

# Ubuntu Server ships with ufw INACTIVE -> no ports blocked. If ufw is active,
# open the configured port.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$HFS_PORT/tcp" >/dev/null 2>&1 || true
  echo "    ufw rule for port $HFS_PORT/tcp added."
fi

UI_REACHABLE=0
for _ in $(seq 1 30); do
  if curl -fs -o /dev/null "http://127.0.0.1:$HFS_PORT/" 2>/dev/null; then
    UI_REACHABLE=1
    break
  fi
  sleep 2
done

# Confirm that HFS really picked up the account. It replaces the plain
# 'password' with the hashed 'srp' as soon as it reads the configuration, so
# an 'srp:' in the file is the proof that the account is live. Without this
# check the script could report success while leaving behind a server nobody
# can administer.
ADMIN_READY=0
if [[ "$ADMIN_EXISTS" -eq 1 ]]; then
  ADMIN_READY=1
else
  for _ in $(seq 1 30); do
    if [[ -f "$CONFIG_FILE" ]] && grep -q 'srp:' "$CONFIG_FILE"; then
      ADMIN_READY=1
      break
    fi
    sleep 2
  done
fi

# The account is already usable once HFS has read the file, even before it
# writes the hash back. Distinguish "not hashed yet" from "not there at all"
# instead of reporting a single vague failure.
ADMIN_CONFIGURED=0
if [[ -f "$CONFIG_FILE" ]] && grep -q '^accounts:' "$CONFIG_FILE"; then
  ADMIN_CONFIGURED=1
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')

if [[ "$UPDATE_MODE" -eq 1 ]]; then
  ACTION_DONE="update"
else
  ACTION_DONE="installation"
fi

echo
if [[ "$UI_REACHABLE" -eq 1 ]]; then
  echo "============================================================"
  echo " HFS $ACTION_DONE finished."
else
  echo "============================================================"
  echo " HFS $ACTION_DONE finished, but the web interface did not"
  echo " answer within 60 seconds. Check with:"
  echo "   docker compose -f $COMPOSE_FILE logs -f"
fi
echo "------------------------------------------------------------"
echo " Web interface:   http://${IP:-<SERVER-IP>}:$HFS_PORT"
echo " Admin panel:     http://${IP:-<SERVER-IP>}:$HFS_PORT/~/admin"
echo
if [[ "$ADMIN_EXISTS" -eq 1 ]]; then
  echo " Account:         '$ADMIN_USER' (existing, password unchanged)"
elif [[ "$ADMIN_READY" -eq 1 ]]; then
  echo " Account:         '$ADMIN_USER'"
  if [[ "$ADMIN_PASSWORD_GENERATED" -eq 1 ]]; then
    echo " Password:        $ADMIN_PASSWORD"
    echo "                  (generated - write it down, it is not shown again)"
  else
    echo " Password:        the one you entered"
  fi
elif [[ "$ADMIN_CONFIGURED" -eq 1 ]]; then
  echo " Account:         '$ADMIN_USER'"
  if [[ "$ADMIN_PASSWORD_GENERATED" -eq 1 ]]; then
    echo " Password:        $ADMIN_PASSWORD"
    echo "                  (generated - write it down, it is not shown again)"
  fi
  echo
  echo " NOTE: the account is in $CONFIG_FILE, but HFS has not replaced the"
  echo "       plain password with its hash within 60 seconds. Usually it just"
  echo "       has not read the file yet - the login should work anyway. Check:"
  echo "         grep -A3 '^accounts:' $CONFIG_FILE"
  echo "       Once 'srp:' shows up there, HFS has taken it over."
else
  echo " WARNING: the '$ADMIN_USER' account is not in $CONFIG_FILE."
  echo "          Something rewrote the file. Check the container:"
  echo "            docker compose -f $COMPOSE_FILE logs -f"
  echo "          Then run this script again."
fi
echo "------------------------------------------------------------"
echo " Files to share:  put them into $SHARES_DIR"
echo "                  (further folders can be added in the admin panel)"
echo " Configuration:   $DATA_DIR"
echo " Compose file:    $COMPOSE_FILE"
echo
echo " Useful commands:"
echo "   docker compose -f $COMPOSE_FILE ps"
echo "   docker compose -f $COMPOSE_FILE logs -f"
echo "   docker compose -f $COMPOSE_FILE restart"
echo
echo " Run this script again at any time to update HFS."
echo " For 'docker' without sudo, log out and back in once."
echo "============================================================"
