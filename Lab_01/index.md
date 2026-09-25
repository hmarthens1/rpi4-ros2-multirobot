---
layout: default
title: "Lab 01 — Raspberry Pi 4 Setup & SSH"
---

# Lab 01 — Raspberry Pi 4 Setup & SSH

**Raspberry Pi 4 · Hiwonder 4-channel motor expansion board · Ubuntu Server 22.04 LTS · ×3 robots**

**Objectives:** Flash Ubuntu Server 22.04 LTS (64-bit) to an SD card and boot the Pi 4 without a monitor. The Pi joins your Wi-Fi router on its own, so you connect over SSH through the router, then give the Pi a **static Wi-Fi address**, update the system, add swap and prepare it for **ROS 2 Humble (ros-base)**. Finish by running `robot_check.sh`, which writes a report of what the robot's Pi can do. Do this once per robot.

---

## Before You Start

You will need, **per robot**:
- A **Raspberry Pi 4 Model B** (2, 4 or 8 GB). It has Wi-Fi built in
- A micro-SD card (32 GB or more, class **A1/A2**) and a card reader
- For the bench: the official **5 V 3 A USB-C** Pi 4 power supply
- On the robot: the **Hiwonder RaspberryPi-Adapter-4chMotorDrive V3.x** expansion board and its battery

And once:
- A **Wi-Fi router with internet access**. The robots and your laptop all join it
- A laptop (Windows, macOS or Linux) on that router's Wi-Fi
- Access to the router's admin page (usually `http://192.168.0.1` or `http://192.168.1.1`)
- Optional: a micro-HDMI to HDMI cable, a monitor and a USB keyboard, for setting the hostname at the console (Part 2.1) or when the Pi doesn't show up on the network

### Plan the fleet first

Every robot needs its own name and its own **fixed** Wi-Fi address, so you always SSH to the
same place and the robots can find each other. Decide them now and label the SD cards.
The examples use a router at `192.168.0.1`:

| Robot | Hostname | wlan0 static IP | Gateway (router) |
|---|---|---|---|
| 1 | `robot01` | `192.168.0.11` | `192.168.0.1` |
| 2 | `robot02` | `192.168.0.12` | `192.168.0.1` |
| 3 | `robot03` | `192.168.0.13` | `192.168.0.1` |

The rule: same first three numbers as the router, last number **10 + the robot number**.
Part 4.1 checks that these addresses are free on your router.

> **Why `robot01` and not `rpi4-01`?** Later, each robot's ROS 2 topics live under its own
> namespace, e.g. `/robot01/cmd_vel`. ROS names can't contain `-`, and hostnames can't
> contain `_`. A name made only of lowercase letters and digits works as both.

This guide uses **`robot01`** and user **`ubuntu`** in its examples. Repeat the lab with
`robot02` and `robot03`.

### Power: one source at a time

The expansion board powers the Pi from its battery: battery → power switch → a 5 V DC-DC
converter → the Pi's 5 V header pins (pins 2 and 4). The Pi 4 has **no protection between
those pins and its USB-C port**, so never connect the USB-C supply while the board is powering the Pi.

| Where you are | Power the Pi from | Expansion board |
|---|---|---|
| On the bench (Parts 1–7) | USB-C supply | **off the Pi**, or fitted with its switch **OFF** and the battery unplugged |
| On the robot (Part 8 onwards) | the battery, through the board | fitted, switch **ON**, USB-C **unplugged** |

A weak battery or DC-DC converter shows up as *under-voltage*: the red power LED blinks or
goes off, and `robot_check.sh` reports it (Part 8).

> **Why Ubuntu 22.04 and not the newest Ubuntu?** ROS 2 Humble is released as ready-built
> packages for Ubuntu 22.04 "Jammy" only. On a newer Ubuntu you would have to compile
> ROS 2 from source.

---

## Part 1 — Flash Ubuntu Server to the SD card

### 1.1 Install Raspberry Pi Imager

Download and install **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** on your laptop.
Insert the SD card into the card reader and plug it in.

### 1.2 Choose the device, OS and storage

In Imager select:

| Setting | Choose |
|---|---|
| **Device** | Raspberry Pi 4 |
| **OS** | Other general-purpose OS → Ubuntu → **Ubuntu Server 22.04.x LTS (64-bit)** |
| **Storage** | your SD card |

