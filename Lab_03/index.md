---
layout: default
title: "Lab 03 — Hiwonder Expansion Board SDK"
---

# Lab 03 — Hiwonder Expansion Board SDK

**Raspberry Pi 4 · Hiwonder RaspberryPi-Adapter-4chMotorDrive V3.x · Ubuntu Server 22.04 LTS · ×3 robots**

**Objectives:** Install Hiwonder's Python SDK for the expansion board (`HiwonderSDK`, from the MSE 112 course workspace) on Ubuntu 22.04, and check the board through it: battery voltage, the two RGB LEDs, the buzzer and, with the wheels off the table, the four motors.

---

## Before You Start

- **Lab 01 is done** on this robot (Lab 02 isn't needed for this lab)
- The expansion board is fitted and powered from its battery, with the switch **ON** and USB-C **unplugged** ([Lab 01, Power](../Lab_01/#power-one-source-at-a-time))
- `sudo bash robot_check.sh` shows **Expansion board found (MCU at 0x7A)** with a battery voltage

### How the SDK talks to the board

| Board function | How | SDK call |
|---|---|---|
| 4 DC motors | I2C, microcontroller at `0x7A`, registers 31–34 | `Board.setMotor(n, -100…100)` |
| 6 PWM servos | I2C `0x7A`, register 40 | `Board.setPWMServoPulse(id, 500…2500, ms)` |
| Battery voltage | I2C `0x7A`, register 0 (2 bytes, mV) | `Board.getBattery()` |
| 2 RGB LEDs (WS2812) | GPIO12 via `rpi_ws281x` | `Board.RGB.setPixelColor(i, Board.PixelColor(r, g, b))`, `Board.RGB.show()` |
| Buzzer | GPIO6 (header pin 31) via `RPi.GPIO` | `Board.setBuzzer(0/1)` |

> **Why `i2cdetect` can't see the board.** The microcontroller uses address `0x7A`, in the
> range above `0x77` that I2C reserves, and `i2cdetect` never scans there. Read it directly
> instead, the same way the SDK does: send the register number, then read in a separate transfer:
>
> ```bash
> i2ctransfer -a -y 1 w1@0x7a 0x00 && i2ctransfer -a -y 1 r2@0x7a    # battery, low byte first
> ```
>
> About one read in three comes back garbled. The SDK and `robot_check.sh` retry.

---

## Part 1 — Install the SDK

⬇️ [install_hiwonder_sdk.sh](code/install_hiwonder_sdk.sh) · ⬇️ [board_test.py](code/board_test.py)

```bash
mkdir -p ~/lab03 && cd ~/lab03
for f in install_hiwonder_sdk.sh board_test.py; do
  curl -fsSLO {{ site.github.url }}/Lab_03/code/$f
done
sudo bash install_hiwonder_sdk.sh
```

| Step | What it installs | Why |
|---|---|---|
| 1 | `git`, `python3-pip`, `python3-dev`, `gcc`, `i2c-tools`, `python3-yaml`, `python3-rpi.gpio` (apt) | `rpi_ws281x` compiles C code; `RPi.GPIO` and `yaml` come from Ubuntu |
| 2 | `smbus2`, `rpi_ws281x` (pip, for root) | I2C to the board; the RGB LEDs |
| 3 | `~/mse112-ws-student` (git clone) | `Board.py` looks for the SDK exactly there |
| 4 | an import check | |

It is safe to run again: it pulls the latest workspace instead of cloning.

> **Everything that uses the SDK runs with `sudo`.** `rpi_ws281x` drives the RGB LEDs through
> `/dev/mem`, and `Board.py` starts the LEDs as soon as it is imported. `Board.py` then finds
> the workspace in your home folder, not root's, through `SUDO_USER`.

---

## Part 2 — Check the board (nothing moves)

```bash
cd ~/lab03
sudo python3 board_test.py
```

```
PASS  battery: 12.22 V
....  RGB LEDs: red, green, blue, then off - watch the board
....  buzzer: two short beeps
```

Watch the board: both RGB LEDs go red, green, blue and off, and the buzzer beeps twice.

The course's own demos work too:

```bash
cd ~/mse112-ws-student/MasterPi/HiwonderSDK
sudo python3 RGBControlDemo.py       # colour cycle, Ctrl+C to stop
sudo python3 BuzzerControlDemo.py
```

---

## Part 3 — Motors (the wheels turn)

**Lift the robot first,** so the wheels are off the table. Then:

```bash
sudo python3 board_test.py --motors
```

Each motor turns forward, then back, at 30 % for one second, one motor at a time.
Note which wheel is motor 1, 2, 3 and 4. `Board.setMotor` flips the sign of motors 1 and 3,
so "forward" should mean the same direction for all four; if one wheel runs backwards, its
motor wires are swapped. `Ctrl+C` stops all motors.

---

## Known problems in this copy of the SDK

Found while testing on Ubuntu 22.04. These are in the workspace code, not in the install:

| Function | Problem |
|---|---|
| `Board.setPWMServoAngle(index, angle)` | Fails with `NameError: name 'servo_id' is not defined`. The parameter is `index` but the body uses `servo_id`. Use `setPWMServoPulse` instead |
| All bus-servo functions (`setBusServoPulse`, `getBusServoPulse`, …) | Fail with `NameError`: the serial bus-servo module (`BusServoCmd.py`) isn't in the workspace. `ArmIK` and `RPCServer.py` use them |
| `Board.setPWMServoPulse(2, …)` | `Deviation.yaml` has no entry for servo 2 (it drives the fan), so this raises `KeyError: '2'` |
| Serial bus servos in general | They use the header UART, which Ubuntu gives to the serial console. It must be freed first ([Lab 01, Part 8](../Lab_01/#part-8--check-the-robot-robot_checksh) reports it) |

---

## Troubleshooting

| Problem | Try this |
|---------|---------|
| `Can't open /dev/mem: Permission denied` or `ws2811_init failed` | Run with `sudo` |
| `ModuleNotFoundError: No module named 'yaml_handle'` | The workspace isn't at `~/mse112-ws-student`, or you ran as root without `sudo` (so `SUDO_USER` is empty) |
| `battery: no valid reading` / `OSError: [Errno 121] Remote I/O error` | Board not fitted, switch OFF, or battery flat |
| Battery reads well under the pack's voltage | Charge it: the motors and servos draw from the same battery |
| LEDs stay off but the battery reads fine | `rpi_ws281x` shares the PWM hardware with analog audio. If they fight, add `dtparam=audio=off` to `/boot/firmware/config.txt` and reboot |
| `pip3: command not found` | `sudo apt install python3-pip`, or re-run `install_hiwonder_sdk.sh` |

---

## Completion Checklist (per robot)

- [ ] `robot_check.sh` finds the expansion board at `0x7A` and shows the battery voltage
- [ ] `sudo bash install_hiwonder_sdk.sh` finishes with the import check OK
- [ ] `sudo python3 board_test.py`: battery PASS, both RGB LEDs cycle, buzzer beeps
- [ ] *(wheels off the table)* `sudo python3 board_test.py --motors`: all four motors turn both ways
