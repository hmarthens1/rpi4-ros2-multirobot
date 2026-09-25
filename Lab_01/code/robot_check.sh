#!/bin/bash
# =============================================================================
# robot_check.sh - What can this robot's Raspberry Pi 4 do right now?
# =============================================================================
# Read-only. Changes nothing on the Pi. Run it on each robot:
#
#   - at the end of Lab 01: is this Pi ready for ROS 2 Humble?
#   - at the end of Lab 02: is ROS 2 installed and set up for the fleet?
#   - any time later: after adding a lidar, an IMU or a camera
#
# It prints PASS / WARN / FAIL / INFO on screen, and writes a full report
# (the summary plus the raw output of every check) to:
#
#   ~/robot_report_<hostname>_<date>.txt
#
# Copy the three reports back to your laptop to compare the robots:
#   scp ubuntu@192.168.0.11:'robot_report_*' .
#
# USAGE
#   sudo bash robot_check.sh     # recommended: sudo lets it read the power
#                                # flags, scan I2C and time the SD card
#   bash robot_check.sh          # also works; a few checks are skipped
#
# Expansion board: the Hiwonder "RaspberryPi-Adapter-4chMotorDrive V3.x".
# Its pin map (from the schematic) is in BOARD_PINS below.
# =============================================================================

set -u

REAL_USER=${SUDO_USER:-$(id -un)}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
HOST=$(hostname)
STAMP=$(date +%Y%m%d-%H%M)
REPORT="$REAL_HOME/robot_report_${HOST}_${STAMP}.txt"
SUMMARY=$(mktemp); DETAIL=$(mktemp)
trap 'rm -f "$SUMMARY" "$DETAIL"' EXIT

ROS_DISTRO_WANTED=humble
CONFIG_TXT=/boot/firmware/config.txt
CMDLINE_TXT=/boot/firmware/cmdline.txt

# BCM GPIO -> "header pin: what the expansion board connects to it"
declare -A BOARD_PINS=(
  [2]="pin 3:  I2C SDA  -> board MCU (motors, PWM servos, battery ADC) + ports P7/P8/P9"
  [3]="pin 5:  I2C SCL  -> board MCU + ports P7/P8/P9"
  [4]="pin 7:  RX_CON   -> 74HC126 enable, bus-servo receive"
  [27]="pin 13: TX_CON   -> 74HC126 enable, bus-servo transmit"
  [14]="pin 8:  UART TXD -> bus-servo buffer + port P12"
  [15]="pin 10: UART RXD -> bus-servo buffer + port P12"
  [6]="pin 31: Buzzer   (via transistor Q1)"
  [12]="pin 32: RGB      -> 2x WS2812 LEDs"
  [13]="pin 33: Key1     (button S2 to GND, needs pull-up)"
  [23]="pin 16: Key2     (button S3 to GND, needs pull-up)"
  [16]="pin 36: LED1     (active low)"
  [26]="pin 37: LED2     (active low)"
  [22]="pin 15: GPIO22   -> port P10"
  [24]="pin 18: GPIO24   -> port P10"
  [8]="pin 24: GPIO8    -> port P11"
  [7]="pin 26: GPIO7    -> port P11"
)

PASS=0; WARNS=0; FAILS=0
log()     { echo "$*" >> "$SUMMARY"; }
pass()    { echo -e "  \033[1;32mPASS\033[0m  $*"; log "  PASS  $*"; PASS=$((PASS+1)); }
warn()    { echo -e "  \033[1;33mWARN\033[0m  $*"; log "  WARN  $*"; WARNS=$((WARNS+1)); }
fail()    { echo -e "  \033[1;31mFAIL\033[0m  $*"; log "  FAIL  $*"; FAILS=$((FAILS+1)); }
info()    { echo -e "  \033[1;34mINFO\033[0m  $*"; log "  INFO  $*"; }
section() { echo -e "\n\033[1;36m$*\033[0m"; log ""; log "$*"; }
# detail "title" "shell command" - runs the command, saves its output in the report only
detail()  { { echo; echo "===== $1"; echo "\$ $2"; timeout 30 bash -c "$2" 2>&1; } >> "$DETAIL"; }
have()    { command -v "$1" >/dev/null 2>&1; }
in_group() { id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }

