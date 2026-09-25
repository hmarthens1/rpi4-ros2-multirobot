---
layout: default
title: "Lab 01 — Raspberry Pi 4 Setup & SSH"
---

# Lab 01 — Raspberry Pi 4 Setup & SSH

**Raspberry Pi 4 · Hiwonder 4-channel motor expansion board · Ubuntu Server 22.04 LTS · ×3 robots**

**Objectives:** Flash Ubuntu Server 22.04 LTS (64-bit) to an SD card and boot the Pi 4 without a monitor. Then connect over SSH, set up networking (a static Ethernet IP for the bench and Wi-Fi for the fleet), update the system, add swap and prepare the Pi for **ROS 2 Humble (ros-base)**. Finish by running `robot_check.sh`, which writes a report of what the robot's Pi can do. Do this once per robot.

---

## Before You Start

You will need, **per robot**:
- A **Raspberry Pi 4 Model B** (2, 4 or 8 GB)
- A micro-SD card (32 GB or more, class **A1/A2**) and a card reader
- For the bench: the official **5 V 3 A USB-C** Pi 4 power supply
- On the robot: the **Hiwonder RaspberryPi-Adapter-4chMotorDrive V3.x** expansion board and its battery
- An Ethernet cable

And once: a laptop (Windows, macOS or Linux). Optional: a micro-HDMI to HDMI cable, a monitor and a USB keyboard, for setting the hostname at the console (Part 2.1) or for troubleshooting.

### Plan the fleet first

Every robot needs its own name and its own address. Decide them now and label the SD cards:

| Robot | Hostname | eth0 static IP (bench cable) | Wi-Fi |
|---|---|---|---|
| 1 | `robot01` | `<laptop-range>.11` | DHCP from the robots' router |
| 2 | `robot02` | `<laptop-range>.12` | DHCP from the robots' router |
| 3 | `robot03` | `<laptop-range>.13` | DHCP from the robots' router |

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
| General | Wireless LAN | the robots' Wi-Fi SSID + password + **Wireless LAN country** (e.g. `CA`) |
| General | Locale | your time zone and keyboard layout |
| Services | Enable SSH | ✅ *Use password authentication* (skipped? see Part 3.3.1) |

Click **Save**, then **Yes** to apply the settings, then **Write**. The write and verify take about 5–10 minutes.

> **Which Wi-Fi?** The three robots and your laptop must be on **the same network** and able
> to reach each other, because ROS 2 finds other robots by multicast. Campus and guest
> Wi-Fi usually blocks that. A small dedicated router for the robots avoids the problem
> (Part 4.3).

---

## Part 2 — First Boot

1. Insert the SD card into the Pi.
2. Plug an Ethernet cable between the Pi and your laptop, or your router.
3. Connect the **USB-C** supply (bench, expansion board off). The red LED lights and the green LED flickers while the SD card is read.

**Wait 3–5 minutes.** On first boot Ubuntu's `cloud-init` applies your Imager settings:
it creates your user, sets the hostname, joins Wi-Fi and enables SSH. It may reboot once
while it does this. If you try to log in too early, you get `Permission denied` even with
the right password. Wait, then try again.

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

While you are at the console, note the Pi's IP address. It saves searching for it in Part 3.2:

```bash
ip -br addr       # e.g. eth0  UP  192.168.137.57/24
```

> **Later changes over SSH:** the same steps (3–7) work in an SSH session too. If you
> have already installed `avahi-daemon` (Part 4.2), also run
> `sudo systemctl restart avahi-daemon` so that `<new-name>.local` resolves.

---

## Part 3 — Connect from your laptop

### 3.1 Share internet from your laptop to the Pi (over Ethernet)

This lets the Pi reach the internet through your laptop's Wi-Fi. It also gives you a
direct cable link that works on any network, including campus Wi-Fi that blocks
device-to-device traffic.

For the **first connection**, use the built-in GUI sharing. It also runs a DHCP server,
so the Pi gets an address automatically:

| Your laptop | How | Pi gets an address in |
|---|---|---|
| **Windows** | Control Panel → Network Connections → right-click *Wi-Fi* → Properties → Sharing → allow sharing with *Ethernet* | `192.168.137.x` |
| **macOS** | System Settings → General → Sharing → Internet Sharing: share *Wi-Fi* to *Ethernet/USB LAN* | `192.168.2.x` |
| **Linux (NetworkManager)** | Wired connection settings → IPv4 → **Shared to other computers** | `10.42.0.x` |

