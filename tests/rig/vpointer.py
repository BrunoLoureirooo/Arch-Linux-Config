#!/usr/bin/env python3
"""Left-click at a layout position through zwlr_virtual_pointer_v1 (rig only).

    run.sh python3 -I tests/rig/vpointer.py <x> <y> [<layout-width> <layout-height>]

Speaks the Wayland wire protocol directly (no pywayland): binds wl_seat and
zwlr_virtual_pointer_manager_v1, moves the pointer to (x, y) with motion_absolute over a
layout box (default 3840x1080: the rig's DP-1 + eDP-1 side by side), then presses and
releases BTN_LEFT. Refuses to run unless WAYLAND_DISPLAY is the nested rig compositor
(checked like rig_env.sh), so it can never click in the live session.
"""
import os
import socket
import struct
import sys
import time

BTN_LEFT = 0x110


def die(msg):
    print("vpointer: " + msg, file=sys.stderr)
    sys.exit(1)


def wstr(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)


class Conn:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.next_id = 2
        self.buf = b""

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, op, payload=b""):
        self.s.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | op) + payload)

    def events(self):
        """Yield (obj, op, payload) until the socket has nothing more for 0.5 s."""
        self.s.settimeout(0.5)
        while True:
            while len(self.buf) >= 8:
                obj, so = struct.unpack_from("<II", self.buf)
                size = so >> 16
                if len(self.buf) < size:
                    break
                payload = self.buf[8:size]
                self.buf = self.buf[size:]
                yield obj, so & 0xFFFF, payload
            try:
                chunk = self.s.recv(65536)
            except socket.timeout:
                return
            if not chunk:
                return
            self.buf += chunk


def main():
    if len(sys.argv) not in (3, 5):
        die("usage: vpointer.py <x> <y> [<layout-width> <layout-height>]")
    x, y = int(sys.argv[1]), int(sys.argv[2])
    w, h = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) == 5 else (3840, 1080)
    # Same guard as rig_env.sh: the signature is not the live one and its lock file
    # names exactly this WAYLAND_DISPLAY.
    disp = os.environ.get("WAYLAND_DISPLAY", "")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    run = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    tb = os.environ.get("RICE_TESTBIN", os.path.expanduser("~/.cache/rice-testbin"))
    try:
        live = open(os.path.join(tb, "live.sig")).read().split()
        lock = open(os.path.join(run, "hypr", sig, "hyprland.lock")).read().splitlines()
    except OSError as e:
        die("not a rig environment (%s); run through tests/rig/run.sh" % e)
    if not sig or sig in live or not live or len(lock) < 2 or lock[1] != disp:
        die("WAYLAND_DISPLAY=%r is not the rig compositor; run through tests/rig/run.sh" % disp)
    path = disp if disp.startswith("/") else os.path.join(run, disp)
    c = Conn(path)

    registry = c.new_id()
    c.send(1, 1, struct.pack("<I", registry))  # wl_display.get_registry
    cb = c.new_id()
    c.send(1, 0, struct.pack("<I", cb))  # wl_display.sync
    globs = {}
    for obj, op, p in c.events():
        if obj == registry and op == 0:  # wl_registry.global
            name, n = struct.unpack_from("<II", p)
            iface = p[8:8 + n - 1].decode()
            (ver,) = struct.unpack_from("<I", p, 8 + n + (-n % 4))
            globs.setdefault(iface, (name, ver))
        if obj == cb:
            break
    for need in ("wl_seat", "zwlr_virtual_pointer_manager_v1"):
        if need not in globs:
            die("compositor lacks " + need)

    def bind(iface, ver):
        i = c.new_id()
        c.send(registry, 0, struct.pack("<I", globs[iface][0]) + wstr(iface) + struct.pack("<II", ver, i))
        return i

    seat = bind("wl_seat", 1)
    mgr = bind("zwlr_virtual_pointer_manager_v1", 1)
    ptr = c.new_id()
    c.send(mgr, 0, struct.pack("<II", seat, ptr))  # create_virtual_pointer(seat, id)

    def ms():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    # Two moves: the first one makes the surface under (x, y) receive enter (Hyprland
    # reports that enter at a stale position), the second one a real motion to (x, y).
    for dx in (1, 0):
        c.send(ptr, 1, struct.pack("<IIIII", ms(), max(0, x - dx), y, w, h))  # motion_absolute
        c.send(ptr, 4)  # frame
        time.sleep(0.1)
    c.send(ptr, 2, struct.pack("<III", ms(), BTN_LEFT, 1))  # button pressed
    c.send(ptr, 4)
    time.sleep(0.05)
    c.send(ptr, 2, struct.pack("<III", ms(), BTN_LEFT, 0))  # button released
    c.send(ptr, 4)
    c.send(ptr, 8)  # destroy
    cb2 = c.new_id()
    c.send(1, 0, struct.pack("<I", cb2))
    for obj, op, p in c.events():
        if obj == 1 and op == 0:  # wl_display.error
            die("protocol error: %r" % (p,))
        if obj == cb2:
            break
    print("clicked %d,%d" % (x, y))


if __name__ == "__main__":
    main()
