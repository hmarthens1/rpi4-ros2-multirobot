#!/bin/bash
# =============================================================================
# RPi4 Lab 01 - Network setup for Ubuntu Server 22.04 (netplan)
# =============================================================================
# Ubuntu Server does not use /etc/dhcpcd.conf. Networking is described in YAML
# files under /etc/netplan/ and applied with "netplan apply". On first boot,
# cloud-init writes /etc/netplan/50-cloud-init.yaml from the settings you gave
# Raspberry Pi Imager (Wi-Fi name/password).
#
# This script replaces those files with ONE file you control:
#
#   wlan0  keep | client | ap | off
#            keep   - keep the Wi-Fi network Imager set up (default)
#            client - join the Wi-Fi network given below
#            ap     - broadcast a hotspot so a laptop can connect directly
#            off    - no Wi-Fi config
#          with a static IP (default) or DHCP from the router
#   eth0   DHCP (default, for a cable to the router) or a static IP
#
# It also stops cloud-init from rewriting the network config on later boots,
# and backs up the old files so --restore can put them back.
#
# USAGE
#   sudo bash setup_network.sh            # apply the SETTINGS below
#   sudo bash setup_network.sh --show     # print the current netplan config
#   sudo bash setup_network.sh --restore  # put the previous config back
#
# Run this ON THE ROBOT. If you are connected over SSH and the IP of that link
# changes, your session drops - reconnect to the new address.
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
WIFI_MODE="keep"                  # "keep" | "client" | "ap" | "off"
WIFI_SSID=""                      # client mode: network to join
WIFI_PASSWORD=""                  # client mode: its password

WIFI_IPV4="static"                # keep/client modes: "static" or "dhcp"
# Same first three numbers as the router; the last one is 10 + robot number:
#   robot01 -> .11   robot02 -> .12   robot03 -> .13
# Pick addresses OUTSIDE the router's DHCP range (Lab 01, Part 4.1).
WIFI_ADDRESS="192.168.0.11/24"
WIFI_GATEWAY="192.168.0.1"        # the router
DNS_SERVERS="192.168.0.1,8.8.8.8" # the router first, then a public server

ETH_MODE="dhcp"                   # "dhcp" or "static" (optional cable)
ETH_ADDRESS="192.168.1.11/24"     # static only: must NOT be in the Wi-Fi subnet
ETH_GATEWAY=""                    # static only: leave empty for no default route
AP_SSID="$(hostname)"             # ap mode: hotspot name (default = hostname)
AP_PASSWORD="changeme123"         # ap mode: at least 8 characters
# -----------------------------------------------------------------------------