**Windows:**

<a href="https://youtu.be/Tc5ONryOa1A?si=qv7NKpMUDXcuS7nK" target="_blank">
  <img src="https://img.youtube.com/vi/Tc5ONryOa1A/hqdefault.jpg" alt="Internet sharing Windows" style="max-width:100%;">
</a>

**macOS:**

<a href="https://www.youtube.com/watch?v=tY1-dS3cICc" target="_blank">
  <img src="https://img.youtube.com/vi/tY1-dS3cICc/hqdefault.jpg" alt="Internet sharing macOS" style="max-width:100%;">
</a>

#### Script alternative (optional)

These scripts do the same thing from a terminal. Each one has a **SETTINGS block at the
top**: edit the adapter names and IP addresses to match your laptop before running it.

| Your laptop | Script | Run it with |
|---|---|---|
| Windows | ⬇️ [share_internet_windows.ps1](code/share_internet_windows.ps1) | PowerShell **as Administrator** |
| macOS | ⬇️ [share_internet_macos.sh](code/share_internet_macos.sh) | Terminal |
| Linux | ⬇️ [share_internet_linux.sh](code/share_internet_linux.sh) | Terminal |

```bash
# macOS / Linux: list adapters first, then turn sharing on (--undo turns it off)
bash share_internet_linux.sh --list
sudo bash share_internet_linux.sh
```

```powershell
# Windows - PowerShell as Administrator (-List, -Undo)
powershell -ExecutionPolicy Bypass -File share_internet_windows.ps1 -List
powershell -ExecutionPolicy Bypass -File share_internet_windows.ps1
```

> **The macOS and Linux scripts do NOT hand out addresses** (no DHCP). The Pi then has no
> IPv4 address until you give it the matching static IP (Part 4.1). You can still reach it
> over **IPv6 link-local** (Part 3.2.2) to do that, or set it at the Pi's console (Part 4.1, Method A).
> On Windows, ICS always uses `192.168.137.1` for the laptop, so the script and the GUI behave the same.

> **Sharing is cleared when your laptop reboots.** Turn it on again each session.

### 3.2 Find the Pi's IP address

Ubuntu Server doesn't advertise `robot01.local` until you install `avahi-daemon`
(Part 4.2), so for the first login you need an address. Which method works depends on
whether your laptop **hands out** addresses on the cable (DHCP):

| Laptop sharing | Does the Pi get an IPv4 address? | Use |
|---|---|---|
| Windows ICS, macOS Internet Sharing, Linux "Shared to other computers" (GUI) | Yes, automatically | **3.2.1**, IPv4 |
| `share_internet_*.sh` scripts, or a laptop port set to a manual IP | **No.** The Pi sits waiting for an address that never comes | **3.2.2**, IPv6 link-local |
| Pi joined Wi-Fi (set in Imager) | Yes, from the router | router's "connected devices" page, looking for `robot01` |

**How to recognise the Pi:** its hardware (MAC) address starts with a Raspberry Pi prefix:
`dc:a6:32`, `e4:5f:01`, `d8:3a:dd`, `28:cd:c1`, `2c:cf:67` or `b8:27:eb`.
Windows shows these with dashes, e.g. `dc-a6-32-…`.

#### 3.2.1 IPv4: when the laptop hands out addresses

| Laptop | Command | Look for |
|---|---|---|
| **Windows** (ICS) | PowerShell: `arp -a` | under `Interface: 192.168.137.1`, a `192.168.137.x` entry with a Pi MAC |
| **macOS** | Terminal: `arp -a \| grep 192.168.2` | a `192.168.2.x` entry with a Pi MAC |
| **Linux** (Shared) | `ip neigh show dev <ethernet-if>` | a `10.42.0.x` entry with a Pi MAC |
| any | `nmap -sn 192.168.137.0/24` (use your range) | a host with a Pi MAC |

#### 3.2.2 IPv6 link-local: works even when the Pi has no IPv4 at all

Every Ethernet port gives itself an **IPv6 link-local address** (it starts with `fe80::`) as
soon as a cable is plugged in. It doesn't need DHCP, a router or any setup. Ubuntu builds
it from the MAC address, so it **never changes**. That makes it a reliable way into a
Pi that has no IPv4 address, or the wrong one.

