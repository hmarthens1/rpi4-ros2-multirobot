---
layout: default
title: "Lab 02 — ROS 2 Humble (ros-base)"
---

# Lab 02 — ROS 2 Humble (ros-base)

**Raspberry Pi 4 · Ubuntu Server 22.04 LTS · ROS 2 Humble · ×3 robots**

**Objectives:** Install **ROS 2 Humble `ros-base`** and the build tools on all three robots, set them up as one fleet (one `ROS_DOMAIN_ID`, one namespace per robot), and prove that the robots and your laptop can talk to each other. Finish by building an empty workspace and re-running `robot_check.sh`.

---

## Before You Start

- **Lab 01 is done on all three robots**: `robot_check.sh` reports *ready for ROS 2 Humble*
- All three robots and your laptop are on **the same Wi-Fi network** (Lab 01, Part 4.3), and `ping robot02.local` works from `robot01`
- About 1.5 GB free on each SD card, and 15–20 minutes per robot, most of it downloading

### Pick the fleet's `ROS_DOMAIN_ID`

ROS 2 machines on the same network find each other automatically. The **domain ID**
(a number from 0 to 101) decides who belongs together: only machines with the same ID
see each other's topics. Choose one number for the fleet:

- the **same** number on all three robots **and** your laptop
- **different** from anyone else running ROS 2 on that network (the default, 0, is what everyone else uses)

This lab uses **`17`**. Write yours down.

> **ros-base, not desktop.** `ros-humble-ros-base` has the communication libraries,
> messages and command-line tools. `ros-humble-desktop` adds RViz, rqt and other GUI
> tools that a headless Pi can't show. Run those on the laptop instead.

---

## Part 1 — Install ROS 2: script or by hand

Pick **one**:

| | Option A — `install_ros2.sh` | Option B — step by step |
|---|---|---|
| What | one script runs Parts 2.1–2.6 | you type each command |
| Best for | robots 2 and 3, or all three | the first robot, to see what each step does |

Both give the same result. They follow the official
[ROS 2 Humble — Ubuntu (deb packages)](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html) guide.

### Option A — the script

⬇️ [install_ros2.sh](code/install_ros2.sh)

```bash
mkdir -p ~/lab02 && cd ~/lab02
curl -fsSLO {{ site.github.url }}/Lab_02/code/install_ros2.sh
nano install_ros2.sh                 # set ROS_DOMAIN_ID in the SETTINGS block
sudo bash install_ros2.sh
```

```bash
ROS_DISTRO="humble"
ROS_DOMAIN_ID=17          # the fleet's number - the same on every robot
INSTALL_DEMOS=1           # talker / listener, used in Part 4
```

It is safe to run again. To change only the domain ID later:
`sudo bash install_ros2.sh --env-only`.

