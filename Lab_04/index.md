---
layout: default
title: "Lab 04 — Camera Vision: OpenCV, Lane Tracking, YOLOX"
---

# Lab 04 — Camera Vision: OpenCV, Lane Tracking, YOLOX

**Raspberry Pi 4 · USB camera · Ubuntu Server 22.04 LTS · ROS 2 Humble · ×3 robots**

**Objectives:** Install OpenCV and the ncnn neural-network runtime, start the robot's camera
node **`robot_vision`** from [rpi4-robot-board](https://github.com/hmarthens1/rpi4-robot-board),
track a coloured line, and detect objects with YOLOX.

---

## Before You Start

- **Lab 03 is done** on this robot (`robot-status` and `robot-command` running)
- The USB camera is plugged in: `v4l2-ctl --list-devices` shows a `uvcvideo` camera
- About 1 GB free disk space

### How this differs from the MSE112 setup

The MSE112 labs build OpenCV 4.10 from source (about 1.5 h) on Raspberry Pi OS. Here OpenCV
comes from **Ubuntu's packages (4.5.4)**, because that is the version ROS 2 Humble's
`cv_bridge` is built against: two OpenCVs in one program would clash. It already includes
V4L2, GStreamer and NEON. YOLOX runs on **ncnn**, as in the MSE112 project, with the same model
files (checked by SHA-256).

## Part 1 — Install

```bash
cd ~/rpi4-robot-board && git pull
sudo bash scripts/install_vision.sh
```

| Step | What | Time on a Pi 4 |
|---|---|---|
| 1 | OpenCV, v4l-utils, cv_bridge (apt) | a few minutes |
| 2 | ncnn, built from source at a pinned release, without the ARMv8.2+ code paths a Pi 4 can't use | about 12 min |
| 3 | YOLOX nano and tiny models (COCO) into `/usr/local/share/robot_vision/models` | seconds |
| 4 | builds `robot_vision`, runs its tests, starts the `robot-vision` service | about 2 min |

Log out and in once (the script adds you to the `video` group).

## Part 2 — Check the speed

```bash
sudo systemctl stop robot-vision
~/ros2_ws/install/robot_vision/lib/robot_vision/vision_bench
sudo systemctl start robot-vision
```

Measured on robot01 (Pi 4, 4 GB, not throttled):

| | ms per frame | frames/s |
|---|---|---|
| Lane tracking, 640×480 | 2.8 | (camera-limited: 15–20) |
| YOLOX nano, 3 threads | 124 | 8.1 |
| YOLOX nano, 4 threads | 112 | 8.9 |
| YOLOX tiny, 3 threads | 274 | 3.7 |

The node uses 3 threads for YOLOX, keeping one core for the camera, lane tracking and ROS.

## Part 3 — Lane tracking

Put a strip of coloured tape (yellow by default) on the floor in front of the robot.

```bash
ros2 topic echo /robot01/vision/lane
```

`offset` goes from −1 (line at the far left) to 1 (far right); `angle_deg` is positive when
the line bends to the right further ahead. Change the colour:

```bash
ros2 topic pub --once /robot01/vision/control std_msgs/String '{data: "{\"color\": \"blue\"}"}'
```

Presets: yellow, blue, green, red, black, white; or your own `"hsv": [h, s, v, h, s, v]`.
In the dashboard's **Vision** tab, set *Picture* to **mask** to see what matches (white).

**Following** (wheels on the floor, room to move): the Vision tab's **Follow** button, or
`{"follow": true, "speed": 0.25}`. It stops by itself when the line is lost for 1 s, and on any
STOP; `command_node` still caps the speed and stops at obstacles. Check the steering direction
at low speed first.

## Part 4 — Object detection

```bash
ros2 topic pub --once /robot01/vision/control std_msgs/String '{data: "{\"detect\": true}"}'
ros2 topic echo /robot01/vision/detections
```

Detection is off at start: it keeps three cores busy. `"model": "tiny"` is more accurate and
about 2× slower; `"classes": ["cup", "bottle"]` keeps only those.

## Troubleshooting

| Problem | Try this |
|---|---|
| `vision/state` shows no camera | `v4l2-ctl --list-devices`; the node looks again every 5 s |
| No picture in the dashboard | `RMW_IMPLEMENTATION=rmw_fastrtps_cpp` on the laptop; the Vision tab must be open |
| Lane not found | *Picture: mask*; adjust the colour, or lower `roi_top` to search higher in the image |
| `detect off: model missing` | re-run `sudo bash scripts/install_vision.sh` |

## Completion Checklist (per robot)

- [ ] `install_vision.sh` ends with "robot-vision running"
- [ ] `vision_bench` runs and finds cars and people in the sample image
- [ ] The dashboard's Vision tab shows the camera picture
- [ ] Coloured tape gives `found: true` with a sensible offset
- [ ] `{"detect": true}` gives detections of objects in view