The trick is to ping **`ff02::1`**, the IPv6 "everyone on this cable" address, and see who replies.

**1. Find the name of your laptop's Ethernet interface.** A link-local address only means
something together with the interface it lives on.

| Laptop | Command | Typical name |
|---|---|---|
| **Linux** | `ip -br link` | `enp130s0`, `eth0`, `enx…` (USB adapter) |
| **macOS** | `networksetup -listallhardwareports` | `en5`, `en6`, `en7` (USB-C Ethernet adapter) |
| **Windows** | PowerShell: `Get-NetAdapter` | use the **ifIndex** number of *Ethernet*, e.g. `12` |

**2. Ping everyone on the cable, then list who answered.** Replace `enp130s0`, `en5` or `12` with yours:

**Linux:**

```bash
ping -6 -c3 ff02::1%enp130s0
ip -6 neigh show dev enp130s0
```

**macOS:**

```bash
ping6 -c3 ff02::1%en5
ndp -an | grep en5
```

**Windows (PowerShell):**

```powershell
ping -6 -n 3 ff02::1%12
Get-NetNeighbor -InterfaceIndex 12 -AddressFamily IPv6 | Where-Object LinkLayerAddress -ne "" | Format-Table IPAddress, LinkLayerAddress, State
```

**3. Pick out the Pi.** One of the replies is the laptop itself. The Pi's line shows a Pi MAC (the state at the end may say `REACHABLE`, `STALE` or `DELAY`; any of them is fine). Example from a Linux laptop:

```
$ ping -6 -c3 ff02::1%enp130s0
64 bytes from fe80::6914:41ea:6e9:c4a0%enp130s0: icmp_seq=1 ttl=64 time=0.046 ms   <- the laptop
64 bytes from fe80::dea6:32ff:fe45:dcb7%enp130s0: icmp_seq=1 ttl=64 time=0.540 ms  <- the Pi
$ ip -6 neigh show dev enp130s0
fe80::dea6:32ff:fe45:dcb7 lladdr dc:a6:32:45:dc:b7 REACHABLE                       <- Pi MAC
```

**4. Use it: always add `%<interface>` at the end.**

```bash
ssh ubuntu@fe80::dea6:32ff:fe45:dcb7%enp130s0                  # Windows: ...%12
scp setup_network.sh 'ubuntu@[fe80::dea6:32ff:fe45:dcb7%enp130s0]:~/lab01/'   # scp needs [ ] and quotes
```

Now use Part 4.1 to give the Pi a proper IPv4 address in your laptop's range.

> **Is SSH even running?** Check the port before you worry about passwords:
> `nc -zv fe80::dea6:32ff:fe45:dcb7%enp130s0 22` (Linux/macOS) should report *succeeded* / *open*.
> On Windows: `Test-NetConnection fe80::dea6:32ff:fe45:dcb7%12 -Port 22`.

> **Nothing but the laptop answers?** Check the cable and the Pi's Ethernet LEDs, and
> give the Pi a few minutes after power-on. On Windows, the neighbour list sometimes stays
> empty even when the Pi is there. In that case, use the monitor and run `ip -br addr` on the Pi (Part 2.1).

### 3.3 SSH in

```bash
ssh ubuntu@<PI_IP>          # e.g. ssh ubuntu@192.168.137.57, or the fe80::…%<if> address
```

Use the username you set in Imager. Type `yes` to accept the host key the first time, then your password.

> **"REMOTE HOST IDENTIFICATION HAS CHANGED"** after re-flashing is expected: the new OS
> has new keys. Clear the old one with `ssh-keygen -R <PI_IP>` (and `ssh-keygen -R robot01.local`).
> You will see this often with three robots moving between addresses.

#### 3.3.1 `Permission denied (publickey)`: turn on password login

