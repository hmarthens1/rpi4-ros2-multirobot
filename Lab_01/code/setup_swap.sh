#!/bin/bash
# =============================================================================
# RPi4 Lab 01 - Memory swap setup for Ubuntu Server 22.04
# =============================================================================
# The Pi 4 ships with 1-8 GB of RAM. apt installs of ROS 2 are fine without
# swap, but building a workspace from source with colcon (C++ packages
# especially) can run out of memory and get killed partway through.
#
#   zram  - compressed swap that lives in RAM. Fast, no SD card wear.
#   file  - a swap file (/swapfile) on the SD card. Slower, but real extra
#           capacity that does not compete with RAM.
#
# Ubuntu does not use dphys-swapfile like Raspberry Pi OS - the swap file is
# created directly and listed in /etc/fstab. zram is started by a systemd
# service, so nothing can hang the boot.
#
# USAGE
#   sudo bash setup_swap.sh              # set up swap
#   sudo bash setup_swap.sh --status     # just show current swap
#   sudo bash setup_swap.sh --uninstall  # undo
#
# Run this ON THE ROBOT (over SSH is fine). No reboot needed.
# =============================================================================

# ----------------------------- SETTINGS --------------------------------------
SWAP_MODE="both"     # "both" (recommended) | "zram" | "file"
ZRAM_FACTOR=1        # total zram = this x RAM
FILE_SWAP_MB=2048    # size of /swapfile on the SD card
RECOMMENDED_MB=4000  # RAM + swap worth having before building ROS 2 packages
# -----------------------------------------------------------------------------

set -u
SWAPFILE=/swapfile
ZRAM_SCRIPT=/usr/local/bin/robot-zram.sh
ZRAM_UNIT=/etc/systemd/system/robot-zram.service

say()  { echo -e "\n\033[1;36m==> $*\033[0m"; }
ok()   { echo -e "    \033[1;32mOK\033[0m  $*"; }
warn() { echo -e "    \033[1;33m!!\033[0m  $*"; }
die()  { echo -e "\n\033[1;31mERROR:\033[0m $*\n" >&2; exit 1; }

show_status() {
  echo
  free -h
  echo
  echo "Active swap devices:"
  cat /proc/swaps
  TOTAL_MB=$(free -m | awk '/^Mem:/{m=$2} /^Swap:/{s=$2} END{print m+s}')
  echo
  echo "Total memory + swap: ${TOTAL_MB} MB"
  if [ "$TOTAL_MB" -ge "$RECOMMENDED_MB" ]; then
    echo -e "\033[1;32mThat is enough for building ROS 2 packages on the Pi.\033[0m"
  else
    echo -e "\033[1;33mBelow ${RECOMMENDED_MB} MB - build with: colcon build --parallel-workers 1\033[0m"
  fi
  echo
}

[ "${1:-}" = "--status" ] && { show_status; exit 0; }
[ "$(id -u)" -eq 0 ] || die "Must run with sudo:  sudo bash $0"

# ----------------------------- UNINSTALL -------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  say "Removing zram"
  systemctl disable --now robot-zram.service 2>/dev/null
  for d in /dev/zram*; do [ -b "$d" ] && swapoff "$d" 2>/dev/null; done
  rm -f "$ZRAM_UNIT" "$ZRAM_SCRIPT"
  systemctl daemon-reload
  ok "zram removed"
  say "Removing $SWAPFILE"
  swapoff "$SWAPFILE" 2>/dev/null
  sed -i "\|^$SWAPFILE |d" /etc/fstab
  rm -f "$SWAPFILE"
  ok "swap file removed"
  show_status
  exit 0
fi

RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
say "This Pi has $((RAM_KB/1024)) MB RAM and $(nproc) cores"

# ----------------------------- ZRAM ------------------------------------------
if [ "$SWAP_MODE" = "both" ] || [ "$SWAP_MODE" = "zram" ]; then
  say "Setting up zram (compressed swap in RAM)"

  # On Ubuntu's Raspberry Pi kernel the zram module may live in the
  # linux-modules-extra package, which is not always installed.
  if ! modprobe zram 2>/dev/null; then
    warn "zram module not found - installing linux-modules-extra-$(uname -r)"
    apt-get install -y "linux-modules-extra-$(uname -r)" >/dev/null 2>&1
  fi

  if modprobe zram 2>/dev/null; then
    ZRAM_BYTES=$(( RAM_KB * 1024 * ZRAM_FACTOR ))

    cat > "$ZRAM_SCRIPT" <<ZSCRIPT
#!/bin/bash
# Robot Pi - bring up zram swap. Installed by setup_swap.sh.
modprobe zram 2>/dev/null
[ -b /dev/zram0 ] || cat /sys/class/zram-control/hot_add >/dev/null 2>&1
swapoff /dev/zram0 2>/dev/null
echo 1 > /sys/block/zram0/reset 2>/dev/null
sleep 1
echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
echo $ZRAM_BYTES > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null 2>&1
swapon -p 5 /dev/zram0
ZSCRIPT
    chmod +x "$ZRAM_SCRIPT"

    cat > "$ZRAM_UNIT" <<ZUNIT
[Unit]
Description=Robot zram swap
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$ZRAM_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
ZUNIT

    systemctl daemon-reload
    systemctl enable robot-zram.service >/dev/null 2>&1
    systemctl restart robot-zram.service
    sleep 2
    ZSIZE=$(awk '/zram/{print int($3/1024)}' /proc/swaps)
    [ -n "$ZSIZE" ] && ok "zram active: ${ZSIZE} MB" \
                    || warn "zram did not come up - check: systemctl status robot-zram"
  else
    warn "This kernel has no zram module - skipping zram, the swap file still helps"
  fi
fi

# ----------------------------- FILE SWAP -------------------------------------
if [ "$SWAP_MODE" = "both" ] || [ "$SWAP_MODE" = "file" ]; then
  say "Setting up a ${FILE_SWAP_MB} MB swap file at $SWAPFILE"

  swapoff "$SWAPFILE" 2>/dev/null
  rm -f "$SWAPFILE"

  FREE_MB=$(df -m / | awk 'NR==2{print $4}')
  [ "$FREE_MB" -lt $((FILE_SWAP_MB + 1000)) ] \
    && die "Not enough free space on the SD card (${FREE_MB} MB free, need $((FILE_SWAP_MB + 1000)) MB)."

  fallocate -l "${FILE_SWAP_MB}M" "$SWAPFILE" 2>/dev/null \
    || dd if=/dev/zero of="$SWAPFILE" bs=1M count="$FILE_SWAP_MB" status=none \
    || die "Could not create $SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE" >/dev/null || die "mkswap failed"
  swapon -p 0 "$SWAPFILE"       || die "swapon failed"
  grep -q "^$SWAPFILE " /etc/fstab || echo "$SWAPFILE none swap sw,pri=0 0 0" >> /etc/fstab
  ok "swap file active and listed in /etc/fstab"
fi

# ----------------------------- VERIFY ----------------------------------------
say "Result"
show_status
echo "Swap is active now and will come back automatically after a reboot."
echo "Check it any time with:  sudo bash setup_swap.sh --status"
echo