> Pick **Server**, not Desktop, and **22.04**, not 24.04. ROS 2 `ros-base` needs no desktop,
> and a server image leaves more RAM for your robot code.

### 1.3 OS customisation — this replaces the monitor setup

The Pi runs without a monitor ("headless"), so everything the first-boot wizard would ask
is set in Imager. When Imager asks **"Would you like to apply OS customisation settings?"**,
choose **Edit settings**. Newer Imager versions show these as steps in the wizard instead.

| Tab | Setting | Value |
|---|---|---|
| General | Hostname | `robot01` (then `robot02`, `robot03`; missed it? see Part 2.1) |
| General | Username / password | `ubuntu` / a password you will remember. **Use the same user on all three robots**: scripts and ROS 2 tools assume it |
| General | Wireless LAN | **your router's** Wi-Fi SSID + password + **Wireless LAN country** (e.g. `CA`). Required: it is the Pi's only network connection |
| General | Locale | your time zone and keyboard layout |
| Services | Enable SSH | ✅ *Use password authentication* (skipped? see Part 3.2.1) |

Click **Save**, then **Yes** to apply the settings, then **Write**. The write and verify take about 5–10 minutes.

> **Check the Wi-Fi name and password twice.** A typo means the Pi never joins the router,
> and without a cable the only way to fix it is a monitor and keyboard, or re-flashing.
> The SSID is case-sensitive.

> **Which router?** The three robots and your laptop must be on **the same network** and able
> to reach each other, because ROS 2 finds other robots by multicast. Campus and guest
> Wi-Fi usually blocks that. A small dedicated router for the robots avoids the problem
> (Part 4.3).

---

## Part 2 — First Boot

1. Insert the SD card into the Pi.
2. Connect the **USB-C** supply (bench, expansion board off). The red LED lights and the green LED flickers while the SD card is read.

**Wait 3–5 minutes.** On first boot Ubuntu's `cloud-init` applies your Imager settings:
it creates your user, sets the hostname, joins your Wi-Fi router and enables SSH. It may
reboot once while it does this. If you try to log in too early, you get `Permission denied`
or no answer at all, even with the right settings. Wait, then try again.

> **What about a monitor?** You don't need one. If you want to watch the boot, plug a
> monitor into **micro-HDMI 0**, the port next to the USB-C socket, and a USB keyboard into any USB port.

### 2.1 Set the hostname (monitor + keyboard)

If you skipped the hostname in Imager, the Pi boots as **`ubuntu`**, and then all three
robots have the same name. Set a unique name at the Pi's own console.

**1. Connect a monitor and keyboard.** With the power off, plug the monitor into
**micro-HDMI 0** and a USB keyboard into a USB port. Then power on.

**2. Log in at the text console.** Ubuntu Server has no desktop. After the boot messages,
wait for the `cloud-init` lines to stop, then press **Enter** to get a login prompt:

```
ubuntu login: ubuntu
Password:
```

- **If you set a user in Imager**, log in with that username and password.
- **If you skipped customisation entirely**, the default login is `ubuntu` / `ubuntu`. Ubuntu
  then makes you change it right away: type the current password (`ubuntu`) once, then your
  new password twice.

> The password doesn't show while you type, not even as `*`. That is normal.

**3. Check the current name:**

```bash
hostnamectl
```

**4. Set the new name.** Lowercase letters and digits only, e.g. `robot01`:

```bash
sudo hostnamectl set-hostname robot01
```

**5. Update `/etc/hosts`,** so `sudo` doesn't warn *"unable to resolve host robot01"*:

```bash
sudo nano /etc/hosts
```

Change the `127.0.1.1` line to your new name (add the line if it is missing):

```
127.0.0.1 localhost
127.0.1.1 robot01
```

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

**6. Stop cloud-init from changing the name back on the next boot:**

```bash
echo "preserve_hostname: true" | sudo tee /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
```

**7. Reboot and check:**

```bash
sudo reboot
# log in again, then:
hostname          # -> robot01
```

While you are at the console, note the Pi's IP address. It saves searching for it in Part 3.1:

```bash
ip -br addr       # e.g. wlan0  UP  192.168.0.3/24
```

> **Later changes over SSH:** the same steps (3–7) work in an SSH session too. If you
> have already installed `avahi-daemon` (Part 4.2), also run
> `sudo systemctl restart avahi-daemon` so that `<new-name>.local` resolves.