```
$ ssh ubuntu@fe80::dea6:32ff:fe45:dcb7%enp130s0
ubuntu@fe80::dea6:32ff:fe45:dcb7%enp130s0: Permission denied (publickey).
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

Next, set up SSH keys (Part 3.4). After that you can switch password login off again for
security with `sudo rm /etc/ssh/sshd_config.d/01-password-auth.conf && sudo systemctl restart ssh`.

> **Wrong username gives the same error.** If the account doesn't exist, SSH still says
> `Permission denied (publickey)` when passwords are off. Check it with `whoami` at the console.

### 3.4 Log in without a password (SSH keys)

From your **laptop** (not the Pi). Create the key once, then copy it to each robot:

```bash
ssh-keygen -t ed25519                  # once; press Enter to accept the defaults
ssh-copy-id ubuntu@<PI_IP>             # macOS / Linux, once per robot
```

On Windows, where `ssh-copy-id` doesn't exist, run this in PowerShell:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@<PI_IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

**Shortcut names for the fleet.** Add this to `~/.ssh/config` on the laptop (create the file
if needed). Then `ssh robot01` works, and so do `scp` and VS Code:

```
Host robot01 robot02 robot03
    HostName %h.local
    User ubuntu
```

`%h.local` needs `avahi-daemon` on the robots (Part 4.2).

### 3.5 VS Code Remote-SSH

For a graphical editor on files that live on the Pi, install the **Remote - SSH**
extension in VS Code and connect to `ubuntu@<PI_IP>` (or `robot01` with the config above):

<a href="https://youtu.be/RLd6qgRHVh0" target="_blank">
  <img src="https://img.youtube.com/vi/RLd6qgRHVh0/hqdefault.jpg" alt="SSH with VSCode" style="max-width:100%;">
</a>

### 3.6 Get the lab scripts onto the Pi

Several later steps run a script **on the Pi**. The scripts are published on this site, so
they start out on the internet and not on the Pi. Use whichever of these three ways fits
your situation:

| Way | Needs | Best when |
|---|---|---|
| **A. Download on the Pi** (`curl`) | Pi has internet | You can SSH in and `ping 8.8.8.8` works on the Pi |
| **B. Copy from your laptop** (`scp`) | SSH from laptop to Pi | You can SSH in, but the Pi has no internet |
| **C. Copy via the SD card** | Nothing: no network at all | You can't SSH in yet (e.g. the Pi isn't in your laptop's range) |

#### A. Download directly on the Pi

In an SSH session or at the Pi's console:

```bash
mkdir -p ~/lab01 && cd ~/lab01
for f in setup_network.sh setup_swap.sh robot_check.sh; do
  curl -fsSLO {{ site.github.url }}/Lab_01/code/$f
