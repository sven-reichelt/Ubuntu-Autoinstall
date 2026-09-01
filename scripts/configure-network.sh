#!/usr/bin/env bash
# =============================================================================
# configure-network.sh
# -----------------------------------------------------------------------------
# Asks interactively whether the network interface should use DHCP or a static
# IP address and writes the matching netplan configuration.
#
# USAGE:
#   sudo ./configure-network.sh
#
# IMPORTANT (merged netplan configuration):
#   Netplan applies ALL *.yaml files in /etc/netplan/ together. The
#   50-cloud-init.yaml written by cloud-init on first boot (DHCP on "e*")
#   would otherwise compete with the static IP set here for the same
#   interface. This script therefore moves ALL other netplan files aside
#   (backup, nothing is lost) and additionally disables network management by
#   cloud-init for good. From then on this file (90-autoinstall-network.yaml)
#   is the single source of truth - even when switching back to DHCP it is
#   rewritten, never just deleted.
#
# SAFETY NET (netplan try instead of netplan apply):
#   The new configuration is first applied ON TRIAL only. If the current
#   session stays reachable, confirm with ENTER in exactly this window. If the
#   connection drops there is nothing left to press - which is precisely why
#   netplan restores the previous configuration automatically once the timeout
#   expires. Since 'netplan try' only rolls back the RUNNING connection but not
#   the files in /etc/netplan/, this script additionally backs up the previous
#   file state and restores it exactly on a rejected attempt (otherwise a
#   reboot would activate the unconfirmed configuration after all).
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please start with sudo:  sudo $0"
  exit 1
fi

NETPLAN_DIR="/etc/netplan"
OUR_FILE="$NETPLAN_DIR/90-autoinstall-network.yaml"
BACKUP_DIR="$NETPLAN_DIR/configure-network.orig"
CLOUD_INIT_DISABLE_FILE="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
# Timeout for 'netplan try': how long the new configuration stays active on
# trial without confirmation by ENTER before it is rolled back automatically.
NETPLAN_TRY_TIMEOUT=60

echo "==> Network configuration"
echo

# --- Helper functions --------------------------------------------------------

valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local o
  for o in "${BASH_REMATCH[@]:1}"; do
    (( o <= 255 )) || return 1
  done
  return 0
}

# Converts a dotted subnet mask (255.255.255.0) into a prefix (24).
# A prefix (0-32) that is passed in is simply handed back unchanged.
netmask_to_prefix() {
  local input="$1"
  if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 0 && input <= 32 )); then
    echo "$input"
    return 0
  fi
  if ! valid_ipv4 "$input"; then
    return 1
  fi
  local -a octets
  IFS=. read -r -a octets <<< "$input"
  local prefix=0 octet
  for octet in "${octets[@]}"; do
    case "$octet" in
      255) prefix=$((prefix+8)) ;;
      254) prefix=$((prefix+7)) ;;
      252) prefix=$((prefix+6)) ;;
      248) prefix=$((prefix+5)) ;;
      240) prefix=$((prefix+4)) ;;
      224) prefix=$((prefix+3)) ;;
      192) prefix=$((prefix+2)) ;;
      128) prefix=$((prefix+1)) ;;
      0)   ;;
      *)   return 1 ;;
    esac
  done
  echo "$prefix"
}

ask_ipv4() {
  local prompt="$1" required="$2" answer
  while true; do
    read -r -p "$prompt" answer
    if [[ -z "$answer" && "$required" == "no" ]]; then
      echo ""
      return 0
    fi
    if valid_ipv4 "$answer"; then
      echo "$answer"
      return 0
    fi
    echo "    Invalid IPv4 address, please try again (e.g. 192.168.1.10)." >&2
  done
}

