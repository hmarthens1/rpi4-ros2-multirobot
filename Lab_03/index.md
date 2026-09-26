---
layout: default
title: "Lab 03 — Expansion Board Driver"
---

# Lab 03 — Expansion Board Driver

**Raspberry Pi 4 · Hiwonder RaspberryPi-Adapter-4chMotorDrive V3.x · Ubuntu Server 22.04 LTS · ×3 robots**

**Objectives:** Install the fleet's own driver for the expansion board,
**[rpi4-robot-board](https://github.com/hmarthens1/rpi4-robot-board)**, check the board
through it (battery, RGB LEDs, buzzer, LEDs, keys, ultrasonic sensor, motors), and start the
two ROS 2 nodes every robot runs: **`robot_status`** (publishes status) and **`robot_command`**
(carries out commands from the laptop, with safety limits).

---

## Before You Start

- **Lab 01 and Lab 02 are done** on this robot
- The expansion board is fitted and powered from its battery, with the switch **ON** and USB-C **unplugged** ([Lab 01, Power](../Lab_01/#power-one-source-at-a-time))
- `sudo bash robot_check.sh` shows **Expansion board found (MCU at 0x7A)** with a battery voltage

### Why a new driver

Hiwonder's `HiwonderSDK/Board.py` works, but it must live in a fixed folder, starts the RGB
driver as soon as it is imported (so everything needs `sudo`), and has functions that crash
(`setPWMServoAngle`, the bus-servo functions). `rpi4-robot-board` speaks **the same I2C
protocol** (its tests check it sends identical bytes, and it was cross-checked against
`Board.py` in 48 cases) and fixes those problems.

| Board function | How | In `robot_board` |
|---|---|---|
| 4 DC motors | I2C, microcontroller at `0x7A`, registers 31–34 | `Board().set_motor(n, -100…100)` |
| 6 PWM servos | I2C `0x7A`, register 40 | `Board().set_servo_pulse(id, 500…2500, ms)`, `set_servo_angle` |
| Battery voltage | I2C `0x7A`, register 0 | `Board().battery_v()` |
| 2 RGB LEDs (WS2812) | GPIO12 via `rpi_ws281x`, needs root | `peripherals.RGB()` |
| Buzzer, LED1/LED2, Key1/Key2 | GPIO6, GPIO16/26, GPIO13/23 | `peripherals.Buzzer()`, `Leds()`, `Keys()` |
| Ultrasonic module (add-on) | I2C `0x77` | `sonar.Sonar().distance_mm()` |

> **Why `i2cdetect` can't see the board.** Its microcontroller uses address `0x7A`, above
> `0x77`, the top of `i2cdetect`'s scan. Read it directly the way the driver does:
> `i2ctransfer -a -y 1 w1@0x7a 0x00 && i2ctransfer -a -y 1 r2@0x7a` (battery, low byte first).

---

## Part 1 — Install the driver

```bash
git clone https://github.com/hmarthens1/rpi4-robot-board.git ~/rpi4-robot-board
cd ~/rpi4-robot-board
sudo bash scripts/install.sh
```

It installs `robot_board` system-wide, so `python3` and `sudo python3` can both import it and
the `robot-board` command is on the `PATH`. Update later with
`git pull && sudo bash scripts/install.sh`.

## Part 2 — Check the board (nothing moves)

```bash
robot-board battery          # e.g. 12.22 V - no sudo needed
sudo robot-board test        # battery, RGB LEDs, buzzer, LED1/LED2
robot-board keys             # press Key1/Key2 on the board, Ctrl+C to stop
robot-board sonar            # only with the ultrasonic module, Ctrl+C to stop
```

## Part 3 — Motors (the wheels turn)

**Lift the robot first,** so the wheels are off the table:

```bash
sudo robot-board test --motors
```

Each motor turns forward, then back, at 30 % for one second. Note which wheel is motor 1–4.
If one wheel turns the wrong way, override its polarity:
`Board(motor_polarity={3: 1})`.

## Part 4 — The robot's ROS 2 nodes

```bash
cd ~/rpi4-robot-board
sudo bash scripts/install_status_service.sh
```

This builds the `robot_status` package in `~/ros2_ws` and starts two services at every boot,
in the namespace `/<hostname>`:

| Service | Node | Topics |
|---|---|---|
| `robot-status` | `status_node` (as your user) | `/robot01/battery`, `/robot01/system`, `/robot01/sonar/range` |
| `robot-command` | `command_node` (as root, for the RGB LEDs) | `/robot01/command` in, `/robot01/command_result` out, `/robot01/cmd_vel` in |

`command_node` carries out JSON commands (`drive`, `motor`, `servo`, `led`, `rgb`, `buzzer`,
`stop`, `status`) and enforces its own limits whatever the sender asks: speed capped at 50 %,
each motion at most 5 s and then it stops by itself, `stop` always wins, and the limits can't
be changed with `ros2 param set` while it runs.

From the laptop (with `ROS_DOMAIN_ID=17` and Fast DDS):

```bash
ros2 topic echo /robot01/battery
ros2 topic pub --once /robot01/command std_msgs/msg/String '{data: "{\"action\": \"buzzer\", \"times\": 2}"}'
ros2 topic echo /robot01/command_result
```

The laptop apps that use these nodes (the fleet dashboard and push-to-talk voice control) are
in `~/Desktop/robot-fleet-gui` on the laptop.

---

## Troubleshooting

| Problem | Try this |
|---------|---------|
| `robot-board battery`: no valid reading | Board not fitted, switch OFF, or battery flat |
| `ws2811_init failed` / `/dev/mem` permission | The RGB LEDs need `sudo` |
| `robot-command` shows `RGB no (not root)` | The service must run as root: re-run `install_status_service.sh` |
| A service keeps restarting | `journalctl -u robot-command -e` (or `robot-status`) |
| Topics don't show on the laptop | Same `ROS_DOMAIN_ID` (17) and `RMW_IMPLEMENTATION=rmw_fastrtps_cpp` on the laptop |

---

## Completion Checklist (per robot)

- [ ] `robot_check.sh` finds the expansion board at `0x7A` and shows the battery voltage
- [ ] `sudo bash scripts/install.sh` ends with "board answers: battery …"
- [ ] `sudo robot-board test`: RGB LEDs cycle, buzzer beeps, LED1/LED2 blink
- [ ] *(wheels off the table)* `sudo robot-board test --motors`: all four motors turn both ways
- [ ] `robot-status` and `robot-command` services running; the laptop sees `/<robot>/battery`
