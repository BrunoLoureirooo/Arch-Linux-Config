"""cursor-shake: the shake detector and the pointer-device picker (pure functions only)."""
import importlib.machinery
import importlib.util
import pathlib
import unittest

SRC = pathlib.Path(__file__).resolve().parents[1] / "dot_local/bin/executable_cursor-shake"
loader = importlib.machinery.SourceFileLoader("cursor_shake", str(SRC))
spec = importlib.util.spec_from_loader("cursor_shake", loader)
cs = importlib.util.module_from_spec(spec)
loader.exec_module(cs)


def path(points, dt=0.05):
    return [(i * dt, x, y) for i, (x, y) in enumerate(points)]


class IsShake(unittest.TestCase):
    def test_zigzag_is_a_shake(self):
        pts = [(500 + (90 if i % 2 else -90), 400) for i in range(12)]
        self.assertTrue(cs.is_shake(path(pts)))

    def test_vertical_zigzag_is_a_shake(self):
        pts = [(500, 400 + (90 if i % 2 else -90)) for i in range(12)]
        self.assertTrue(cs.is_shake(path(pts)))

    def test_straight_sweep_is_not(self):
        self.assertFalse(cs.is_shake(path([(i * 60, 300) for i in range(12)])))

    def test_one_flick_and_back_is_not(self):
        pts = [(i * 60, 300) for i in range(6)] + [(300 - i * 60, 300) for i in range(6)]
        self.assertFalse(cs.is_shake(path(pts)))

    def test_jitter_is_not(self):
        pts = [(500 + (3 if i % 2 else -3), 400) for i in range(40)]
        self.assertFalse(cs.is_shake(path(pts)))

    def test_short_wiggle_is_not(self):
        pts = [(500 + (20 if i % 2 else -20), 400) for i in range(12)]
        self.assertFalse(cs.is_shake(path(pts)))

    def test_empty_and_single(self):
        self.assertFalse(cs.is_shake([]))
        self.assertFalse(cs.is_shake([(0, 1, 1)]))


DEVICES = """I: Bus=0003
N: Name="Logitech G502 HERO Gaming Mouse"
H: Handlers=event6 mouse0

I: Bus=0003
N: Name="Logitech G502 HERO Gaming Mouse Keyboard"
H: Handlers=sysrq kbd event7

I: Bus=0003
N: Name="xremap"
H: Handlers=sysrq kbd event27 rfkill mouse3

I: Bus=0018
N: Name="SYNA32B9:00 06CB:CE7D Touchpad"
H: Handlers=event17 mouse2

I: Bus=0000
N: Name="HDA NVidia HDMI/DP,pcm=3"
H: Handlers=event21
"""


class PointerNodes(unittest.TestCase):
    def test_mice_and_touchpads_only(self):
        self.assertEqual(cs.pointer_nodes(DEVICES), ["/dev/input/event17", "/dev/input/event6"])

    def test_empty(self):
        self.assertEqual(cs.pointer_nodes(""), [])


if __name__ == "__main__":
    unittest.main()
