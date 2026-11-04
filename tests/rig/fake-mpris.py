#!/usr/bin/env python3
"""A fake MPRIS player for the qs selftest, for a PRIVATE session bus only.

    DBUS_SESSION_BUS_ADDRESS=<private bus> fake-mpris.py [title] [artist] [length-s]

Owns org.mpris.MediaPlayer2.rigfake, reports PlaybackStatus Playing with the given
metadata, and a Position that advances with wall time. Every control method is a
no-op. Refuses to run on the user's real session bus (the live desktop's players and
notification daemon live there).
"""
import os
import sys
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"

addr = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
live = f"unix:path={os.environ.get('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid())}/bus"
if not addr or addr == live or addr.startswith(live + ","):
    sys.exit("fake-mpris: refusing to run without a private DBUS_SESSION_BUS_ADDRESS")

title = sys.argv[1] if len(sys.argv) > 1 else "Rig Song"
artist = sys.argv[2] if len(sys.argv) > 2 else "Rig Artist"
length_us = int(float(sys.argv[3] if len(sys.argv) > 3 else 252) * 1_000_000)
start = time.monotonic()


class Player(dbus.service.Object):
    def props(self, iface):
        if iface == ROOT:
            return {"Identity": "rigfake", "CanQuit": False, "CanRaise": False,
                    "HasTrackList": False, "DesktopEntry": "rigfake",
                    "SupportedUriSchemes": dbus.Array([], "s"),
                    "SupportedMimeTypes": dbus.Array([], "s")}
        if iface == PLAYER:
            pos = int((time.monotonic() - start) * 1_000_000) % length_us
            return {
                "PlaybackStatus": "Playing", "LoopStatus": "None", "Rate": 1.0,
                "Shuffle": False, "Volume": 1.0, "Position": dbus.Int64(pos),
                "MinimumRate": 1.0, "MaximumRate": 1.0,
                "CanGoNext": False, "CanGoPrevious": False, "CanPlay": True,
                "CanPause": True, "CanSeek": False, "CanControl": True,
                "Metadata": dbus.Dictionary({
                    "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/rigfake/1"),
                    "mpris:length": dbus.Int64(length_us),
                    "xesam:title": title,
                    "xesam:artist": dbus.Array([artist], "s"),
                }, "sv"),
            }
        return {}

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, name):
        return self.props(iface)[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props(iface)

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, name, value):
        pass

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    @dbus.service.method(ROOT)
    def Raise(self):
        pass

    @dbus.service.method(ROOT)
    def Quit(self):
        pass

    @dbus.service.method(PLAYER)
    def Play(self):
        pass

    @dbus.service.method(PLAYER)
    def Pause(self):
        pass

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        pass

    @dbus.service.method(PLAYER)
    def Stop(self):
        pass

    @dbus.service.method(PLAYER)
    def Next(self):
        pass

    @dbus.service.method(PLAYER)
    def Previous(self):
        pass

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        pass

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track, pos):
        pass

    @dbus.service.method(PLAYER, in_signature="s")
    def OpenUri(self, uri):
        pass


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
Player(bus, "/org/mpris/MediaPlayer2")
name = dbus.service.BusName("org.mpris.MediaPlayer2.rigfake", bus)
print("fake-mpris: on", addr, flush=True)
GLib.MainLoop().run()