set -u
NETPLAN_DIR=/etc/netplan
OUT_FILE=$NETPLAN_DIR/01-robot-network.yaml
BACKUP_ROOT=/etc/netplan-backups
CLOUD_CFG=/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
warn() { echo -e "    \033[1;33m!!\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

if [ "${1:-}" = "--show" ]; then
  for f in "$NETPLAN_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    echo -e "\n--- $f"; sudo cat "$f" 2>/dev/null || cat "$f"
  done
  echo; ip -br addr; echo; exit 0
fi

[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"
command -v netplan >/dev/null || die "netplan not found - is this Ubuntu Server?"

# ----------------------------- RESTORE ---------------------------------------
if [ "${1:-}" = "--restore" ]; then
  LAST=$(ls -1d "$BACKUP_ROOT"/* 2>/dev/null | tail -n1)
  [ -n "$LAST" ] || die "No backup found in $BACKUP_ROOT"
  say "Restoring netplan config from $LAST"
  rm -f "$NETPLAN_DIR"/*.yaml
  cp -a "$LAST"/*.yaml "$NETPLAN_DIR"/ 2>/dev/null
  rm -f "$CLOUD_CFG"
  netplan generate || die "Restored config does not validate - check $NETPLAN_DIR"
  netplan apply
  ok "restored (cloud-init network config re-enabled)"
  exit 0
fi

# ----------------------------- VALIDATE SETTINGS -----------------------------
case "$ETH_MODE"  in static|dhcp) ;; *) die "ETH_MODE must be static or dhcp" ;; esac
case "$WIFI_MODE" in keep|client|ap|off) ;; *) die "WIFI_MODE must be keep, client, ap or off" ;; esac
case "$WIFI_IPV4" in static|dhcp) ;; *) die "WIFI_IPV4 must be static or dhcp" ;; esac
if [ "$ETH_MODE" = "static" ]; then
  [[ "$ETH_ADDRESS" == */* ]] || die "ETH_ADDRESS needs a prefix, e.g. 192.168.1.11/24"
fi
WIFI_STATIC=0
if [ "$WIFI_IPV4" = "static" ] && { [ "$WIFI_MODE" = "keep" ] || [ "$WIFI_MODE" = "client" ]; }; then
  WIFI_STATIC=1
  [[ "$WIFI_ADDRESS" == */* ]] || die "WIFI_ADDRESS needs a prefix, e.g. 192.168.0.11/24"
  [ -n "$WIFI_GATEWAY" ] || die "WIFI_GATEWAY is empty - use the router's address"
  # Is another device already using this address? (Our own current address is fine.)
  NEW_IP=${WIFI_ADDRESS%/*}
  if ! ip -4 -o addr show | grep -q " $NEW_IP/"; then
    ping -c2 -W1 "$NEW_IP" >/dev/null 2>&1 \
      && die "$NEW_IP already answers on the network - another device has it. Pick a different WIFI_ADDRESS."
  fi
fi
if [ "$WIFI_MODE" = "client" ]; then
  [ -n "$WIFI_SSID" ] || die "WIFI_MODE=client needs WIFI_SSID"
fi
if [ "$WIFI_MODE" = "ap" ]; then
  [ ${#AP_PASSWORD} -ge 8 ] || die "AP_PASSWORD must be at least 8 characters"
  ip link show wlan0 >/dev/null 2>&1 || die "No wlan0 - is Wi-Fi turned off (dtoverlay=disable-wifi in config.txt)?"
fi
python3 -c "import yaml" 2>/dev/null || die "python3-yaml is missing:  sudo apt install python3-yaml"

# ----------------------------- AP NEEDS NETWORKMANAGER -----------------------
# netplan can only build a hotspot through NetworkManager. The default Server
# renderer (systemd-networkd) cannot. NetworkManager's "shared" mode also runs
# the DHCP server for the laptops that join, so nothing else is needed.
if [ "$WIFI_MODE" = "ap" ] && ! command -v nmcli >/dev/null; then
  say "Installing NetworkManager (needed for hotspot mode)"
  apt-get update -q && apt-get install -y network-manager dnsmasq-base \
    || die "Could not install network-manager. The Pi needs internet for this step."
  ok "installed"
fi

# ----------------------------- BACKUP ----------------------------------------
say "Backing up the current netplan files"
BACKUP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -a "$NETPLAN_DIR"/*.yaml "$BACKUP"/ 2>/dev/null
ok "$BACKUP"

# ----------------------------- BUILD THE NEW CONFIG --------------------------
say "Writing $OUT_FILE"
export ETH_MODE ETH_ADDRESS ETH_GATEWAY DNS_SERVERS WIFI_MODE WIFI_STATIC WIFI_ADDRESS WIFI_GATEWAY WIFI_SSID WIFI_PASSWORD AP_SSID AP_PASSWORD
NEW_YAML=$(python3 - "$BACKUP" <<'PY'
import glob, os, sys, yaml
e = os.environ
backup = sys.argv[1]

# Existing wlan0 settings, so "keep" preserves what Imager wrote.
old_wifi = {}
for f in sorted(glob.glob(os.path.join(backup, "*.yaml"))):
    try:
        data = yaml.safe_load(open(f)) or {}
    except Exception:
        continue
    for name, cfg in ((data.get("network") or {}).get("wifis") or {}).items():
        old_wifi[name] = cfg

dns = [d.strip() for d in e["DNS_SERVERS"].split(",") if d.strip()]
net = {"version": 2, "renderer": "networkd", "ethernets": {}}

eth = {"optional": True}           # do not stall boot when the cable is out
if e["ETH_MODE"] == "static":
    eth.update({"dhcp4": False, "addresses": [e["ETH_ADDRESS"]]})
    if e["ETH_GATEWAY"]:
        eth["routes"] = [{"to": "default", "via": e["ETH_GATEWAY"], "metric": 700}]
else:
    eth["dhcp4"] = True
net["ethernets"]["eth0"] = eth

mode = e["WIFI_MODE"]
if mode == "keep":
    if old_wifi:
        net["wifis"] = old_wifi
elif mode == "client":
    ap = {"password": e["WIFI_PASSWORD"]} if e["WIFI_PASSWORD"] else {}
    net["wifis"] = {"wlan0": {"dhcp4": True, "optional": True,
                              "access-points": {e["WIFI_SSID"]: ap}}}
elif mode == "ap":
    net["wifis"] = {"wlan0": {"renderer": "NetworkManager", "optional": True,
                              "access-points": {e["AP_SSID"]: {
                                  "password": e["AP_PASSWORD"], "mode": "ap"}}}}

if e["WIFI_STATIC"] == "1":
    if not net.get("wifis"):
        sys.exit("WIFI_MODE=keep, but there is no Wi-Fi network to keep. Use WIFI_MODE=client.")
    for cfg in net["wifis"].values():
        for k in ("dhcp4", "addresses", "routes", "gateway4", "nameservers"):
            cfg.pop(k, None)
        cfg.update({"dhcp4": False,
                    "addresses": [e["WIFI_ADDRESS"]],
                    "routes": [{"to": "default", "via": e["WIFI_GATEWAY"]}],
                    "nameservers": {"addresses": dns}})

print(yaml.safe_dump({"network": net}, default_flow_style=False, sort_keys=False))
PY
) || die "Could not build the new config"

rm -f "$NETPLAN_DIR"/*.yaml
printf '# Written by setup_network.sh - edit the script and re-run it instead.\n%s\n' "$NEW_YAML" > "$OUT_FILE"
chmod 600 "$OUT_FILE"
ok "written (mode 600 - netplan warns about readable files)"

if ! netplan generate; then
  warn "The new config does not validate - restoring the backup"
  rm -f "$NETPLAN_DIR"/*.yaml; cp -a "$BACKUP"/*.yaml "$NETPLAN_DIR"/ 2>/dev/null
  die "Nothing was changed. Check the SETTINGS block."
fi
ok "validated"

# ----------------------------- STOP CLOUD-INIT OVERWRITING IT ----------------
mkdir -p "$(dirname "$CLOUD_CFG")"
echo "network: {config: disabled}" > "$CLOUD_CFG"
ok "cloud-init will no longer rewrite the network config"

# ----------------------------- APPLY -----------------------------------------
ME=$(logname 2>/dev/null || echo ubuntu)
if [ "$WIFI_STATIC" = "1" ]; then
  echo
  echo -e "\033[1;33m  Over SSH on Wi-Fi, this session freezes or drops now. That is expected.\033[0m"
  echo -e "\033[1;33m  Wait ~20 s, then reconnect:  ssh $ME@${WIFI_ADDRESS%/*}\033[0m"
fi
say "Applying"
# Keep going if the SSH session drops: the new config must be applied in full.
trap '' HUP
nohup netplan apply > "$BACKUP/apply.log" 2>&1
sleep 5
ok "applied (log: $BACKUP/apply.log)"

say "Result"
cat "$OUT_FILE"
echo
ip -br addr
echo
[ "$WIFI_STATIC" = "1" ] && echo "wlan0 is ${WIFI_ADDRESS%/*}   ->  ssh $ME@${WIFI_ADDRESS%/*}"
[ "$ETH_MODE" = "static" ] && echo "eth0 is ${ETH_ADDRESS%/*}"
[ "$WIFI_MODE" = "ap" ] && echo "Hotspot '$AP_SSID' is up. Join it, then:  ssh $ME@10.42.0.1"
echo "Test internet with:  ping -c3 8.8.8.8"
echo "Undo with:           sudo bash $0 --restore"
echo