---

## Part 3 — Connect from your laptop

Your laptop and the Pi are both on the router's Wi-Fi, so the laptop reaches the Pi
through the router. No cable and no internet sharing are needed.

### 3.1 Find the Pi's IP address

On first boot the router gives the Pi an address automatically (DHCP), e.g. `192.168.0.3`.
Part 4.1 replaces it with the fixed one from your plan. To find it:

| Way | How | Look for |
|---|---|---|
| **Router admin page** (easiest) | open `http://192.168.0.1` (your router's address) → *Connected devices*, *DHCP clients* or *Attached devices* | `robot01`, or a Pi MAC address |
| **Linux laptop** | `nmap -sn 192.168.0.0/24` (`sudo apt install nmap`), then `ip neigh` | a line with a Pi MAC |
| **macOS laptop** | `nmap -sn 192.168.0.0/24` (from Homebrew), then `arp -a` | a line with a Pi MAC |
| **Windows laptop** | PowerShell: `arp -a` | under your Wi-Fi interface, a `192.168.0.x` entry with a Pi MAC |
| **At the Pi** | monitor + keyboard, log in, `ip -br addr` | `wlan0  UP  192.168.0.3/24` |

**How to recognise the Pi:** its hardware (MAC) address starts with a Raspberry Pi prefix:
`dc:a6:32`, `e4:5f:01`, `d8:3a:dd`, `88:a2:9e`, `28:cd:c1`, `2c:cf:67` or `b8:27:eb`.
Windows shows these with dashes, e.g. `dc-a6-32-…`.

Use your router's first three numbers wherever these examples say `192.168.0`.

> **Your laptop's own address** tells you the network: `ip -br addr` (Linux), `ipconfig`
> (Windows) or `ipconfig getifaddr en0` (macOS). If the laptop is `192.168.0.2`, the Pi is
> somewhere in `192.168.0.x`.

> **The Pi doesn't show up at all?** Give it 5 minutes after power-on. Then check the Wi-Fi
> name, password and country from Imager, and that the router uses 2.4 GHz or 5 GHz on a
> channel the Pi supports. A monitor and keyboard show the real state: log in and run
> `ip -br addr` and `networkctl status wlan0`.

### 3.2 SSH in

```bash
ssh ubuntu@<PI_IP>          # e.g. ssh ubuntu@192.168.0.3
```

Use the username you set in Imager. Type `yes` to accept the host key the first time, then your password.

> **No answer, or `ping` works only on the second try?** The Pi's Wi-Fi saves power by
> dozing, so the first packets can be lost or take a second. Try again. Part 4.4 turns power
> saving off.

> **"REMOTE HOST IDENTIFICATION HAS CHANGED"** after re-flashing, or after the Pi moves to its
> static address, is expected: the new OS has new keys. Clear the old one with
> `ssh-keygen -R <PI_IP>` (and `ssh-keygen -R robot01.local`).

#### 3.2.1 `Permission denied (publickey)`: turn on password login

```
$ ssh ubuntu@192.168.0.3
ubuntu@192.168.0.3: Permission denied (publickey).
```

This means the Pi **accepts only SSH keys, not passwords**, and it doesn't trust your laptop's key.
Ubuntu's image switches password login off unless Imager's *Enable SSH → Use password
authentication* setting was applied. Turn it on at the Pi's own console:

**1.** Connect the monitor and keyboard and log in (Part 2.1). Confirm your username, since you need it for SSH:

```bash
whoami
```

**2.** See which file turns passwords off:

```bash
sudo grep -ri passwordauthentication /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
# typically: /etc/ssh/sshd_config.d/50-cloud-init.conf:PasswordAuthentication no
```

**3.** Override it. The SSH server uses the **first** value it reads, and it reads the files in
`sshd_config.d/` in name order, so a file starting with `01-` wins over `50-cloud-init.conf`:

```bash
echo "PasswordAuthentication yes" | sudo tee /etc/ssh/sshd_config.d/01-password-auth.conf
sudo systemctl restart ssh
sudo sshd -T | grep -i passwordauthentication     # -> passwordauthentication yes
```

**4.** From the laptop, try again. It now asks for your password:

```bash
ssh <username>@<PI_IP>
```

Next, set up SSH keys (Part 3.3). After that you can switch password login off again for
security with `sudo rm /etc/ssh/sshd_config.d/01-password-auth.conf && sudo systemctl restart ssh`.

> **Wrong username gives the same error.** If the account doesn't exist, SSH still says
> `Permission denied (publickey)` when passwords are off. Check it with `whoami` at the console.

### 3.3 Log in without a password (SSH keys)

From your **laptop** (not the Pi). Create the key once, then copy it to each robot:

```bash
ssh-keygen -t ed25519                  # once; press Enter to accept the defaults
ssh-copy-id ubuntu@<PI_IP>             # macOS / Linux, once per robot
```

On Windows, where `ssh-copy-id` doesn't exist, run this in PowerShell:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@<PI_IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

The key stays valid when the Pi moves to its static address in Part 4.1.

### 3.4 VS Code Remote-SSH

For a graphical editor on files that live on the Pi, install the **Remote - SSH**
extension in VS Code and connect to `ubuntu@<PI_IP>` (or `robot01` once Part 4.2 is done):

<a href="https://youtu.be/RLd6qgRHVh0" target="_blank">
  <img src="https://img.youtube.com/vi/RLd6qgRHVh0/hqdefault.jpg" alt="SSH with VSCode" style="max-width:100%;">
</a>

### 3.5 Get the lab scripts onto the Pi

Several later steps run a script **on the Pi**. The Pi has internet through the router, so
download them directly. In an SSH session:

```bash
mkdir -p ~/lab01 && cd ~/lab01
for f in setup_network.sh setup_swap.sh robot_check.sh; do
  curl -fsSLO {{ site.github.url }}/Lab_01/code/$f
done
ls
```

The scripts: ⬇️ [setup_network.sh](code/setup_network.sh) ·
⬇️ [setup_swap.sh](code/setup_swap.sh) · ⬇️ [robot_check.sh](code/robot_check.sh)

> **`curl: (6) Could not resolve host`** means the Pi has no internet yet. Check
> `ping -c3 8.8.8.8` on the Pi. As a fallback, download the scripts on the laptop and copy them over:
> `scp setup_network.sh setup_swap.sh robot_check.sh ubuntu@<PI_IP>:~/lab01/`

---

## Part 4 — Networking

Ubuntu Server doesn't use `/etc/dhcpcd.conf` (a Raspberry Pi OS file). Networking is set by
**netplan** YAML files in `/etc/netplan/`. On first boot, cloud-init wrote
`/etc/netplan/50-cloud-init.yaml` with the Wi-Fi network you gave Imager, set to get an address by DHCP.

### 4.1 Static IP on wlan0

The router's DHCP address can change after a reboot, and then you are hunting for the Pi
again, and the other robots lose it too. A static address never changes.

#### Step 1 — Get your router's details

You need three things. Find them on the Pi, in the SSH session:

```bash
ip -br addr show wlan0     # the current address and prefix, e.g. 192.168.0.3/24
ip route | grep default    # the router (gateway), e.g. "default via 192.168.0.1 dev wlan0"
```

| You need | Example | Where it comes from |
|---|---|---|
| **Gateway** | `192.168.0.1` | the `default via` address |
| **Prefix** | `/24` | the end of the current address |
| **Static address** | `192.168.0.11/24` | first three numbers of the gateway + `.1N` for robot `0N` |

#### Step 2 — Make sure the address is free

The static address must not be one the router could hand to another device. Open the
router's admin page (`http://192.168.0.1`), find the **DHCP settings** and check the
**address pool** (or "range"):

| If the pool is… | Then |
|---|---|
| e.g. `192.168.0.100` – `192.168.0.199` | `.11`, `.12`, `.13` are outside it. Use them |
| e.g. `192.168.0.2` – `192.168.0.254` (the whole network) | change the pool's start to `.100`, **or** pick addresses above the pool's end if there is room |

Then check nobody is using it right now. On the Pi:

```bash
ping -c2 192.168.0.11      # "Destination Host Unreachable" or 100% loss = free
```

> **Alternative: a DHCP reservation.** Most routers can always give the same address to one
> MAC address (*Address reservation*, *Static lease*). That gives a fixed address without
> changing the Pi at all. This lab sets it on the Pi instead, so the address stays the same
> if the robots move to another router.

#### Step 3 — Set it on the Pi: pick Method A or B

Both methods change the address of the connection you are using, so **the SSH session
freezes when you apply it**. That is expected. Wait about 20 seconds and connect to the new
address. If you make a mistake, the Pi drops off the network until you fix it with a
monitor and keyboard, so check your values before applying.

| | Method A — write the file by hand | Method B — the `setup_network.sh` script |
|---|---|---|
| What | one small netplan file that overrides the address | one netplan file with everything, a backup and checks |
| Checks the address is free | no, you did it in Step 2 | yes |
| Undo | delete the file | `--restore` |

---

#### Method A — Write the netplan file by hand

**1.** Look at the existing network files:

```bash
ls /etc/netplan/
# usually: 50-cloud-init.yaml   (written on first boot from your Imager settings)
sudo cat /etc/netplan/50-cloud-init.yaml
```

You see `wifis:` → `wlan0:` with your network name under `access-points:` and `dhcp4: true`.

**2.** Create a new file. Its name starts with `99-` so it is read *last*. netplan merges the
files: your new file replaces only the address settings of `wlan0`, and the Wi-Fi name and
password still come from `50-cloud-init.yaml`.

```bash
sudo nano /etc/netplan/99-wlan0-static.yaml
```

**3.** Type this in, using **your** values from Step 1:

```yaml
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: false
      addresses: [192.168.0.11/24]
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses: [192.168.0.1, 8.8.8.8]
```

> **YAML is strict about indentation.** Use **spaces, never Tab**, exactly 2 per level as
> shown. `addresses` and `routes` line up under `dhcp4`, and `- to:` is indented under `routes:`.

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

**4.** Lock down the file's permissions (netplan warns otherwise) and stop cloud-init from
rewriting the network config on later boots:

```bash
sudo chmod 600 /etc/netplan/99-wlan0-static.yaml
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

**5.** Check the file:

```bash
sudo netplan generate          # no output = no mistakes. An error names the line to fix.
```

**6.** Apply it. The SSH session freezes here:

```bash
sudo netplan apply
```

**7.** From your **laptop**, after about 20 seconds:

```bash
ssh-keygen -R 192.168.0.11     # only if SSH complains about a changed host key
ssh ubuntu@192.168.0.11
```

On the Pi, check:

```bash
ip -br addr show wlan0         # -> wlan0  UP  192.168.0.11/24
ping -c3 192.168.0.1           # the router answers?
ping -c3 google.com            # internet and DNS work?
```

**To undo Method A:** delete both files, then apply. The Pi goes back to a DHCP address:

```bash
sudo rm /etc/netplan/99-wlan0-static.yaml /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
```

---

#### Method B — The `setup_network.sh` script

The script keeps the Wi-Fi network Imager set up, gives it the static address, and writes
everything into one file, `/etc/netplan/01-robot-network.yaml`.

⬇️ [setup_network.sh](code/setup_network.sh)

**1. Edit the SETTINGS block** with your values from Step 1:

```bash
cd ~/lab01
nano setup_network.sh
```

```bash
WIFI_MODE="keep"                  # keep the Wi-Fi network from Imager
WIFI_IPV4="static"
WIFI_ADDRESS="192.168.0.11/24"    # <- .11 / .12 / .13 for robot01 / 02 / 03
WIFI_GATEWAY="192.168.0.1"        # <- your router
DNS_SERVERS="192.168.0.1,8.8.8.8"
```

**2. Run it:**

```bash
sudo bash setup_network.sh
```

The script:
- stops if another device already answers on `WIFI_ADDRESS`
- backs up the current netplan files to `/etc/netplan-backups/` and writes `/etc/netplan/01-robot-network.yaml`
- checks the new file with `netplan generate` before applying it, and restores the backup if the check fails
- stops cloud-init from rewriting the network config on later boots
- keeps going even when the SSH session drops, so the change is applied in full

**3. Reconnect** after about 20 seconds, from the laptop:

```bash
ssh-keygen -R 192.168.0.11     # only if SSH complains about a changed host key
ssh ubuntu@192.168.0.11
```

Other options: `sudo bash setup_network.sh --show` prints the current config, and
`sudo bash setup_network.sh --restore` puts the previous one back (run it at the console if
the network is gone).

> **To join a different Wi-Fi network later,** set `WIFI_MODE="client"` plus `WIFI_SSID` and
> `WIFI_PASSWORD`, adjust `WIFI_ADDRESS` / `WIFI_GATEWAY` to the new router, and run the script again.

> **Ethernet still works.** With `ETH_MODE="dhcp"` (the default), plugging a cable from the
> Pi to the router gives eth0 an address too. That is a handy way back in if Wi-Fi fails.

### 4.2 Reach the Pi by name (`robot01.local`)

```bash
sudo apt update
sudo apt install -y avahi-daemon
```

From now on `ssh ubuntu@robot01.local` works from macOS, Linux and Windows 10/11 on the same network.

**Shortcut names for the fleet.** Add this to `~/.ssh/config` on the laptop (create the file
if needed). Then `ssh robot01` works, and so do `scp` and VS Code:

```
Host robot01
    HostName 192.168.0.11
Host robot02
    HostName 192.168.0.12
Host robot03
    HostName 192.168.0.13
Host robot01 robot02 robot03
    User ubuntu
```

Using the static addresses rather than `.local` names makes it work even when a network
blocks name discovery.

> **`robot01.local` doesn't resolve on the laptop, but `ssh 192.168.0.11` works?** `.local`
> names travel by multicast on `224.0.0.251`. Some routers and Wi-Fi cards drop that group in
> one direction while ROS 2's multicast (`239.255.0.1`) still gets through. Use the static
> addresses and the `~/.ssh/config` above. It doesn't affect ROS 2.

### 4.3 Check the fleet network

ROS 2 finds other machines with **multicast** on the local network, so the router must:

- carry **all three robots and the laptop** on the same subnet
- allow device-to-device traffic (no "client isolation" / "AP isolation")
- pass multicast

A home or lab router does this by default. Campus and guest Wi-Fi usually doesn't. In the
router's Wi-Fi settings, make sure *AP isolation* / *client isolation* is **off**.

Once two robots are set up, check from `robot01`:

```bash
ping -c3 192.168.0.12      # robot02
ping -c3 robot02.local     # by name (avahi)
```

### 4.4 Turn off Wi-Fi power saving

By default the Pi's Wi-Fi dozes between packets to save power. You notice it as a ping that
fails or takes a second the first time, and ROS 2 traffic between robots gets delayed.
Turn it off, now and at every boot:

```bash
sudo apt install -y iw
sudo tee /etc/systemd/system/wifi-powersave-off.service >/dev/null <<'EOF'
[Unit]
Description=Turn off Wi-Fi power saving on wlan0
Wants=sys-subsystem-net-devices-wlan0.device
After=sys-subsystem-net-devices-wlan0.device

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw dev wlan0 set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-powersave-off.service
iw dev wlan0 get power_save       # -> Power save: off
```

---

## Part 5 — Update the System

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

> **`Could not get lock /var/lib/dpkg/lock-frontend`**: on the first boot,
> `unattended-upgrades` installs security updates in the background. Wait a few minutes
> for it to finish. Don't delete the lock file.

Check the clock. The Pi 4 has **no battery-backed clock**: at every power-on it starts from
the last saved time until it reaches a time server. A wrong date makes `apt` reject
repositories with *"Release file is not valid yet"*, and makes ROS 2 timestamps from
different robots disagree:

```bash
timedatectl                                        # "System clock synchronized: yes"
sudo timedatectl set-timezone America/Vancouver    # use your own zone: timedatectl list-timezones
```

> **Robots without internet** (e.g. a dedicated router with no uplink) never synchronise.
> Keeping the three clocks in step then needs a local time server, which a later lab sets up.

---

## Part 6 — Memory Swap

Installing ROS 2 from `apt` needs little memory. **Building** packages with `colcon`
(C++ nodes especially) can run a 2–4 GB Pi out of memory, and the compiler gets killed
partway through. Ubuntu Server has no swap by default, so add some.

⬇️ [setup_swap.sh](code/setup_swap.sh)

```bash
cd ~/lab01
sudo bash setup_swap.sh
```

This sets up both kinds of swap:
- **zram**: compressed swap in RAM. It's fast and doesn't wear the SD card.
- **a 2 GB `/swapfile`** on the SD card, as a safety net for long builds.

It prints RAM + swap at the end. Aim for at least **4 GB** in total before building ROS 2 packages.

```bash
sudo bash setup_swap.sh --status      # check any time
sudo bash setup_swap.sh --uninstall   # undo
```

> **SD card wear:** the swap file is only used when RAM and zram are full, so normal use
> barely touches it. On a 2 GB Pi, you can also build with
> `colcon build --parallel-workers 1` to keep memory use down.

---

## Part 7 — Prepare for ROS 2 Humble

These are the first steps of the official ROS 2 Humble install. Doing them now means the
ROS 2 install in Lab 02 is only the ROS-specific part.

### 7.1 UTF-8 locale

```bash
locale                                    # look for UTF-8
sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
```

### 7.2 Universe repository and tools

```bash
sudo apt install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt install -y curl git htop i2c-tools gpiod usbutils iw libraspberrypi-bin
```

| Tool | Used for |
|---|---|
| `i2c-tools` | `i2cdetect`: finds the expansion board's microcontroller on the I2C bus |
| `gpiod` | `gpioinfo`: shows which GPIO pins are in use |
| `usbutils` | `lsusb`: lists USB devices (a lidar, a USB-serial IMU, a camera) |
| `iw` | Wi-Fi signal, country and power-saving state |
| `libraspberrypi-bin` | `vcgencmd`: under-voltage and throttling flags, firmware version |

---

## Part 8 — Check the robot: `robot_check.sh`

This script checks everything this lab set up, and also looks at the hardware: power,
temperature, SD card speed, the expansion board's I2C and GPIO pins, and any USB or serial
devices. It **changes nothing**.

**Do this on the robot:** fit the expansion board, unplug USB-C, and power the Pi from the
battery with the board's switch **ON** (see [Power](#power-one-source-at-a-time)). Then the
power check tests the real supply, and the I2C scan can find the board.

⬇️ [robot_check.sh](code/robot_check.sh)

```bash
cd ~/lab01
sudo bash robot_check.sh
```

It prints **PASS / WARN / FAIL / INFO** for each item. When it ends with
**"robot01 is ready for ROS 2 Humble"**, this lab is done for this robot.

| Section | What it checks |
|---|---|
| Identity | Pi 4 model, RAM, hostname (unique, and usable as a ROS namespace) |
| Power and temperature | under-voltage and throttling since boot, CPU temperature |
| Operating system | Ubuntu 22.04, arm64 |
| Memory and storage | swap, free space, SD card model and read speed |
| Network | eth0 / wlan0 addresses, Wi-Fi signal and power saving, internet, DNS, avahi, SSH, firewall |
| Time | NTP synchronised |
| Packages and locale | apt, universe, updates, tools from Part 7.2, UTF-8 |
| ROS 2 | (after Lab 02) install, `~/.bashrc`, `ROS_DOMAIN_ID`, colcon, rosdep |
| Expansion board | I2C enabled and which addresses answer, UART and serial console, GPIO |
| USB, serial, camera | `lsusb`, `/dev/ttyUSB*`, `/dev/ttyACM*`, `/dev/video*`, group permissions |

It also saves a **full report** to `~/robot_report_<hostname>_<date>.txt`: the summary plus
the raw output of every check. Copy the reports to your laptop:

```bash
# on the laptop
scp 'robot01:robot_report_*' .        # uses the ~/.ssh/config shortcut from Part 4.2
scp 'robot02:robot_report_*' .
scp 'robot03:robot_report_*' .
```

> **Keep the reports.** They record exactly what each robot has before the robot-specific
> labs start: the I2C address of the board's microcontroller, which UART the header uses,
> which USB ports a lidar or IMU will appear on. Run the script again after Lab 02 and
> after adding any hardware.

---

## Part 9 — Repeat for robot02 and robot03

Go back to Part 1 with the next SD card. What changes per robot:

| Step | robot01 | robot02 | robot03 |
|---|---|---|---|
| Imager hostname (1.3) | `robot01` | `robot02` | `robot03` |
| `WIFI_ADDRESS` (4.1) | `192.168.0.11/24` | `192.168.0.12/24` | `192.168.0.13/24` |

Everything else, including the username, the Wi-Fi network, the gateway and the scripts, is the same.
When a new robot boots, it gets a DHCP address first: find it (Part 3.1), then give it its static one (Part 4.1).

---

## Troubleshooting

| Problem | Try this |
|---------|---------|
| Nothing happens at power-on, no red LED | Check the supply. On the robot: battery charged, board switch ON |
| Red LED blinks or goes off under load; `robot_check.sh` says under-voltage | The 5 V supply is too weak: charge the battery, or use the official 3 A USB-C supply on the bench |
| Green LED blinks a pattern and it doesn't boot | The SD card isn't readable: re-flash it, or try another card |
| The Pi never appears on the router | Wrong Wi-Fi name, password or country in Imager. Check at the console (`networkctl status wlan0`), or re-flash with the right values |
| `ping` or `ssh` fails the first time, works on the next try | Wi-Fi power saving (Part 4.4), or the Pi is still booting |
| `Permission denied` at the first SSH login | cloud-init hasn't finished. Wait 2–3 minutes and try again |
| `Permission denied (publickey)` | Password login is off on the Pi. Turn it on at the console (Part 3.2.1), or check the username |
| `Permission denied (publickey,password)` | The username or password is wrong. The username is the one from Imager |
| `sudo: unable to resolve host ...` | `/etc/hosts` still has the old name on the `127.0.1.1` line (Part 2.1, step 5) |
| Hostname goes back to `ubuntu` after a reboot | Add `preserve_hostname: true` (Part 2.1, step 6) |
| `ssh: Could not resolve hostname robot01.local` | Install `avahi-daemon` (Part 4.2), or use the static IP |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Re-flashed, or another robot used that address before: `ssh-keygen -R <address>` |
| `netplan generate` error about indentation or `mapping values` | A Tab or a wrong number of spaces in the YAML. Retype the indentation with spaces (Part 4.1, Method A step 3) |
| Pi unreachable after setting the static IP | Wait a minute and try the new address. Still nothing: monitor + keyboard, then `sudo rm /etc/netplan/99-wlan0-static.yaml && sudo netplan apply` (Method A) or `sudo bash ~/lab01/setup_network.sh --restore` (Method B). No monitor? A cable from the Pi to the router gives eth0 a DHCP address to SSH into |
| Static IP works but no internet (`ping 8.8.8.8` fails) | Wrong `via` / `WIFI_GATEWAY`: it must be the router's address from `ip route` (Part 4.1, Step 1) |
| `ping 8.8.8.8` works but `ping google.com` fails | DNS: check the `nameservers` addresses |
| Another device gets the robot's address | The address is inside the router's DHCP pool (Part 4.1, Step 2) |
| `ping robot02.local` fails from `robot01`, but both have Wi-Fi | Not on the same network, or the router isolates clients (Part 4.3) |
| `Could not get lock /var/lib/dpkg/lock-frontend` | unattended-upgrades is running. Wait |
| `Release file ... is not valid yet` | The clock is wrong. Check `timedatectl` and the internet connection (Part 5) |
| `robot_check.sh`: no device on I2C bus 1 | Board not fitted, or its switch is OFF, or `dtparam=i2c_arm=on` is missing in `/boot/firmware/config.txt` |
| Build killed / `c++: fatal error: Killed signal` | Out of memory. Part 6, then `colcon build --parallel-workers 1` |

---

## Completion Checklist (per robot)

- [ ] SD card flashed with Ubuntu Server 22.04 LTS (64-bit), with hostname, user, SSH and Wi-Fi set in Imager
- [ ] Unique hostname set: `hostname` prints `robot01` / `robot02` / `robot03`
- [ ] Connected over SSH from your laptop (key-based login set up, `ssh robot01` works)
- [ ] The Pi joined the router's Wi-Fi: `ping -c3 8.8.8.8` works on the Pi
- [ ] Static IP on wlan0 (`192.168.0.11` / `.12` / `.13`), outside the router's DHCP pool
- [ ] `avahi-daemon` installed: `ssh ubuntu@robot01.local` works
- [ ] Wi-Fi power saving off: `iw dev wlan0 get power_save` says `off`
- [ ] Each robot can `ping` the other two
- [ ] System fully updated and clock synchronised
- [ ] Swap configured: `sudo bash setup_swap.sh --status`
- [ ] UTF-8 locale, `universe` repository and the Part 7.2 tools installed
- [ ] `sudo bash robot_check.sh` on battery power reports **ready for ROS 2 Humble**
- [ ] Report copied to the laptop

**Next:** [Lab 02 — ROS 2 Humble (ros-base)](../Lab_02/)