When it finishes, **open a new SSH session** and skip to [Part 3](#part-3--test-on-one-robot).

### Option B — by hand

Continue with Part 2.

---

## Part 2 — Install ROS 2 by hand

### 2.1 Locale and universe

Done in Lab 01, Part 7. Check:

```bash
locale | grep LANG                        # LANG=en_US.UTF-8
grep -r universe /etc/apt/sources.list    # lines ending in "universe"
```

### 2.2 Add the ROS 2 apt repository

The **`ros2-apt-source`** package installs the repository's signing key and its address,
and keeps both up to date. It is downloaded from GitHub:

```bash
sudo apt update && sudo apt install -y curl
export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}')
echo $ROS_APT_SOURCE_VERSION              # e.g. 1.3.0 - empty means the lookup failed
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb
```

> Older guides use `curl … ros.key` and a hand-written `ros2.list` file. That key expired
> in June 2025. Use the package above instead.

### 2.3 Upgrade first

```bash
sudo apt update
sudo apt full-upgrade -y
```

> **Don't skip this on 22.04.** On a fresh image, installing ROS 2 before `systemd` and
> `udev` are updated can make apt **remove critical system packages**
> ([ros2/ros2#1272](https://github.com/ros2/ros2/issues/1272)). Lab 01 upgraded once
> already. Run it again anyway, since the new repository may bring updates.

### 2.4 Install ros-base and the development tools

```bash
sudo apt install -y ros-humble-ros-base ros-dev-tools
sudo apt install -y ros-humble-demo-nodes-cpp ros-humble-demo-nodes-py
```

| Package | What you get |
|---|---|
| `ros-humble-ros-base` | the ROS 2 libraries, standard messages, `ros2` command line, launch |
| `ros-dev-tools` | `colcon` (build tool), `rosdep` (installs dependencies), `vcstool`, compilers |
| `ros-humble-demo-nodes-*` | `talker` and `listener`, for Parts 3–5. `ros-base` doesn't include them |

### 2.5 rosdep

`rosdep` looks up and installs the system packages that a ROS package depends on.
Initialise it once per robot. `init` needs `sudo`, `update` must **not** use it:

```bash
sudo rosdep init
rosdep update
```

### 2.6 Environment in `~/.bashrc`

Every new shell needs ROS 2 loaded ("sourced"). Add these lines to the end of `~/.bashrc`
(`nano ~/.bashrc`), using your domain ID:

```bash
# >>> ROS 2 (install_ros2.sh) >>>
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=17
export ROS_LOCALHOST_ONLY=0
[ -f ~/ros2_ws/install/setup.bash ] && source ~/ros2_ws/install/setup.bash
[ -f /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash ] && source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
# <<< ROS 2 (install_ros2.sh) <<<
```

| Line | Why |
|---|---|
| `source /opt/ros/humble/setup.bash` | puts `ros2` and the ROS libraries on the path |
| `ROS_DOMAIN_ID=17` | the fleet's number, from *Before You Start* |
| `ROS_LOCALHOST_ONLY=0` | talk to other machines, not only to this Pi |
| `~/ros2_ws/install/setup.bash` | your own packages, once the workspace is built (Part 6) |
| `colcon-argcomplete` | Tab completion for `colcon` |

The marker lines let `install_ros2.sh` find and replace the block later.

Then **log out and SSH in again**, or run `source ~/.bashrc`. Check:

```bash
printenv | grep ROS
# ROS_VERSION=2
# ROS_DISTRO=humble
# ROS_DOMAIN_ID=17
# ROS_LOCALHOST_ONLY=0
# ...
```

---

## Part 3 — Test on one robot

Open **two** SSH sessions to `robot01`. In the first:

```bash
ros2 run demo_nodes_cpp talker
# [INFO] [talker]: Publishing: 'Hello World: 1'
```

In the second:

```bash
ros2 run demo_nodes_py listener
# [INFO] [listener]: I heard: [Hello World: 1]
```

That tests both the C++ and the Python side of ROS 2. Stop both with `Ctrl+C`.

> **One SSH session only?** Run the talker in the background:
> `ros2 run demo_nodes_cpp talker &`, then the listener, then `kill %1`.
> Or install `tmux` (`sudo apt install tmux`) to split one session into several.

Useful commands while the talker runs:

```bash
ros2 node list                 # /talker
ros2 topic list                # /chatter, /parameter_events, /rosout
ros2 topic echo /chatter       # print the messages
ros2 topic hz /chatter         # ~1 Hz
```

---

## Part 4 — Test across the robots

Now the part that matters for a fleet: a message sent on one robot is received on another.

| Where | Run |
|---|---|
| `robot01` | `ros2 run demo_nodes_cpp talker` |
| `robot02` | `ros2 run demo_nodes_py listener` |
| `robot03` | `ros2 run demo_nodes_py listener` |

Both listeners should print `I heard: [Hello World: …]`. On any robot, `ros2 node list`
now shows the nodes running on **all** robots.

Then swap roles, so every robot has been a talker once. Traffic that works in one
direction only usually means a firewall or Wi-Fi setting on one robot.

> **Nothing received?** Work through these in order:
> 1. Same `ROS_DOMAIN_ID` everywhere? `echo $ROS_DOMAIN_ID` on each robot.
> 2. Can the robots reach each other at all? `ping robot02.local` from `robot01`.
> 3. Does the network pass multicast? Run `ros2 multicast receive` on `robot02`, then `ros2 multicast send` on `robot01`.
>    If nothing arrives, the router blocks multicast or isolates clients (Lab 01, Part 4.3).
> 4. `ros2 daemon stop`, then try again. The daemon caches old discovery results.

### 4.1 Add your laptop

To see the robots from the laptop (and later use RViz there), the laptop needs ROS 2
Humble too, on the same network with the same `ROS_DOMAIN_ID`:

- **Ubuntu 22.04 laptop:** install `ros-humble-desktop` with the same steps as Part 2
- **Windows / macOS:** use a Ubuntu 22.04 virtual machine with **bridged** networking (NAT networking hides it from the robots)

```bash
# on the laptop
export ROS_DOMAIN_ID=17
ros2 topic echo /chatter       # while robot01 runs the talker
```

> **Use the same middleware (RMW) everywhere.** The robots use the default, Fast DDS
> (`rmw_fastrtps_cpp`). If the laptop sets `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`, either
> unset it for the fleet, or install `ros-humble-rmw-cyclonedds-cpp` on all three robots and
> set the same variable in their `~/.bashrc`. Mixed middleware sometimes works, but not reliably.

---

## Part 5 — One namespace per robot

In Part 4 all three robots used the same topic name, `/chatter`. For three robots running
the same software that is a problem: `robot01`'s `/cmd_vel` would drive all three. The fix is a
**namespace**: every node and topic of a robot lives under `/<hostname>/…`.

Try it. On each robot, start a talker in its own namespace:

```bash
ros2 run demo_nodes_cpp talker --ros-args -r __ns:=/$(hostname)
```

Then on any robot or the laptop:

```bash
ros2 topic list
# /robot01/chatter
# /robot02/chatter
# /robot03/chatter

ros2 topic echo /robot02/chatter      # only robot02's messages
```

This is why the hostnames are `robot01`–`robot03`: the hostname can be the namespace directly.
Every robot-specific lab from here on starts its nodes this way.

---

## Part 6 — A first workspace

Your own ROS 2 packages live in a **workspace**, built with `colcon`. Create one and build
it once, so the environment line from Part 2.6 has something to load:

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
ros2 pkg create --build-type ament_python hello_robot --node-name hello
cd ~/ros2_ws
colcon build --symlink-install
source ~/.bashrc
ros2 run hello_robot hello            # -> Hi from hello_robot.
```

| Folder | Contents |
|---|---|
| `src/` | your packages' source code. The only folder you edit |
| `build/` | intermediate build files |
| `install/` | the built packages. `install/setup.bash` loads them |
| `log/` | build logs |

> **Memory:** C++ packages can run a 2–4 GB Pi out of memory during the build. With the
> swap from Lab 01 this is rare. If a build is killed, use
> `colcon build --symlink-install --parallel-workers 1`.

---

## Part 7 — Check the robot again

Run the check from Lab 01 again on each robot, **on battery power** with the board switched on:

```bash
cd ~/lab01
sudo bash robot_check.sh
```

The **ROS 2** section is now filled in: install, `~/.bashrc`, `ROS_DOMAIN_ID`, colcon,
rosdep and the workspace. It should end with **"robot01 has ROS 2 humble installed and
nothing failed"**.

Copy the three new reports to your laptop:

```bash
scp 'robot01:robot_report_*' 'robot02:robot_report_*' 'robot03:robot_report_*' .
```

---

## Troubleshooting

| Problem | Try this |
|---------|---------|
| `ROS_APT_SOURCE_VERSION` is empty | The GitHub API lookup failed (no internet, or too many requests from one address). Wait a minute and retry, or set it by hand: `export ROS_APT_SOURCE_VERSION=1.3.0` (see the [releases page](https://github.com/ros-infrastructure/ros-apt-source/releases)) |
| `NO_PUBKEY` or `EXPKEYSIG` for packages.ros.org | An old `ros2.list` / `ros.key` from an older guide. `sudo rm /etc/apt/sources.list.d/ros2.list /usr/share/keyrings/ros-archive-keyring.gpg`, then Part 2.2 |
| `Release file ... is not valid yet` | The Pi's clock is wrong (Lab 01, Part 5) |
| apt wants to **remove** `systemd`, `udev` or many packages | Stop (answer `n`). Run `sudo apt full-upgrade` first (Part 2.3) |
| `Unable to locate package ros-humble-ros-base` | The repository is missing, or not `jammy`/`arm64`. Check `apt policy ros-humble-ros-base` and `dpkg --print-architecture` |
| `ros2: command not found` | ROS 2 isn't sourced: `source ~/.bashrc`, and check the block from Part 2.6 |
| `sudo rosdep init`: *default sources list file already exists* | Already done. Just run `rosdep update` |
| `rosdep update` run with `sudo` | Fix ownership: `sudo chown -R $USER: ~/.ros`, then `rosdep update` |
| Talker and listener work on one robot, not across robots | Part 4 checklist: domain ID, ping, `ros2 multicast`, `ros2 daemon stop` |
| Works across robots, but the laptop sees nothing | Laptop's `ROS_DOMAIN_ID`, a VM using NAT instead of bridged networking, a different RMW, or the laptop's firewall |
| Topics show up in `ros2 topic list` but no messages arrive | Usually a firewall on one side (`sudo ufw status`), or the laptop is on a VPN |
| `colcon build`: *option --editable not recognized* | A newer `setuptools` from `pip` shadows Ubuntu's. `pip3 list --user \| grep setuptools`, then `pip3 uninstall setuptools` (the apt one stays) |
| Build killed / `c++: fatal error: Killed signal` | Out of memory: `colcon build --parallel-workers 1` and check swap (Lab 01, Part 6) |

---

## Completion Checklist (per robot)

- [ ] `ros2-apt-source` installed, `apt full-upgrade` done
- [ ] `ros-humble-ros-base`, `ros-dev-tools` and the demo nodes installed
- [ ] `rosdep` initialised and updated
- [ ] `~/.bashrc` sources ROS 2 and sets the fleet's `ROS_DOMAIN_ID`
- [ ] Talker → listener works on this robot (Part 3)
- [ ] This robot's talker is heard on the other two robots, and it hears theirs (Part 4)
- [ ] *(optional)* The laptop sees the robots' topics (Part 4.1)
- [ ] `/robot0N/chatter` shows up when started with a namespace (Part 5)
- [ ] `~/ros2_ws` builds and `ros2 run hello_robot hello` works (Part 6)
- [ ] `sudo bash robot_check.sh` passes the ROS 2 section, and the report is on the laptop