echo -e "\033[1mrobot_check.sh on $HOST ($(date '+%Y-%m-%d %H:%M'))\033[0m"
[ "$IS_ROOT" -eq 1 ] || echo "  (not run with sudo: power flags, I2C scan and SD speed may be skipped)"

# -----------------------------------------------------------------------------
section "Identity"
MODEL=$( { tr -d '\0' < /proc/device-tree/model; } 2>/dev/null)
[[ "$MODEL" == *"Raspberry Pi 4"* ]] && pass "$MODEL" || warn "Model is '${MODEL:-unknown}' - expected a Raspberry Pi 4"
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
pass "RAM: ${RAM_MB} MB, $(nproc) CPU cores"
case "$HOST" in
  ubuntu|raspberrypi) warn "Hostname is still '$HOST' - give each robot its own name (Lab 01, Part 2.1)" ;;
  *) if [[ "$HOST" =~ ^[a-z][a-z0-9]*$ ]]; then
       pass "Hostname: $HOST (also valid as a ROS namespace: /$HOST)"
     else
       info "Hostname: $HOST - has characters a ROS namespace can't use; you will need a separate namespace, e.g. robot01"
     fi ;;
esac
detail "Model / revision / serial" "tr -d '\0' < /proc/device-tree/model; echo; grep -E '^(Revision|Serial|Model)' /proc/cpuinfo"
detail "CPU" "lscpu; echo; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null"

# -----------------------------------------------------------------------------
section "Power and temperature"
# get_throttled bits: 0 under-voltage now, 1 freq capped now, 2 throttled now,
# 3 soft temp limit now, 16-19 = the same things "has happened since boot".
THR=""
if have vcgencmd; then
  THR=$(vcgencmd get_throttled 2>/dev/null | sed -n 's/^throttled=//p')
fi
if [ -z "$THR" ] && [ -r /sys/devices/platform/soc/soc:firmware/get_throttled ]; then
  THR=$(cat /sys/devices/platform/soc/soc:firmware/get_throttled 2>/dev/null)
