# RPi4 + ROS 2 Multi-Robot

GitHub Pages site with setup instructions for three robots, each a **Raspberry Pi 4** on a
**Hiwonder 4-channel motor expansion board**, running **Ubuntu Server 22.04 LTS** and
**ROS 2 Humble (ros-base)**.

Adapted from [cm4-ubuntu-setup](https://github.com/hmarthens1/cm4-ubuntu-setup).

## Layout

```
index.md                 home page: fleet, expansion board pin map, roadmap
Lab_01/index.md          Pi 4 setup: flash, SSH, networking, swap, ROS 2 prep
Lab_01/code/
  setup_network.sh         netplan: wlan0 static IP / DHCP, Wi-Fi client/hotspot (runs on the Pi)
  setup_swap.sh            zram + /swapfile                                    (runs on the Pi)
  robot_check.sh           read-only capability check, writes a report file    (runs on the Pi)
Lab_02/index.md          ROS 2 Humble ros-base, fleet domain ID, cross-robot test, namespaces
Lab_02/code/
  install_ros2.sh          the Lab 02 install steps in one script              (runs on the Pi)
```

## Publishing

Settings → Pages → *Deploy from a branch* → `main` / `(root)`.
The theme (`pages-themes/hacker`) is loaded with `jekyll-remote-theme`, so no build workflow is needed.
