---
layout: default
title: Home
---

# RPi4 + ROS 2 Multi-Robot
## Raspberry Pi 4 · Ubuntu Server 22.04 LTS · ROS 2 Humble · three robots

```
> Boards:  3x Raspberry Pi 4 Model B, each on a Hiwonder 4-channel motor expansion board
> OS:      Ubuntu Server 22.04 LTS (64-bit, arm64), headless
> ROS:     ROS 2 Humble, ros-base
> Fleet:   robot01, robot02, robot03 on one Wi-Fi network, one ROS_DOMAIN_ID
```

---

## Labs

| Lab | Topic |
|-----|-------|
| [Lab 01 — Raspberry Pi 4 Setup & SSH](Lab_01/) | Flash Ubuntu Server 22.04, connect over SSH, set up Ethernet and fleet Wi-Fi, update, add swap, prepare for ROS 2, and run `robot_check.sh` |
| [Lab 02 — ROS 2 Humble (ros-base)](Lab_02/) | Install `ros-humble-ros-base` and the build tools, set the fleet's `ROS_DOMAIN_ID`, talk between the three robots, one namespace per robot, a first workspace |

<!--
Planned, once the robot_check.sh reports are in:
| Lab 03 — Expansion board | I2C motor/servo controller, battery voltage, keys, LEDs, buzzer, RGB |
| Lab 04 — Sensors | USB lidar, serial IMU, camera |
-->

---

## The fleet

| Robot | Hostname | ROS namespace | eth0 (bench cable) |
|---|---|---|---|
| 1 | `robot01` | `/robot01` | `<laptop-range>.11` |
| 2 | `robot02` | `/robot02` | `<laptop-range>.12` |
| 3 | `robot03` | `/robot03` | `<laptop-range>.13` |

All three robots and the laptop share one Wi-Fi network and one `ROS_DOMAIN_ID`.

## The expansion board

The **Hiwonder RaspberryPi-Adapter-4chMotorDrive V3.x** sits on the 40-pin header. From its schematic:

| Function | Pi pins | Notes |
|---|---|---|
| 4 DC motors, 6 PWM servos, battery voltage | I2C1: GPIO2/3 (pins 3, 5) | through an on-board microcontroller; I2C also on ports P7, P8, P9 |
| Serial bus servos + port P12 | UART: GPIO14/15 (pins 8, 10) | half-duplex through a 74HC126 buffer, direction on GPIO4 / GPIO27 |
| Keys 1 and 2 | GPIO13, GPIO23 | to GND, need a pull-up |
| LED1, LED2 | GPIO16, GPIO26 | active low |
| Buzzer | GPIO6 | |
| 2× RGB (WS2812) | GPIO12 | |
| Spare ports P10, P11 | GPIO22/24, GPIO7/8 | with 5 V and GND |
| Power | 5 V pins 2, 4 | battery → switch → 5 V DC-DC → the Pi |

> **The header UART is taken.** The bus-servo buffer and port P12 share it, and the Pi 4's
> other UARTs land on pins the board already uses. Plan the lidar and the IMU as **USB**
> devices (USB-serial adapters are fine). `robot_check.sh` lists every USB and serial device it finds.

---

## Where this is going

The goal is a closed-loop, multi-agent system for the three robots, along the lines of
*A Closed-Loop Multi-Agent Framework for Robust Multi-Robot Manipulation* (He et al., 2026,
[arXiv:2607.06990](https://arxiv.org/abs/2607.06990)). The paper uses three LLM-based agents:

| Paper | Here |
|---|---|
| **Planning Agent**: turns an instruction into a dependency graph of sub-tasks and gives each to the robot best able to do it | runs off-board (laptop or server), sees the fleet through ROS 2 |
| **Manipulation Agent**, one per robot: grounds a sub-task into primitives, using perception tools | one per robot, running under that robot's namespace, with mobile primitives (move, turn, go to, dock) instead of arm primitives |
| **Verification Agent**, one per robot: checks each result, fixes execution errors locally, sends capability errors back to the planner for re-allocation | one per robot, using the robot's sensors |

The labs here build the base that needs: identical, checked robots on one ROS 2 network,
each in its own namespace.

---

## Why these versions?

**ROS 2 Humble Hawksbill** is an LTS release (supported until May 2027) whose Tier 1
platform is **Ubuntu 22.04 "Jammy"** on **arm64**. Installing Ubuntu 22.04 on the Pi 4
means ROS 2 installs as ready-built `apt` packages. You do not have to compile ROS 2
from source.