# --- 1. Pick the network interface ------------------------------------------
IFACES=()
for path in /sys/class/net/*; do
  name="$(basename "$path")"
  [[ "$name" == "lo" ]] && continue
  IFACES+=("$name")
done
if [[ ${#IFACES[@]} -eq 0 ]]; then
  echo "ERROR: no network interface found."
  exit 1
elif [[ ${#IFACES[@]} -eq 1 ]]; then
  IFACE="${IFACES[0]}"
  echo "Network interface found: $IFACE"
else
  echo "Several network interfaces found:"
  select choice in "${IFACES[@]}"; do
    if [[ -n "${choice:-}" ]]; then
      IFACE="$choice"
      break
    fi
    echo "Please pick a valid number."
  done
fi
echo

# --- 2. DHCP or static IP -----------------------------------------------------
echo "How should '$IFACE' be configured?"
echo "  1) DHCP (assigned automatically by the router)"
echo "  2) Static IP address"
MODE=""
while [[ -z "$MODE" ]]; do
  read -r -p "Selection [1/2]: " reply
  case "$reply" in
    1) MODE="dhcp" ;;
    2) MODE="static" ;;
    *) echo "    Please enter 1 or 2." ;;
  esac
done
echo

if [[ "$MODE" == "static" ]]; then
  IP_ADDR=$(ask_ipv4 "IP address (e.g. 192.168.1.50): " "yes")

  while true; do
    read -r -p "Subnet mask or prefix (e.g. 255.255.255.0 or 24): " MASK_INPUT
    if PREFIX=$(netmask_to_prefix "$MASK_INPUT"); then
      break
    fi
    echo "    Invalid subnet mask/prefix, please try again."
  done

  GATEWAY=$(ask_ipv4 "Gateway (e.g. 192.168.1.1): " "yes")
  DNS1=$(ask_ipv4 "DNS server (e.g. 1.1.1.1): " "yes")
  DNS2=$(ask_ipv4 "Alternative DNS server (optional, press Enter to skip): " "no")

  echo
  echo "==> Summary of the new configuration"
  echo "    Interface:       $IFACE"
  echo "    Mode:            static IP"
  echo "    IP address:      $IP_ADDR/$PREFIX"
  echo "    Gateway:         $GATEWAY"
  if [[ -n "$DNS2" ]]; then
    echo "    DNS servers:     $DNS1, $DNS2"
  else
    echo "    DNS server:      $DNS1"
  fi
else
  echo "==> Summary of the new configuration"
  echo "    Interface:       $IFACE"
  echo "    Mode:            DHCP"
fi

echo
echo "IMPORTANT: the new configuration is first applied ON TRIAL for"
echo "${NETPLAN_TRY_TIMEOUT} seconds (netplan try):"
echo "  - If THIS session stays reachable: press ENTER in exactly this window"
echo "    as soon as netplan asks, to make the change permanent."
echo "  - If the SSH connection drops: do nothing. After ${NETPLAN_TRY_TIMEOUT}s"
echo "    netplan restores the old, working configuration automatically -"
echo "    then reconnect using the OLD IP address and start the script again"
echo "    if needed."
read -r -p "Continue? [y/N]: " CONFIRM
case "$CONFIRM" in
  y|Y|j|J) ;;
  *) echo "Aborted, nothing has been changed."; exit 0 ;;
esac

# --- 3. Move competing netplan files aside ----------------------------------
# Netplan applies ALL *.yaml files in /etc/netplan/ together. Only our own file
# should manage the interface - everything else (e.g. the 50-cloud-init.yaml
# generated by cloud-init) is moved to a backup. The names are remembered so
# they can be restored exactly if 'netplan try' is rejected.
mkdir -p "$BACKUP_DIR"
MOVED_FILES=()
shopt -s nullglob
for f in "$NETPLAN_DIR"/*.yaml; do
  [[ "$f" == "$OUR_FILE" ]] && continue
  MOVED_FILES+=("$(basename "$f")")
  mv "$f" "$BACKUP_DIR/"
done
shopt -u nullglob

# Back up the previous content of OUR_FILE (if any) - restored only when
# 'netplan try' is rejected.
OUR_FILE_PREV=""
if [[ -f "$OUR_FILE" ]]; then
  OUR_FILE_PREV="$(mktemp)"
  cp "$OUR_FILE" "$OUR_FILE_PREV"
fi

# cloud-init must never overwrite the network configuration again
# (e.g. after cloning the VM or running 'cloud-init clean').
mkdir -p "$(dirname "$CLOUD_INIT_DISABLE_FILE")"
cat > "$CLOUD_INIT_DISABLE_FILE" <<'EOF'
network: {config: disabled}
EOF

# --- 4. Write the netplan configuration ---------------------------------------
if [[ "$MODE" == "static" ]]; then
  if [[ -n "$DNS2" ]]; then
    NAMESERVERS="[$DNS1, $DNS2]"
  else
    NAMESERVERS="[$DNS1]"
  fi
  cat > "$OUR_FILE" <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: false
      addresses:
        - $IP_ADDR/$PREFIX
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: $NAMESERVERS
EOF
else
  cat > "$OUR_FILE" <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: true
EOF
fi
chmod 600 "$OUR_FILE"

echo
echo "==> Applying the configuration on trial (netplan try, timeout ${NETPLAN_TRY_TIMEOUT}s) ..."
echo "    If this session stays reachable: press ENTER as soon as you are asked."
netplan generate
set +e
netplan try --timeout "$NETPLAN_TRY_TIMEOUT"
TRY_STATUS=$?
set -e

if [[ "$TRY_STATUS" -ne 0 ]]; then
  echo
  echo "============================================================"
  echo " Timeout reached or aborted - NOTHING has been changed"
  echo " permanently. netplan has already restored the previous"
  echo " network connection automatically."
  echo "============================================================"
  echo "==> Restoring the previous configuration files ..."
  if [[ -n "$OUR_FILE_PREV" ]]; then
    cp "$OUR_FILE_PREV" "$OUR_FILE"
  else
    rm -f "$OUR_FILE"
  fi
  for name in "${MOVED_FILES[@]}"; do
    mv "$BACKUP_DIR/$name" "$NETPLAN_DIR/$name"
  done
  rm -f "$OUR_FILE_PREV"
  netplan generate
  netplan apply
  echo "Done - everything is as it was. Try again if needed."
  exit 1
fi

rm -f "$OUR_FILE_PREV"
echo "==> Confirmed - the configuration is now permanent."

# --- 5. Show the values that are actually active ------------------------------
echo "    Waiting a moment until the configuration is live ..."
sleep 5

ACTIVE_IP=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n1)
ACTIVE_GW=$(ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3}' | head -n1)
if command -v resolvectl >/dev/null 2>&1; then
  ACTIVE_DNS=$(resolvectl dns "$IFACE" 2>/dev/null | sed "s#^.*: ##")
else
  ACTIVE_DNS=$(grep -h '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | paste -sd ', ' -)
fi

echo
echo "============================================================"
echo " Network configuration applied."
echo "------------------------------------------------------------"
echo " Interface:   $IFACE"
echo " IP address:  ${ACTIVE_IP:-<no IP received>}"
echo " Gateway:     ${ACTIVE_GW:-<no gateway>}"
echo " DNS server:  ${ACTIVE_DNS:-<no DNS>}"
echo "============================================================"
if [[ -z "$ACTIVE_IP" ]]; then
  echo "Note: no IP address detected yet. With DHCP the lease can take a few"
  echo "seconds - check the status with:"
  echo "  ip -4 addr show dev $IFACE"
fi