fi
if [ -n "$THR" ]; then
  T=$((16#${THR#0x}))
  if [ "$T" -eq 0 ]; then
    pass "Power OK: no under-voltage or throttling since boot (get_throttled=$THR)"
  else
    (( T & 0x1 ))     && fail "UNDER-VOLTAGE NOW - the 5 V supply (battery DC-DC or USB-C) is too weak"
    (( T & 0x10000 )) && ! (( T & 0x1 )) && warn "Under-voltage happened since boot - check the battery and the 5 V supply"
    (( T & 0x6 ))     && warn "CPU is throttled / frequency-capped right now"
    (( T & 0x60000 )) && ! (( T & 0x6 )) && warn "CPU was throttled since boot (heat or power)"
    (( T & 0x8 ))     && warn "Soft temperature limit active - add a heatsink or fan"
    info "get_throttled=$THR"
  fi
else
  warn "Can't read the power flags - run with sudo, or: sudo apt install libraspberrypi-bin"
fi
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
  TEMP_C=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
  if   [ "$TEMP_C" -ge 80 ]; then fail "CPU temperature ${TEMP_C} C - it throttles at 80 C"
  elif [ "$TEMP_C" -ge 70 ]; then warn "CPU temperature ${TEMP_C} C - warm, a heatsink or fan will help under load"
  else pass "CPU temperature ${TEMP_C} C"; fi
fi
detail "vcgencmd (firmware, clocks, volts)" "have() { command -v \$1 >/dev/null; }; have vcgencmd && { vcgencmd version; vcgencmd get_throttled; vcgencmd measure_volts core; vcgencmd measure_clock arm; vcgencmd bootloader_version; } || echo 'vcgencmd not installed (sudo apt install libraspberrypi-bin)'"

# -----------------------------------------------------------------------------
section "Operating system"
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "jammy" ] && pass "$PRETTY_NAME" || fail "$PRETTY_NAME - ROS 2 Humble needs Ubuntu 22.04 (jammy)"
ARCH=$(dpkg --print-architecture)
[ "$ARCH" = "arm64" ] && pass "Architecture: arm64" || fail "Architecture: $ARCH - use the 64-bit Ubuntu Server image"
info "Kernel $(uname -r), up $(uptime -p | sed 's/^up //')"
detail "OS" "cat /etc/os-release; uname -a; uptime"

# -----------------------------------------------------------------------------
section "Memory and storage"
TOTAL_MB=$(free -m | awk '/^Mem:/{m=$2} /^Swap:/{s=$2} END{print m+s}')
SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
if [ "$SWAP_MB" -gt 0 ]; then
  [ "$TOTAL_MB" -ge 4000 ] && pass "Swap: ${SWAP_MB} MB (RAM + swap = ${TOTAL_MB} MB)" \
                           || warn "Swap: ${SWAP_MB} MB, RAM + swap = ${TOTAL_MB} MB - aim for 4000+ for colcon builds"
else
  warn "No swap - run setup_swap.sh (Lab 01, Part 6)"
fi
ROOT_SRC=$(findmnt -n -o SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1)
[[ "$ROOT_SRC" == /dev/mmcblk* ]] && pass "Root filesystem on $ROOT_SRC (SD card)" || info "Root filesystem on $ROOT_SRC"
FREE_MB=$(df -m / | awk 'NR==2{print $4}')
SIZE_MB=$(df -m / | awk 'NR==2{print $2}')
[ "$FREE_MB" -ge 4000 ] && pass "Free space on /: ${FREE_MB} of ${SIZE_MB} MB" \
                        || warn "Only ${FREE_MB} MB free on / - ROS 2 plus a workspace wants 4 GB+"
if [ -r /sys/block/mmcblk0/device/name ]; then
  info "SD card: $(cat /sys/block/mmcblk0/device/name) (manufacturer id $(cat /sys/block/mmcblk0/device/manfid 2>/dev/null), made $(cat /sys/block/mmcblk0/device/date 2>/dev/null))"
fi
if [ "$IS_ROOT" -eq 1 ] && [ -n "$ROOT_DISK" ] && [ -b "/dev/$ROOT_DISK" ]; then
  # Read-only timing: 200 MB straight off the card, bypassing the cache.
  SPEED=$(timeout 60 dd if="/dev/$ROOT_DISK" of=/dev/null bs=4M count=50 iflag=direct 2>&1 | tail -n1 | awk -F', ' '{print $NF}')
  if [ -n "$SPEED" ]; then
    SPEED_NUM=$(echo "$SPEED" | awk '{print ($2=="GB/s") ? $1*1000 : $1}')
    awk -v s="$SPEED_NUM" 'BEGIN{exit !(s>=30)}' && pass "SD card read speed: $SPEED" \
      || warn "SD card read speed: $SPEED - slow; an A1/A2 card (40+ MB/s) makes installs and builds faster"
  fi
fi
detail "Memory" "free -h; echo; cat /proc/swaps"
detail "Disks" "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; echo; df -h /; echo; findmnt -n -o SOURCE,OPTIONS /; for f in name manfid oemid date; do printf '%s: ' \$f; cat /sys/block/mmcblk0/device/\$f 2>/dev/null; done"

# -----------------------------------------------------------------------------
section "Network"
for IF in eth0 wlan0; do
  ADDR=$(ip -4 -br addr show "$IF" 2>/dev/null | awk '{print $3}')
  MAC=$(cat /sys/class/net/$IF/address 2>/dev/null)
  if [ -n "$ADDR" ]; then
    pass "$IF: $ADDR (MAC $MAC)"
    if [ "$IF" = "wlan0" ]; then
      ip -4 addr show wlan0 | grep -q dynamic \
        && warn "wlan0 address comes from DHCP and can change - set a static one (Lab 01, Part 4.1)" \
        || pass "wlan0 address is static"
    fi
  elif [ -n "$MAC" ]; then
    [ "$IF" = "wlan0" ] && warn "wlan0 has no IPv4 address - the robots need Wi-Fi to talk to each other" \
                        || info "eth0 has no IPv4 address (fine: the robots use Wi-Fi)"
  else warn "$IF not found"; fi
done
if have iw && ip link show wlan0 >/dev/null 2>&1; then
  SSID=$(iw dev wlan0 link 2>/dev/null | sed -n 's/^\s*SSID: //p')
  SIG=$(iw dev wlan0 link 2>/dev/null | sed -n 's/^\s*signal: //p')
  [ -n "$SSID" ] && info "Wi-Fi: '$SSID', signal $SIG"
  PS=$(iw dev wlan0 get power_save 2>/dev/null | awk '{print $NF}')
  [ "$PS" = "on" ] && warn "Wi-Fi power saving is ON - adds latency to ROS 2 traffic between robots (Lab 01, Part 4.4)"
  [ "$PS" = "off" ] && pass "Wi-Fi power saving is off"
  REG=$(iw reg get 2>/dev/null | awk '/^country/{print $2; exit}' | tr -d ':')
  [ -n "$REG" ] && { [ "$REG" = "00" ] && warn "Wi-Fi country not set (00) - some channels are blocked" || info "Wi-Fi country: $REG"; }
elif ip link show wlan0 >/dev/null 2>&1; then
  info "Install 'iw' for Wi-Fi details: sudo apt install iw"
fi
ip link show wlan0 2>/dev/null | grep -q MULTICAST && pass "wlan0 supports multicast (ROS 2 discovery uses it)"
ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && pass "Internet reachable (ping 8.8.8.8)" || fail "No internet - check the Wi-Fi and the gateway (Lab 01, Part 4.1)"
getent hosts packages.ros.org >/dev/null 2>&1 && pass "DNS works (packages.ros.org resolves)" || fail "DNS lookup failed"
systemctl is-active --quiet avahi-daemon && pass "avahi-daemon running - $HOST.local works" || warn "avahi-daemon not running - $HOST.local will not resolve"
systemctl is-active --quiet ssh && pass "SSH server running" || fail "SSH server not running"
if have ufw && [ "$IS_ROOT" -eq 1 ]; then
  ufw status 2>/dev/null | grep -q "Status: active" && warn "ufw firewall is active - it can block ROS 2 (DDS) traffic between robots" || pass "ufw firewall inactive"
fi
detail "Addresses and routes" "ip -br addr; echo; ip -br link; echo; ip route; echo; resolvectl dns 2>/dev/null"
detail "Wi-Fi" "iw dev wlan0 link 2>/dev/null || networkctl status wlan0 2>/dev/null | head -20; cat /proc/net/wireless 2>/dev/null"
detail "netplan" "ls -l /etc/netplan/; networkctl list 2>/dev/null"

# -----------------------------------------------------------------------------
section "Time"
timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes \
  && pass "Clock synchronised: $(date '+%Y-%m-%d %H:%M %Z')" \
  || warn "Clock not NTP-synchronised: $(date '+%Y-%m-%d %H:%M %Z') - the Pi 4 has no battery clock"
detail "timedatectl" "timedatectl; timedatectl show-timesync 2>/dev/null | head"

# -----------------------------------------------------------------------------
section "Packages and locale"
if pgrep -x unattended-upgr >/dev/null || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
  warn "apt is busy (unattended-upgrades) - wait for it before installing"
else
  pass "apt is free"
fi
grep -rhsE '^(deb|Components:|Suites:)' /etc/apt/sources.list /etc/apt/sources.list.d/ | grep -q universe \
  && pass "'universe' repository enabled" || fail "'universe' not enabled - run: sudo add-apt-repository universe"
# Count what full-upgrade would really install: "apt list --upgradable" also lists
# phased updates that Ubuntu deliberately holds back for now.
UPG=$(apt-get -s -o Debug::NoLocking=1 full-upgrade 2>/dev/null | grep -c '^Inst ')
[ "$UPG" -eq 0 ] && pass "System up to date" || warn "$UPG packages can be upgraded - run: sudo apt update && sudo apt full-upgrade"
MISSING=""
for c in curl git i2cdetect gpioinfo lsusb iw vcgencmd; do have $c || MISSING="$MISSING $c"; done
[ -z "$MISSING" ] && pass "Tools installed: curl git i2c-tools gpiod usbutils iw vcgencmd" \
  || warn "Missing tools:$MISSING - run: sudo apt install -y curl git i2c-tools gpiod usbutils iw libraspberrypi-bin"
LOCALE_NOW=$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2}')
[[ "$LOCALE_NOW" == *UTF-8* || "$LOCALE_NOW" == *utf8* ]] && pass "LANG=$LOCALE_NOW" || fail "LANG=${LOCALE_NOW:-unset} - ROS 2 needs a UTF-8 locale (Lab 01, Part 7.1)"

