#!/usr/bin/env python3
"""
RPi4 Lab 03 - Check the Hiwonder expansion board through HiwonderSDK.

    sudo python3 board_test.py            # battery, RGB LEDs, buzzer - nothing moves
    sudo python3 board_test.py --motors   # also turns each motor briefly, slowly

With --motors the wheels turn: lift the robot so the wheels are off the table.
Needs sudo: the RGB LED driver (rpi_ws281x) uses /dev/mem.
"""
import os
import sys
import time

SDK = os.path.join(os.path.expanduser('~' + os.environ.get('SUDO_USER', '')),
                   'mse112-ws-student', 'MasterPi')
sys.path.insert(0, SDK)

if os.geteuid() != 0:
    sys.exit("Run with sudo:  sudo python3 board_test.py")

try:
    import HiwonderSDK.Board as Board
except Exception as e:  # missing packages, wrong path, no /dev/mem
    sys.exit(f"Could not load HiwonderSDK from {SDK}: {type(e).__name__}: {e}\n"
             "Run install_hiwonder_sdk.sh first.")

MOTOR_SPEED = 30      # percent, -100..100
MOTOR_TIME = 1.0      # seconds per direction


def battery_mv():
    """The board's MCU sometimes returns a garbled reading; retry until plausible."""
    for _ in range(6):
        try:
            mv = Board.getBattery()
        except OSError:
            continue
        if 3000 <= mv <= 20000:
            return mv
    return None


def rgb(r, g, b):
    for i in range(Board.RGB.numPixels()):
        Board.RGB.setPixelColor(i, Board.PixelColor(r, g, b))
    Board.RGB.show()


failed = False

mv = battery_mv()
if mv is None:
    print("FAIL  battery: no valid reading from the board (I2C 0x7A) - board fitted and switched ON?")
    failed = True
else:
    print(f"PASS  battery: {mv / 1000:.2f} V")

print("....  RGB LEDs: red, green, blue, then off - watch the board")
for color in ((80, 0, 0), (0, 80, 0), (0, 0, 80)):
    rgb(*color)
    time.sleep(0.7)
rgb(0, 0, 0)

print("....  buzzer: two short beeps")
for _ in range(2):
    Board.setBuzzer(1)
    time.sleep(0.1)
    Board.setBuzzer(0)
    time.sleep(0.2)

if "--motors" in sys.argv:
    print(f"....  motors 1-4 at {MOTOR_SPEED}%: forward, back, stop - one at a time")
    try:
        for m in (1, 2, 3, 4):
            print(f"      motor {m}")
            Board.setMotor(m, MOTOR_SPEED)
            time.sleep(MOTOR_TIME)
            Board.setMotor(m, -MOTOR_SPEED)
            time.sleep(MOTOR_TIME)
            Board.setMotor(m, 0)
            time.sleep(0.3)
    finally:  # also on Ctrl+C
        for m in (1, 2, 3, 4):
            Board.setMotor(m, 0)

print("\nDid the LEDs light and the buzzer beep? Then the board works through the SDK."
      if not failed else "\nFix the FAIL item first.")
sys.exit(1 if failed else 0)
