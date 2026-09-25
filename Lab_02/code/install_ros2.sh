#!/bin/bash
# =============================================================================
# RPi4 Lab 02 - Install ROS 2 Humble (ros-base) on Ubuntu Server 22.04
# =============================================================================
# Does the same steps as Lab 02, Parts 1-4, in one go, so the three robots end
# up identical:
#
#   1. UTF-8 locale, 'universe' repository, curl
#   2. ROS 2 apt repository (the ros2-apt-source package)
#   3. apt full-upgrade  (must come BEFORE ROS 2 on 22.04, see below)
#   4. ros-humble-ros-base + ros-dev-tools (colcon, rosdep, vcstool)
#      + the talker/listener demo nodes
#   5. rosdep init / update
#   6. a ROS 2 block in ~/.bashrc: source setup.bash, ROS_DOMAIN_ID, ...
#
# Safe to run again: every step checks whether it's already done.
#
# USAGE
#   sudo bash install_ros2.sh             # full install
#   sudo bash install_ros2.sh --env-only  # only rewrite the ~/.bashrc block
#                                         # (e.g. after changing ROS_DOMAIN_ID)
#
# Run this ON EACH ROBOT, over SSH. It needs internet. It takes about
# 10-20 minutes on a Pi 4, most of it downloading.
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
ROS_DISTRO="humble"
ROS_DOMAIN_ID=17          # 0-101. SAME number on all three robots AND your laptop,
                          # and different from anyone else's ROS 2 on the network.
INSTALL_DEMOS=1           # 1 = also install demo_nodes_cpp/py (talker, listener)
# -----------------------------------------------------------------------------

set -u
REAL_USER=${SUDO_USER:-}
say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
warn() { echo -e "    \033[1;33m!!\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"
[ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] || die "Run it with sudo from your normal user, not as root."
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
BASHRC="$REAL_HOME/.bashrc"
[[ "$ROS_DOMAIN_ID" =~ ^[0-9]+$ ]] && [ "$ROS_DOMAIN_ID" -le 101 ] || die "ROS_DOMAIN_ID must be 0-101"

# ----------------------------- ~/.bashrc BLOCK -------------------------------
write_env() {
  say "Writing the ROS 2 block in $BASHRC"
  touch "$BASHRC"
  # Remove an older copy of the block, then append the new one.
  sed -i '/^# >>> ROS 2 (install_ros2.sh) >>>$/,/^# <<< ROS 2 (install_ros2.sh) <<<$/d' "$BASHRC"
  cat >> "$BASHRC" <<ENV
# >>> ROS 2 (install_ros2.sh) >>>
source /opt/ros/$ROS_DISTRO/setup.bash
export ROS_DOMAIN_ID=$ROS_DOMAIN_ID
export ROS_LOCALHOST_ONLY=0
[ -f ~/ros2_ws/install/setup.bash ] && source ~/ros2_ws/install/setup.bash
[ -f /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash ] && source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
# <<< ROS 2 (install_ros2.sh) <<<
ENV
  chown "$REAL_USER": "$BASHRC"
  ok "ROS_DOMAIN_ID=$ROS_DOMAIN_ID - open a new SSH session (or: source ~/.bashrc) to use it"
}

if [ "${1:-}" = "--env-only" ]; then write_env; exit 0; fi

# ----------------------------- CHECKS ----------------------------------------
say "Checking the system"
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "jammy" ] || die "This is $PRETTY_NAME. ROS 2 Humble debs need Ubuntu 22.04 (jammy)."
[ "$(dpkg --print-architecture)" = "arm64" ] || die "Not arm64 - flash the 64-bit Ubuntu Server image."
ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 || die "No internet. Fix that first (Lab 01, Part 3.1)."
timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes \
  || warn "Clock not synchronised ($(date)). If apt says 'not valid yet', wait for NTP."
ok "$PRETTY_NAME, arm64, online"

while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  warn "apt is busy (unattended-upgrades) - waiting 20 s..."; sleep 20
done

# ----------------------------- 1. LOCALE + UNIVERSE --------------------------
say "1/6  UTF-8 locale and the universe repository"
apt-get update -q || die "apt update failed"
apt-get install -y -q locales software-properties-common curl || die "apt install failed"
locale -a 2>/dev/null | grep -qi '^en_US.utf8$' || locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
add-apt-repository -y universe >/dev/null
ok "locale en_US.UTF-8, universe enabled"

# ----------------------------- 2. ROS 2 APT SOURCE ---------------------------
say "2/6  ROS 2 apt repository"
if dpkg -s ros2-apt-source >/dev/null 2>&1; then
  ok "ros2-apt-source already installed ($(dpkg-query -W -f='${Version}' ros2-apt-source))"
else
  VER=$(curl -fsS https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
        | grep -F '"tag_name"' | awk -F'"' '{print $4}')
  [ -n "$VER" ] || die "Could not look up the ros-apt-source version on GitHub. Try again in a minute."
  DEB=/tmp/ros2-apt-source.deb
  curl -fsSL -o "$DEB" \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${VER}/ros2-apt-source_${VER}.${UBUNTU_CODENAME:-$VERSION_CODENAME}_all.deb" \
    || die "Download of ros2-apt-source $VER failed"
  dpkg -i "$DEB" || die "dpkg -i ros2-apt-source failed"
  rm -f "$DEB"
  ok "ros2-apt-source $VER installed"
fi

# ----------------------------- 3. UPGRADE FIRST ------------------------------
# On a fresh 22.04 image, installing ROS 2 before upgrading systemd/udev can
# make apt REMOVE critical system packages (ros2/ros2#1272).
say "3/6  apt full-upgrade (required before ROS 2 on 22.04)"
apt-get update -q || die "apt update failed"
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -q || die "full-upgrade failed"
ok "system up to date"

# ----------------------------- 4. ROS 2 --------------------------------------
say "4/6  ros-$ROS_DISTRO-ros-base and ros-dev-tools"
PKGS="ros-$ROS_DISTRO-ros-base ros-dev-tools"
[ "$INSTALL_DEMOS" = "1" ] && PKGS="$PKGS ros-$ROS_DISTRO-demo-nodes-cpp ros-$ROS_DISTRO-demo-nodes-py"
# shellcheck disable=SC2086
DEBIAN_FRONTEND=noninteractive apt-get install -y -q $PKGS || die "ROS 2 install failed"
ok "installed: $PKGS"

# ----------------------------- 5. ROSDEP -------------------------------------
say "5/6  rosdep"
[ -f /etc/ros/rosdep/sources.list.d/20-default.list ] || rosdep init || die "rosdep init failed"
sudo -u "$REAL_USER" -H rosdep update || warn "rosdep update failed - run it again later as $REAL_USER: rosdep update"
ok "rosdep ready"

# ----------------------------- 6. ENVIRONMENT --------------------------------
write_env

# ----------------------------- RESULT ----------------------------------------
say "Result"
sudo -u "$REAL_USER" -H bash -c "source /opt/ros/$ROS_DISTRO/setup.bash && echo \"    ROS_DISTRO=\$ROS_DISTRO\" && ros2 pkg list | wc -l | xargs echo '    ROS packages:'"
[ -f /var/run/reboot-required ] && warn "The upgrade asks for a reboot: sudo reboot"
echo
echo "Next: open a NEW SSH session, then test with"
echo "    ros2 run demo_nodes_cpp talker"
echo