# -----------------------------------------------------------------------------
section "ROS 2"
ROS_SETUP=/opt/ros/$ROS_DISTRO_WANTED/setup.bash
BASHRC="$REAL_HOME/.bashrc"
if [ -f "$ROS_SETUP" ]; then
  pass "ROS 2 $ROS_DISTRO_WANTED installed in /opt/ros/$ROS_DISTRO_WANTED"
  NPKG=$(bash -c "source $ROS_SETUP && ros2 pkg list 2>/dev/null | wc -l")
  info "$NPKG ROS packages available"
  bash -c "source $ROS_SETUP && ros2 pkg prefix demo_nodes_cpp" >/dev/null 2>&1 \
    && pass "demo_nodes_cpp installed (talker/listener test)" || warn "demo_nodes_cpp missing - sudo apt install ros-humble-demo-nodes-cpp ros-humble-demo-nodes-py"
  grep -qs "source $ROS_SETUP" "$BASHRC" && pass "~/.bashrc sources ROS 2" || warn "~/.bashrc doesn't source $ROS_SETUP"
  # Read the settings from ~/.bashrc itself: with sudo, this shell's environment is root's.
  rc_var() { grep -E "^\s*export $1=" "$BASHRC" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'"'"; }
  DOMAIN=$(rc_var ROS_DOMAIN_ID)
  [ -n "$DOMAIN" ] && pass "ROS_DOMAIN_ID=$DOMAIN (must be the same on all three robots and the laptop)" \
                   || warn "ROS_DOMAIN_ID not set in ~/.bashrc - the robots then share domain 0 with everyone else's ROS 2"
  RMW=$(rc_var RMW_IMPLEMENTATION)
  info "RMW: ${RMW:-default (rmw_fastrtps_cpp)}"
  [ "$(rc_var ROS_LOCALHOST_ONLY)" = "1" ] && fail "ROS_LOCALHOST_ONLY=1 in ~/.bashrc - this robot can't see the others"
  have colcon && pass "colcon installed" || warn "colcon missing - sudo apt install ros-dev-tools"
  [ -f /etc/ros/rosdep/sources.list.d/20-default.list ] && pass "rosdep initialised" || warn "rosdep not initialised - sudo rosdep init && rosdep update"
  [ -d "$REAL_HOME/ros2_ws/install" ] && pass "Workspace ~/ros2_ws has been built" || info "No built workspace at ~/ros2_ws yet"
else
  info "ROS 2 $ROS_DISTRO_WANTED not installed yet (that is Lab 02)"
fi
detail "ROS environment" "grep -n -A8 'ROS 2' '$BASHRC' 2>/dev/null; ls /opt/ros 2>/dev/null; dpkg -l 'ros-*' 2>/dev/null | awk '/^ii/{print \$2, \$3}' | head -300"

# -----------------------------------------------------------------------------
section "Expansion board interfaces (I2C, UART, GPIO)"
if [ -r "$CONFIG_TXT" ]; then
  grep -qE '^\s*dtparam=i2c_arm=on' "$CONFIG_TXT" && pass "config.txt: I2C enabled (dtparam=i2c_arm=on)" \
    || warn "config.txt: dtparam=i2c_arm=on not found - the board's MCU is on I2C"
  grep -qE '^\s*enable_uart=1' "$CONFIG_TXT" && info "config.txt: enable_uart=1 (header UART on pins 8/10)"
fi
if grep -qsE 'console=(serial0|ttyS0|ttyAMA0)' "$CMDLINE_TXT"; then
  info "Kernel serial console is on the header UART (pins 8/10). The board's bus-servo port and P12 use those pins - it must be turned off before using them (later lab)"
fi
for t in ttyS0 ttyAMA0; do
  systemctl is-active --quiet serial-getty@$t && info "A login prompt runs on /dev/$t (serial-getty@$t)"
done
[ -e /dev/serial0 ] && info "/dev/serial0 -> $(readlink -f /dev/serial0)"

if [ -e /dev/i2c-1 ]; then
  pass "I2C bus 1 present (/dev/i2c-1)"
  if have i2cdetect && { [ "$IS_ROOT" -eq 1 ] || [ -r /dev/i2c-1 -a -w /dev/i2c-1 ]; }; then
    # The board's microcontroller is at 0x7A. That is above 0x77, in the range
    # i2cdetect never scans, so ask it directly the way HiwonderSDK/Board.py
    # does: write the register number (0 = battery), then read 2 bytes as a
    # separate transfer. Some reads come back garbled, so retry a few times.
    MV=""
    for try in 1 2 3 4 5 6; do
      i2ctransfer -a -y 1 w1@0x7a 0x00 >/dev/null 2>&1 || continue
      R=$(i2ctransfer -a -y 1 r2@0x7a 2>/dev/null) || continue
      set -- $R; V=$(( ($2 << 8) | $1 ))
      [ "$V" -ge 3000 ] && [ "$V" -le 20000 ] && { MV=$V; break; }
    done
    if [ -n "$MV" ]; then
      pass "Expansion board found (MCU at 0x7A): battery $((MV/1000)).$(printf '%02d' $(((MV%1000)/10))) V"
      [ "$MV" -lt 7000 ] && warn "Battery is low ($MV mV) - charge it before driving the motors"
    else
      warn "Expansion board MCU at 0x7A didn't answer - is the board fitted and its power switch ON?"
    fi
    OTHER=$(i2cdetect -y 1 2>/dev/null | awk 'NR>1{for(i=2;i<=NF;i++) if($i!="--") printf "0x%s ", $i}')
    [ -n "$OTHER" ] && info "Other I2C devices on bus 1: $OTHER(sensors on ports P7/P8/P9)"
  else
    info "Skipped the I2C scan (needs i2c-tools and sudo or I2C permission)"
  fi
else
  fail "No /dev/i2c-1 - add dtparam=i2c_arm=on to $CONFIG_TXT and reboot"
fi
if [ -e /dev/gpiochip0 ]; then
  have gpiodetect && pass "GPIO: $(gpiodetect 2>/dev/null | head -n1)" || pass "GPIO: /dev/gpiochip0 present"
else
  fail "No /dev/gpiochip0"
fi
detail "config.txt (active lines)" "grep -vE '^\s*(#|$)' $CONFIG_TXT; echo; ls /boot/firmware/*.txt"
detail "cmdline.txt" "cat $CMDLINE_TXT"
detail "UARTs" "ls -l /dev/serial* /dev/ttyS* /dev/ttyAMA* 2>/dev/null; systemctl list-units 'serial-getty@*' --no-legend 2>/dev/null; ls /sys/class/bluetooth 2>/dev/null"
detail "I2C" "ls -l /dev/i2c-* 2>/dev/null; i2cdetect -l 2>/dev/null; echo; i2cdetect -y 1 2>/dev/null; echo; echo 'battery register (0x7A reg 0), 3 reads:'; for i in 1 2 3; do i2ctransfer -a -y 1 w1@0x7a 0x00 && i2ctransfer -a -y 1 r2@0x7a; done"
{
  echo; echo "===== GPIO lines used by the expansion board"
  for g in 2 3 4 27 14 15 6 12 13 23 16 26 22 24 8 7; do
    STATE=$(gpioinfo gpiochip0 2>/dev/null | grep -E "^\s*line\s+$g:" | sed 's/^\s*//')
    printf 'GPIO%-3s %-78s | %s\n' "$g" "${BOARD_PINS[$g]}" "${STATE:-gpioinfo not available}"
  done
} >> "$DETAIL"
detail "All GPIO lines" "gpioinfo gpiochip0 2>/dev/null"

# -----------------------------------------------------------------------------
section "USB, serial and camera devices (lidar / IMU / camera go here)"
USB_N=$(lsusb 2>/dev/null | grep -vic " hub")   # the Pi 4 has a built-in VIA USB hub
info "USB devices (not counting hubs): ${USB_N:-unknown}"; lsusb 2>/dev/null | grep -vi " hub" | while read -r l; do info "  ${l#*ID }"; done
SER=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ')
[ -n "$SER" ] && info "USB serial ports: $SER" || info "No USB serial ports (/dev/ttyUSB*, /dev/ttyACM*) yet"
[ -d /dev/serial/by-id ] && for l in /dev/serial/by-id/*; do info "  $(basename "$l") -> $(readlink -f "$l")"; done
# /dev/video10-31 are the Pi's own codec/ISP blocks (bcm2835-codec, -isp), not cameras.
VID=""
for v in /sys/class/video4linux/video*; do
  [ -e "$v/name" ] || continue
  NAME=$(cat "$v/name")
  case "$NAME" in bcm2835-codec*|bcm2835-isp*|*unicam*-embedded) continue ;; esac
  VID="$VID/dev/$(basename "$v") ($NAME) "
done
[ -n "$VID" ] && info "Cameras: $VID" || info "No cameras (/dev/video*) yet"
for DEV in /dev/i2c-1 /dev/gpiochip0 /dev/serial0 /dev/ttyUSB0 /dev/ttyACM0 /dev/video0; do
  [ -e "$DEV" ] || continue
  G=$(stat -L -c %G "$DEV")
  if [ "$DEV" = /dev/serial0 ] && [ "$G" = "tty" ]; then
    info "/dev/serial0 is owned by the login prompt on it (group tty) - freed when the serial console is turned off (later lab)"
  elif [ "$G" = "root" ]; then info "$DEV belongs to root:root - only sudo can use it"
  elif in_group "$G"; then pass "$REAL_USER can use $DEV (group $G)"
  else warn "$REAL_USER is not in group '$G' for $DEV - sudo usermod -aG $G $REAL_USER, then log in again"; fi
done
detail "lsusb" "lsusb; echo; lsusb -t"
detail "Serial and video device nodes" "ls -l /dev/serial/by-id/ /dev/ttyUSB* /dev/ttyACM* /dev/video* 2>/dev/null; for v in /sys/class/video4linux/video*; do echo \"\$(basename \$v): \$(cat \$v/name)\"; done 2>/dev/null"
detail "Groups" "id $REAL_USER"
[ "$IS_ROOT" -eq 1 ] && detail "Kernel messages: USB, serial, I2C, voltage" "dmesg | grep -iE 'usb|tty|i2c|voltage|throttl' | tail -60"

# -----------------------------------------------------------------------------
echo
echo "-----------------------------------------------------------------------"
echo "  $PASS passed, $WARNS warnings, $FAILS failed"
if [ "$FAILS" -eq 0 ]; then
  if [ -f "/opt/ros/$ROS_DISTRO_WANTED/setup.bash" ]; then
    echo -e "  \033[1;32m$HOST has ROS 2 $ROS_DISTRO_WANTED installed and nothing failed.\033[0m"
  else
    echo -e "  \033[1;32m$HOST is ready for ROS 2 Humble.\033[0m"
  fi
else
  echo -e "  \033[1;31mFix the FAIL items first.\033[0m"
fi

{
  echo "robot_check.sh report"
  echo "host: $HOST   date: $(date '+%Y-%m-%d %H:%M:%S %Z')   user: $REAL_USER   sudo: $IS_ROOT"
  echo "result: $PASS passed, $WARNS warnings, $FAILS failed"
  cat "$SUMMARY"
  echo; echo; echo "######################## DETAILS ########################"
  cat "$DETAIL"
} > "$REPORT"
[ "$IS_ROOT" -eq 1 ] && chown "$REAL_USER": "$REPORT"
echo "  Report saved: $REPORT"
MY_IP=$(ip -4 -br addr show wlan0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
echo "  Copy it to your laptop:  scp $REAL_USER@${MY_IP:-$HOST.local}:$(basename "$REPORT") ."
echo "-----------------------------------------------------------------------"
echo
[ "$FAILS" -eq 0 ]
