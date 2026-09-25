#!/bin/bash
# =============================================================================
# RPi4 Lab 01 - Share your Mac's internet with the Pi over Ethernet  (macOS)
# =============================================================================
#   [ Pi 4 ] --ethernet--> [ your Mac ] --wifi--> [ internet ]
#
# USAGE
#   sudo bash share_internet_macos.sh          # turn sharing on
#   sudo bash share_internet_macos.sh --undo   # turn it off
#   bash share_internet_macos.sh --list        # show your interface names
#
# Run this in Terminal (Applications > Utilities > Terminal).
#
# SIMPLER ALTERNATIVE: System Settings > General > Sharing > Internet Sharing.
# The GUI always hands out 192.168.2.x addresses and you cannot change that.
# Use this script when you need the Pi on a specific subnet instead.
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
# Run with --list to find these. On most laptops Wi-Fi is en0 and a USB-C
# Ethernet adapter shows up as en5, en6 or en7.
WAN_IF="en0"                 # interface WITH internet  (Wi-Fi)
LAN_IF="en5"                 # interface TO THE Pi      (Ethernet adapter)
HOST_IP="192.168.0.1"        # this Mac's address on the Pi link = the Pi's GATEWAY
NETMASK="255.255.255.0"
LAN_SUBNET="192.168.0.0/24"  # must match the Pi's static IP range
SET_HOST_IP=1                # 1 = also assign HOST_IP to LAN_IF
# -----------------------------------------------------------------------------

set -u
ANCHOR=/etc/pf.anchors/robot-share
PFCONF=/etc/pf-robot-share.conf

say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

if [ "${1:-}" = "--list" ]; then
  echo; echo "Hardware ports on this Mac:"; echo
  networksetup -listallhardwareports | sed 's/^/  /'
  echo "Active interfaces:"; echo
  ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet /{print "  " iface " " $2}'
  echo; echo "Default route (your internet interface):"
  route -n get default 2>/dev/null | awk '/interface:/{print "  " $2}'
  echo; exit 0
fi

[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"
[ "$WAN_IF" = "$LAN_IF" ] && die "WAN_IF and LAN_IF are the same ($WAN_IF). Fix them at the top."
ifconfig "$WAN_IF" >/dev/null 2>&1 || die "Interface '$WAN_IF' not found. Run: bash $0 --list"
ifconfig "$LAN_IF" >/dev/null 2>&1 || die "Interface '$LAN_IF' not found. Is the adapter plugged in? Run: bash $0 --list"

say "Configuration"
echo "    internet via : $WAN_IF"
echo "    pi on        : $LAN_IF  ($HOST_IP)"
echo "    pi subnet    : $LAN_SUBNET"

# ----------------------------- UNDO ------------------------------------------
if [ "${1:-}" = "--undo" ]; then
  say "Removing sharing"
  pfctl -d 2>/dev/null
  pfctl -f /etc/pf.conf 2>/dev/null       # restore the stock ruleset
  rm -f "$ANCHOR" "$PFCONF"
  sysctl -w net.inet.ip.forwarding=0 >/dev/null
  ok "Sharing disabled"
  exit 0
fi

# ----------------------------- ENABLE ----------------------------------------
say "Enabling IP forwarding"
sysctl -w net.inet.ip.forwarding=1 >/dev/null && ok "done"

if [ "$SET_HOST_IP" -eq 1 ]; then
  say "Assigning $HOST_IP to $LAN_IF"
  ifconfig "$LAN_IF" inet "$HOST_IP" netmask "$NETMASK" up && ok "set"
fi

say "Writing the pf NAT rule"
echo "nat on $WAN_IF from $LAN_SUBNET to any -> ($WAN_IF)" > "$ANCHOR"
ok "$ANCHOR"

# pf requires a strict rule order: options, normalization, queueing,
# translation (nat/rdr), then filtering. Appending our nat-anchor to the end of
# /etc/pf.conf would put a translation rule after a filter rule and pf would
# refuse to load it. So we write a complete ruleset with the Apple anchors kept
# in their correct positions and our anchor inserted in the translation block.
cat > "$PFCONF" <<PFRULES
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
nat-anchor "robot-share"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
load anchor "robot-share" from "$ANCHOR"
PFRULES

say "Loading the firewall ruleset"
pfctl -q -d 2>/dev/null
pfctl -q -e -f "$PFCONF" 2>/dev/null || die "pfctl failed to load the ruleset.
       Check it by hand with:  sudo pfctl -n -f $PFCONF"
ok "pf enabled with NAT"

pfctl -s nat 2>/dev/null | grep -q "nat on $WAN_IF" \
  && ok "NAT rule confirmed active" \
  || echo "    !!  Could not confirm the NAT rule - check: sudo pfctl -s nat"

cat <<SUMMARY

-----------------------------------------------------------------------
 Internet sharing is ON.

 On the Pi, give eth0 a static IP that uses this laptop as gateway.
 Edit the SETTINGS block of setup_network.sh:

     ETH_ADDRESS="${HOST_IP%.*}.11/24"    # robot01 = .11, robot02 = .12, robot03 = .13
     ETH_GATEWAY="$HOST_IP"

 then run:   sudo bash setup_network.sh
 and test:   ping -c3 8.8.8.8

 NOTE: this is cleared when your Mac reboots - re-run the script.
 Turn it off again with:  sudo bash $0 --undo
-----------------------------------------------------------------------

SUMMARY
