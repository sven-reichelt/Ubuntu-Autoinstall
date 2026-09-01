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
#   3. Starts the container with 'docker compose up -d'
#
# The container uses host networking, as recommended by the HFS Docker wiki -
# that is the only way HFS sees the real client IP addresses in its log. The
# listening port is therefore not mapped but set through the HFS_PORT
# environment variable.
#
# UPDATE: simply run the script again. An existing installation is detected,
# the image is pulled and the container recreated - the configuration under
# /opt/hfs/data is kept.
#
# USAGE:
#   sudo ./install-hfs.sh                     interactive (asks for the port)
#   sudo ./install-hfs.sh --port 8080         set the port, no questions
#   sudo ./install-hfs.sh --shares /srv/data  use a different share directory
#   sudo ./install-hfs.sh --yes               accept all defaults
#
# LOG: the complete output is appended to /var/log/hfs-install.log.
#
# Source: https://github.com/rejetto/hfs/wiki/Docker
# =============================================================================
set -euo pipefail

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
IMAGE="rejetto/hfs:latest"
CONTAINER_NAME="hfs"
HFS_PORT="80"
ASSUME_YES=0
PORT_GIVEN=0

# --- Arguments --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)   HFS_PORT="${2:-}"; PORT_GIVEN=1; shift 2 ;;
    -s|--shares) SHARES_DIR="${2:-}"; shift 2 ;;
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
echo "==> [1/4] Making sure Docker is available"
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
echo "==> [2/4] Preparing directories and configuration"
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

# --- 3. Pull the image and start the container ------------------------------
echo
if [[ "$UPDATE_MODE" -eq 1 ]]; then
  echo "==> [3/4] Pulling the image and recreating the container"
else
  echo "==> [3/4] Pulling the image and starting the container"
fi
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d

# --- 4. Wait for the web interface ------------------------------------------
echo
echo "==> [4/4] Waiting for the web interface (port $HFS_PORT)"

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
echo " IMPORTANT: the image creates a default account"
echo "     user: admin    password: please-change"
echo " Change this password IMMEDIATELY in the admin panel."
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