done
ls
```

#### B. Copy from your laptop with `scp`

1. On your **laptop**, click the ⬇️ links on this page to download the scripts. They land in
   your `Downloads` folder: [setup_network.sh](code/setup_network.sh),
   [setup_swap.sh](code/setup_swap.sh), [robot_check.sh](code/robot_check.sh).
   If the browser opens the file as text instead, right-click the link → **Save link as…**
2. Open a terminal on the **laptop**. On Windows use PowerShell. Go to the Downloads folder:

   ```bash
   cd ~/Downloads             # Windows PowerShell: cd $HOME\Downloads
   ```

3. Create the folder on the Pi, then copy the files into it. Replace `<PI_IP>` with its address:

   ```bash
   ssh ubuntu@<PI_IP> "mkdir -p ~/lab01"
   scp setup_network.sh setup_swap.sh robot_check.sh ubuntu@<PI_IP>:~/lab01/
   ```

4. Check on the Pi: `ls ~/lab01`

#### C. Copy through the SD card (no network needed)

The SD card's first partition, **`system-boot`**, is a normal FAT drive that Windows, macOS and
Linux can all read and write. Anything you copy there shows up on the Pi under `/boot/firmware/`.

1. On the Pi run `sudo poweroff`, wait until the green LED stops, unplug the power, and take out the SD card.
2. Put the SD card in your laptop. A drive called **`system-boot`** appears.
   > **Windows may also say *"You need to format the disk in drive X: before you can use it"*.**
   > That is the Linux partition, which Windows can't read. Click **Cancel**. Formatting
   > it would erase Ubuntu.
3. Drag the downloaded scripts onto the `system-boot` drive, then **eject** it properly before removing the card.
4. Put the card back in the Pi and power on. At the Pi console, or over SSH:

   ```bash
   mkdir -p ~/lab01
   cp /boot/firmware/*.sh ~/lab01/
   ls ~/lab01
   ```

---

## Part 4 — Networking

Ubuntu Server doesn't use `/etc/dhcpcd.conf` (a Raspberry Pi OS file). Networking is set by
**netplan** YAML files in `/etc/netplan/`.

The robots use two links:
- **eth0**, a cable to your laptop on the bench, with a fixed address (4.1), for setup and rescue
- **wlan0**, Wi-Fi to the robots' router (4.3), which is how the three robots and the laptop talk ROS 2 to each other

### 4.1 Static IP on eth0, in your laptop's shared range

When your laptop shares its internet over Ethernet, the cable becomes a small network with
the **laptop as the gateway**. The Pi must have an address on that same network, meaning the
same first three numbers, and must use the laptop's address as its gateway. A fixed
(static) address also means you always SSH to the same IP.

#### Step 1 — Find your laptop's address on the Ethernet link

Turn internet sharing on (Part 3.1) with the cable plugged in, then on the **laptop**:

| Laptop | Command | Look for |
|---|---|---|
| **Windows** | `ipconfig` (PowerShell) | the *Ethernet adapter* section → **IPv4 Address**, e.g. `192.168.137.1` |
| **macOS** | `ifconfig bridge100 \| grep "inet "` (GUI sharing) or `ifconfig en5 \| grep "inet "` (script) | `inet 192.168.2.1` |
| **Linux** | `ip -br addr` | your Ethernet interface (`enp…`/`eth…`), e.g. `10.42.0.1/24` |

**The rule:** keep the first three numbers, and make the last one **10 + the robot number**:
`robot01` → `.11`, `robot02` → `.12`, `robot03` → `.13`.

| If the laptop is… | then `robot01` gets `ETH_ADDRESS` | and `ETH_GATEWAY` |
|---|---|---|
| `192.168.137.1` (Windows ICS) | `192.168.137.11/24` | `192.168.137.1` |
| `192.168.2.1` (macOS Internet Sharing) | `192.168.2.11/24` | `192.168.2.1` |
| `10.42.0.1` (Linux "Shared to other computers") | `10.42.0.11/24` | `10.42.0.1` |
| `192.168.0.1` (macOS / Linux script) | `192.168.0.11/24` | `192.168.0.1` |
| anything else, e.g. `a.b.c.1` | `a.b.c.11/24` | `a.b.c.1` |

Write your values down. The examples below use the Windows row and `robot01`.

#### Step 2 — Set it on the Pi: pick Method A or B

| | Method A — at the Pi console | Method B — the script over SSH |
|---|---|---|
| Needs | monitor + USB keyboard (Part 2.1) | an SSH session to the Pi already working |
| Use it when | you **can't** reach the Pi over the network yet | you **can** already SSH in: over Wi-Fi, via a GUI-sharing address, or over IPv6 link-local (Part 3.2.2) |

---

#### Method A — Write the netplan file by hand (monitor + keyboard)

This needs no network and no script: you type the config directly on the Pi.

**1.** Log in at the console (see Part 2.1) and look at the existing network files:

```bash
ls /etc/netplan/
# usually: 50-cloud-init.yaml   (written on first boot from your Imager settings)
```

**2.** Create a new file. Its name starts with `99-` so it is read *last* and overrides the
eth0 settings in `50-cloud-init.yaml`. Your Wi-Fi settings in that file are left alone.

```bash
sudo nano /etc/netplan/99-eth0-static.yaml
```

**3.** Type this in, using **your** values from Step 1:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.137.11/24]
      routes:
        - to: default
          via: 192.168.137.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      optional: true
```

> **YAML is strict about indentation.** Use **spaces, never Tab**, exactly 2 per level as
> shown. `addresses` and `routes` line up under `dhcp4`, and `- to:` is indented under `routes:`.

Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

**4.** Lock down the file's permissions (netplan warns otherwise) and stop cloud-init from
rewriting the network config on later boots:

```bash
sudo chmod 600 /etc/netplan/99-eth0-static.yaml
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

**5.** Check the file, then apply it:

```bash
sudo netplan generate          # no output = no mistakes. An error names the line to fix.
sudo netplan apply
```

**6.** Test it:

```bash
ip -br addr show eth0          # -> eth0  UP  192.168.137.11/24
ping -c3 192.168.137.1         # the laptop answers?
ping -c3 8.8.8.8               # the internet answers?
```

**7.** From your **laptop**, you can now SSH in:

```bash
ssh ubuntu@192.168.137.11
```

**To undo Method A:** delete both files, then apply:

```bash
sudo rm /etc/netplan/99-eth0-static.yaml /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
```

---

#### Method B — The `setup_network.sh` script (over SSH)

The script writes the same kind of netplan file, plus a backup, validation and the hotspot option (Part 4.4).

**1. Get the script onto the Pi** (details in [Part 3.6](#36-get-the-lab-scripts-onto-the-pi)). The quickest way, run on your **laptop** from the folder you downloaded it to:

```bash
ssh ubuntu@<CURRENT_PI_IP> "mkdir -p ~/lab01"
scp setup_network.sh ubuntu@<CURRENT_PI_IP>:~/lab01/
```

With an IPv6 link-local address, `scp` needs brackets and quotes:
`scp setup_network.sh 'ubuntu@[fe80::…%enp130s0]:~/lab01/'`

⬇️ [setup_network.sh](code/setup_network.sh)

**2. SSH in and edit the SETTINGS block** with your values from Step 1:

```bash
ssh ubuntu@<CURRENT_PI_IP>
cd ~/lab01
nano setup_network.sh
```

```bash
ETH_MODE="static"
ETH_ADDRESS="192.168.137.11/24"     # <- your value: .11 / .12 / .13 for robot01 / 02 / 03
ETH_GATEWAY="192.168.137.1"         # <- your value
```

**3. Run it:**

```bash
sudo bash setup_network.sh
```

The script:
- backs up the current netplan files and writes one file, `/etc/netplan/01-robot-network.yaml`
- keeps the Wi-Fi network you set in Imager (`WIFI_MODE="keep"`)
- checks the new file with `netplan generate` before applying it, and restores the backup if the check fails
- stops cloud-init from rewriting the network config on later boots

**4. Reconnect.** If you were connected over the cable, the session drops when the address
changes. That is expected. From the laptop:

```bash
ssh ubuntu@192.168.137.11      # the ETH_ADDRESS you chose
ping -c3 8.8.8.8               # on the Pi: internet works?
```

> **Plugging eth0 into a router instead of your laptop?** With Method A, delete
> `99-eth0-static.yaml` and run `sudo netplan apply`. With Method B, set `ETH_MODE="dhcp"` and re-run
> the script. A static `192.168.137.11` has no route on a normal router network.

Other options: `sudo bash setup_network.sh --show` prints the current config, and
`--restore` puts the previous one back.

### 4.2 Reach the Pi by name (`robot01.local`)

```bash
sudo apt update
sudo apt install -y avahi-daemon
```

From now on `ssh ubuntu@robot01.local` works from macOS, Linux and Windows 10/11 on the same network.

### 4.3 Wi-Fi for the fleet

On the robot there is no cable, so the robots reach each other and your laptop over Wi-Fi.
ROS 2 finds other machines with **multicast** on the local network, so this network must:

- carry **all three robots and the laptop** on the same subnet
- allow device-to-device traffic (no "client isolation" / "AP isolation")
- pass multicast

Campus and guest Wi-Fi usually fails the last two. The reliable setup is a **small
dedicated router** for the robots, with its internet port plugged into the building network if you want internet.
In the router's settings, turn off *AP/client isolation* and give each robot's MAC a **DHCP
reservation**, so `robot01` always gets the same Wi-Fi address.

**If you set Wi-Fi in Imager,** it is already configured. Check it:

```bash
ip -br addr show wlan0         # -> wlan0  UP  192.168.1.101/24
```

**To join a different network later,** use `setup_network.sh`:

```bash
WIFI_MODE="client"
WIFI_SSID="robots-5g"
WIFI_PASSWORD="your-password"
```

```bash
sudo bash setup_network.sh
```

Then check that the robots can see each other, from `robot01`:

```bash
ping -c3 robot02.local
ping -c3 robot03.local
```

### 4.4 Optional — Wi-Fi hotspot on the Pi

Make one Pi broadcast its own Wi-Fi network so a laptop can connect with no router or
cable. **Do this while connected over Ethernet.** Hotspot mode replaces the Wi-Fi client
connection, so this Pi then gets internet only through eth0, and it drops out of the
robots' Wi-Fi from Part 4.3. Use it for a single robot on the bench, not for the fleet.

In the SETTINGS block of `setup_network.sh`:

```bash
WIFI_MODE="ap"
AP_SSID="$(hostname)"         # the network name = your hostname, e.g. robot01
AP_PASSWORD="choose-8+-chars"
```

```bash
sudo bash setup_network.sh
```

The script installs **NetworkManager**, which netplan needs to run a hotspot, and runs it on
wlan0 only. eth0 stays on the default networking service, systemd-networkd. Join the
`robot01` Wi-Fi network from your laptop, then:

```bash
ssh ubuntu@10.42.0.1
```

To go back to a Wi-Fi client, set `WIFI_MODE="client"` plus `WIFI_SSID` / `WIFI_PASSWORD`
and run the script again.

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
scp 'robot01:robot_report_*' .        # uses the ~/.ssh/config shortcut from Part 3.4
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
| `ETH_ADDRESS` (4.1) | `a.b.c.11/24` | `a.b.c.12/24` | `a.b.c.13/24` |
| Router DHCP reservation (4.3) | its MAC | its MAC | its MAC |

Everything else, including the username, the Wi-Fi network and the scripts, is the same.
**Only one robot on the bench cable at a time**: they all use the laptop as gateway, but
each has its own address.

---

## Troubleshooting

| Problem | Try this |
|---------|---------|
| Nothing happens at power-on, no red LED | Check the supply. On the robot: battery charged, board switch ON |
| Red LED blinks or goes off under load; `robot_check.sh` says under-voltage | The 5 V supply is too weak: charge the battery, or use the official 3 A USB-C supply on the bench |
| Green LED blinks a pattern and it doesn't boot | The SD card isn't readable: re-flash it, or try another card |
| `Permission denied` at the first SSH login | cloud-init hasn't finished. Wait 2–3 minutes and try again |
| `sudo: unable to resolve host ...` | `/etc/hosts` still has the old name on the `127.0.1.1` line (Part 2.1, step 5) |
| Hostname goes back to `ubuntu` after a reboot | Add `preserve_hostname: true` (Part 2.1, step 6) |
| `ssh: Could not resolve hostname robot01.local` | Install `avahi-daemon` (Part 4.2) or use the IP address |
| Can't find the Pi's IP | Ping `ff02::1%<your-ethernet-if>` and use the Pi's `fe80::` address (Part 3.2.2); or plug in HDMI + keyboard and run `ip -br addr` |
| Pi answers on IPv6 but has no `192.168.x.x` address | Your laptop doesn't hand out addresses (script or manual IP). SSH in over `fe80::…%<if>` and set the static IP (Part 4.1) |
| `Permission denied (publickey)` | Password login is off on the Pi. Turn it on at the console (Part 3.3.1), or check the username |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Re-flashed, or another robot now has that address: `ssh-keygen -R <address>` |
| Sharing works but the Pi is in a different range from the laptop | Part 4.1: find the laptop's Ethernet address, then set the Pi's static IP (Method A needs only a monitor and keyboard) |
| `netplan generate` error about indentation or `mapping values` | A Tab or a wrong number of spaces in the YAML. Retype the indentation with spaces (Part 4.1, Method A step 3) |
| Lost SSH after `setup_network.sh` | Reconnect to `ETH_ADDRESS`. If that fails, put the SD card in your laptop, delete `/etc/netplan/01-robot-network.yaml` on the `writable` partition and copy the backup from `/etc/netplan-backups/` |
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
- [ ] Internet shared from the laptop: `ping -c3 8.8.8.8` works on the Pi
- [ ] Static IP on eth0 (`.11` / `.12` / `.13`)
- [ ] `avahi-daemon` installed: `ssh ubuntu@robot01.local` works
- [ ] On the robots' Wi-Fi: each robot can `ping` the other two by name
- [ ] System fully updated and clock synchronised
- [ ] Swap configured: `sudo bash setup_swap.sh --status`
- [ ] UTF-8 locale, `universe` repository and the Part 7.2 tools installed
- [ ] `sudo bash robot_check.sh` on battery power reports **ready for ROS 2 Humble**
- [ ] Report copied to the laptop

**Next:** [Lab 02 — ROS 2 Humble (ros-base)](../Lab_02/)
