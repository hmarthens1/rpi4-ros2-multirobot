#!/bin/bash
# =============================================================================
# RPi4 Lab 03 - Install the Hiwonder expansion-board SDK on Ubuntu 22.04
# =============================================================================
# The SDK (MasterPi/HiwonderSDK: Board.py, mecanum.py, Sonar.py, demos) comes
# from the course workspace repo. Board.py expects it at
# ~/mse112-ws-student/MasterPi, so it is cloned exactly there.
#
#   1. apt:  git, pip, a C compiler (rpi_ws281x builds from source),
#            python3-yaml, python3-rpi.gpio
#   2. pip:  smbus2 (I2C), rpi_ws281x (the two RGB LEDs)
#   3. git:  clone or update ~/mse112-ws-student
#   4. check that everything imports
#
# Safe to run again. Run board_test.py afterwards to check the board itself.
#
# USAGE
#   sudo bash install_hiwonder_sdk.sh
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
WS_REPO="https://github.com/hmarthens1/mse112-ws-student.git"
WS_DIR_NAME="mse112-ws-student"       # Board.py hardcodes this folder name
# -----------------------------------------------------------------------------

set -u
say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
warn() { echo -e "    \033[1;33m!!\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"
REAL_USER=${SUDO_USER:-}
[ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] || die "Run it with sudo from your normal user, not as root."
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
WS_DIR="$REAL_HOME/$WS_DIR_NAME"

while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  warn "apt is busy (unattended-upgrades) - waiting 15 s..."; sleep 15
done

# ----------------------------- 1. APT ----------------------------------------
say "1/4  System packages"
apt-get update -q >/dev/null || die "apt update failed"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  git python3-pip python3-dev gcc i2c-tools python3-yaml python3-rpi.gpio >/dev/null \
  || die "apt install failed"
ok "git, pip, gcc, i2c-tools, python3-yaml, python3-rpi.gpio"

# ----------------------------- 2. PIP ----------------------------------------
# The SDK runs with sudo (rpi_ws281x needs /dev/mem), so install for root's
# python3. Ubuntu 22.04's pip allows this; it only prints a warning.
say "2/4  Python packages (smbus2, rpi_ws281x)"
pip3 install -q --root-user-action=ignore smbus2 rpi_ws281x 2>/dev/null \
  || pip3 install -q smbus2 rpi_ws281x \
  || die "pip install failed"
ok "smbus2 $(pip3 show smbus2 2>/dev/null | awk '/^Version/{print $2}'), rpi_ws281x $(pip3 show rpi_ws281x 2>/dev/null | awk '/^Version/{print $2}')"

# ----------------------------- 3. WORKSPACE ----------------------------------
say "3/4  Workspace $WS_DIR"
if [ -d "$WS_DIR/.git" ]; then
  sudo -u "$REAL_USER" git -C "$WS_DIR" pull -q --ff-only || warn "git pull failed - keeping the current copy"
else
  sudo -u "$REAL_USER" git clone -q "$WS_REPO" "$WS_DIR" || die "git clone failed"
fi
[ -f "$WS_DIR/MasterPi/HiwonderSDK/Board.py" ] || die "$WS_DIR/MasterPi/HiwonderSDK/Board.py not found"
ok "$(sudo -u "$REAL_USER" git -C "$WS_DIR" log --oneline -1)"

# ----------------------------- 4. CHECK --------------------------------------
say "4/4  Import check"
python3 -c "import yaml, RPi.GPIO, smbus2, rpi_ws281x" || die "a Python package does not import"
ok "yaml, RPi.GPIO, smbus2, rpi_ws281x import"

echo
echo "Next: check the board (battery, RGB LEDs, buzzer). The robot does not move:"
echo "    sudo python3 board_test.py"
echo
