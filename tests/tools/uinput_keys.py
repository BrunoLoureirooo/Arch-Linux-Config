#!/usr/bin/env python3
"""Press a key combination through a throwaway uinput keyboard.

    python3 tests/tools/uinput_keys.py LEFTCTRL 3
    python3 tests/tools/uinput_keys.py LEFTCTRL LEFTALT RIGHT

press(*keys) creates a virtual keyboard named "rice-test", waits for libinput to
pick it up, presses the keys in order, releases them in reverse, and destroys the
device. Key names are evdev KEY_* names without the prefix (LEFTCTRL, 2, LEFT).

WARNING: a uinput device is seen by the compositor that owns the seat, i.e. the
LIVE session. The test rig must use tests/rig/keys.sh (wtype) instead.
"""
import fcntl
import os
import struct
import sys
import time

EV_SYN, EV_KEY, SYN_REPORT = 0, 1, 0
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_SETUP = 0x405C5503
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
BUS_VIRTUAL = 0x06
DEVICE_NAME = "rice-test"

_KEYS = {
    "ESC": 1, "MINUS": 12, "EQUAL": 13, "BACKSPACE": 14, "TAB": 15, "ENTER": 28,
    "LEFTCTRL": 29, "LEFTSHIFT": 42, "RIGHTSHIFT": 54, "LEFTALT": 56, "SPACE": 57,
    "GRAVE": 41, "BACKSLASH": 43, "RIGHTCTRL": 97, "SYSRQ": 99, "PRINT": 99, "RIGHTALT": 100,
    "HOME": 102, "UP": 103, "PAGEUP": 104, "LEFT": 105, "RIGHT": 106, "END": 107,
    "DOWN": 108, "PAGEDOWN": 109, "DELETE": 111, "LEFTMETA": 125, "RIGHTMETA": 126,
}
_KEYS.update({str(d): d + 1 for d in range(1, 10)})  # 1..9 -> 2..10
_KEYS["0"] = 11
for _row, _start in (("QWERTYUIOP", 16), ("ASDFGHJKL", 30), ("ZXCVBNM", 44)):
    _KEYS.update({ch: _start + i for i, ch in enumerate(_row)})
_KEYS.update({f"F{n}": 58 + n for n in range(1, 11)})
_KEYS.update({"F11": 87, "F12": 88})


def keycode(name: str) -> int:
    key = name.upper()
    if key.startswith("KEY_"):
        key = key[4:]
    if key not in _KEYS:
        raise ValueError(f"unknown key name: {name}")
    return _KEYS[key]


def parse_args(argv) -> list:
    if not argv:
        raise ValueError("no keys given")
    return [keycode(a) for a in argv]


def event_sequence(codes) -> list:
    """(type, code, value) triples: press in order, SYN, release in reverse, SYN."""
    down = [(EV_KEY, c, 1) for c in codes]
    up = [(EV_KEY, c, 0) for c in reversed(codes)]
    return down + [(EV_SYN, SYN_REPORT, 0)] + up + [(EV_SYN, SYN_REPORT, 0)]


def setup_struct(name: str) -> bytes:
    # struct uinput_setup { struct input_id {u16 bustype, vendor, product, version};
    #                       char name[80]; u32 ff_effects_max; }
    return struct.pack("HHHH80sI", BUS_VIRTUAL, 0x1234, 0x5678, 1, name.encode(), 0)


def _event(etype, code, value) -> bytes:
    now = time.time()
    return struct.pack("llHHi", int(now), int((now % 1) * 1_000_000), etype, code, value)


def press(*keys: str) -> None:
    codes = parse_args(list(keys))
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    try:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        for c in codes:
            fcntl.ioctl(fd, UI_SET_KEYBIT, c)
        fcntl.ioctl(fd, UI_DEV_SETUP, setup_struct(DEVICE_NAME))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        try:
            time.sleep(2)  # let udev/libinput add the device
            seq = event_sequence(codes)
            half = len(codes) + 1  # presses + SYN
            for ev in seq[:half]:
                os.write(fd, _event(*ev))
            time.sleep(0.05)  # hold the chord briefly before releasing
            for ev in seq[half:]:
                os.write(fd, _event(*ev))
            time.sleep(0.2)
        finally:
            fcntl.ioctl(fd, UI_DEV_DESTROY)
    finally:
        os.close(fd)


def main(argv) -> int:
    try:
        parse_args(argv)
    except ValueError as e:
        print(f"uinput_keys: {e}", file=sys.stderr)
        return 2
    press(*argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
