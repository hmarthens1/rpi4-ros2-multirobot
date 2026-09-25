#!/bin/bash
# =============================================================================
# RPi4 Lab 01 - Share your laptop's internet with the Pi over Ethernet  (LINUX)
# =============================================================================
# Your laptop is on Wi-Fi. The Pi is plugged into your laptop's Ethernet port.
# This makes the laptop route and NAT the Pi's traffic out over the Wi-Fi.
#
#   [ Pi 4 ] --ethernet--> [ your laptop ] --wifi--> [ internet ]
#
# USAGE
#   sudo bash share_internet_linux.sh          # turn sharing on
#   sudo bash share_internet_linux.sh --undo   # turn it off
#   bash share_internet_linux.sh --list        # just show your interfaces
#
# Run this in a REAL TERMINAL WINDOW - it needs to prompt for your password.
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
# Leave WAN_IF / LAN_IF empty to auto-detect. Use --list to see the names.
WAN_IF=""                    # interface WITH internet   (Wi-Fi, e.g. wlp3s0)
LAN_IF=""                    # interface TO THE Pi      (Ethernet, e.g. enp0s31f6)
HOST_IP="192.168.0.1"        # this laptop's address on the Pi link = the Pi's GATEWAY
LAN_SUBNET="192.168.0.0/24"  # must match the Pi's static IP range
SET_HOST_IP=1                # 1 = also assign HOST_IP to LAN_IF
# -----------------------------------------------------------------------------

set -u
say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

if [ "${1:-}" = "--list" ]; then
  echo; echo "Interfaces on this laptop:"; echo
  ip -br addr | awk '{printf "  %-16s %-8s %s\n", $1, $2, $3}'
  echo; echo "Default route (this is your internet interface):"
  ip route | grep '^default'
  echo; exit 0
fi

[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"

# Auto-detect if not set above.
[ -z "$WAN_IF" ] && WAN_IF=$(ip route | awk '/^default/{print $5; exit}')
[ -z "$LAN_IF" ] && LAN_IF=$(ip -br link | awk '$1 ~ /^(en|eth)/ && $2 == "UP" {print $1; exit}')
[ -n "$WAN_IF" ] || die "Could not detect the internet interface. Set WAN_IF at the top. (--list to see names)"
[ -n "$LAN_IF" ] || die "Could not detect the Ethernet interface. Is the cable plugged in? Set LAN_IF at the top."
[ "$WAN_IF" = "$LAN_IF" ] && die "WAN_IF and LAN_IF are the same ($WAN_IF). Set them manually at the top."
# Catch typos: rules for a non-existent interface are accepted silently and do nothing.
for IF in "$WAN_IF" "$LAN_IF"; do
  ip link show dev "$IF" >/dev/null 2>&1 \
    || die "No interface named '$IF'. Check the spelling at the top, or run:  bash $0 --list"
done

say "Configuration"
echo "    internet via : $WAN_IF"
echo "    pi on        : $LAN_IF  ($HOST_IP)"
echo "    pi subnet    : $LAN_SUBNET"

# ----------------------------- UNDO ------------------------------------------
if [ "${1:-}" = "--undo" ]; then
  say "Removing sharing"
  iptables -t nat -D POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null
  iptables -D FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null
  iptables -D FORWARD -i "$WAN_IF" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
  sysctl -w net.ipv4.ip_forward=0 >/dev/null
  ok "Sharing disabled"
  exit 0
fi

# ----------------------------- ENABLE ----------------------------------------
say "Enabling IP forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null && ok "done"

if [ "$SET_HOST_IP" -eq 1 ]; then
  say "Assigning $HOST_IP to $LAN_IF"
  ip addr show dev "$LAN_IF" | grep -q "inet $HOST_IP" \
    && ok "already set" \
    || { ip addr add "$HOST_IP/${LAN_SUBNET##*/}" dev "$LAN_IF" \
           && ip link set "$LAN_IF" up && ok "set" \
           || die "Could not assign $HOST_IP to $LAN_IF"; }
fi

say "Adding NAT and forwarding rules"
# -C tests for an existing rule, so re-running this script is harmless.
iptables -t nat -C POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IF" -j MASQUERADE
# Insert at the TOP: Docker sets the FORWARD policy to DROP and appends its own
# rules, so an appended rule here would never be reached.
iptables -C FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
iptables -C FORWARD -i "$WAN_IF" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i "$WAN_IF" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ok "rules active"

# ufw, if running, drops forwarded traffic regardless of the rules above.
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi "^Status: active"; then
  say "ufw is active - allowing forwarding"
  sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
  ufw route allow in on "$LAN_IF" out on "$WAN_IF" >/dev/null 2>&1
  ufw reload >/dev/null 2>&1 && ok "ufw updated"
fi

cat <<SUMMARY

-----------------------------------------------------------------------
 Internet sharing is ON.

 On the Pi, give eth0 a static IP that uses this laptop as gateway.
 Edit the SETTINGS block of setup_network.sh:

     ETH_ADDRESS="${HOST_IP%.*}.11/24"    # robot01 = .11, robot02 = .12, robot03 = .13
     ETH_GATEWAY="$HOST_IP"

 then run:   sudo bash setup_network.sh
 and test:   ping -c3 8.8.8.8

 NOTE: these rules are cleared when your laptop reboots. Re-run this
 script, or make them permanent with:
   sudo apt install iptables-persistent && sudo netfilter-persistent save
-----------------------------------------------------------------------

SUMMARY
