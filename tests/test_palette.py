import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "dot_local" / "share" / "rice"))

from palette import NEON_RAIN, contrast, derive_palette, hex_to_oklch, oklch_to_hex  # noqa: E402

KEYS = {"bg", "panel", "line", "dim", "fg", "a1", "a2", "warn"}
HEX = re.compile(r"^#[0-9a-f]{6}$")


def hue_diff(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def check_floors(tc, p):
    tc.assertGreaterEqual(contrast(p["fg"], p["bg"]), 7)
    tc.assertGreaterEqual(contrast(p["a1"], p["bg"]), 7)
    tc.assertGreaterEqual(contrast(p["a2"], p["bg"]), 4.5)
    tc.assertGreaterEqual(contrast(p["dim"], p["bg"]), 4.5)


class PaletteTests(unittest.TestCase):
    def test_roundtrip(self):
        out = oklch_to_hex(*hex_to_oklch("#00f0ff"))
        for i, want in ((1, 0x00), (3, 0xF0), (5, 0xFF)):
            self.assertLessEqual(abs(int(out[i:i + 2], 16) - want), 1)

    def test_keys_and_format(self):
        p = derive_palette({"primary": "#7df9ff", "tertiary": "#ff2e88"})
        self.assertEqual(set(p), KEYS)
        for v in p.values():
            self.assertRegex(v, HEX)

    def test_contrast_floor(self):
        check_floors(self, derive_palette({"primary": "#7df9ff", "tertiary": "#ff2e88"}))

    def test_hue_follows_wallpaper(self):
        p = derive_palette({"primary": "#7df9ff", "tertiary": "#ff2e88"})
        self.assertLessEqual(hue_diff(hex_to_oklch(p["a1"])[2], hex_to_oklch("#7df9ff")[2]), 15)

    def test_close_hues_are_separated(self):
        p = derive_palette({"primary": oklch_to_hex(.7, .12, 100), "tertiary": oklch_to_hex(.7, .12, 110)})
        self.assertGreaterEqual(hue_diff(hex_to_oklch(p["a1"])[2], hex_to_oklch(p["a2"])[2]), 40)

    def test_grey_wallpaper_falls_back(self):
        p = derive_palette({"primary": "#808080", "tertiary": "#808080"})
        self.assertLessEqual(hue_diff(hex_to_oklch(p["a1"])[2], 195), 5)
        check_floors(self, p)

    def test_black_wallpaper(self):
        p = derive_palette({k: "#000000" for k in ("primary", "secondary", "tertiary")})
        self.assertEqual(set(p), KEYS)
        check_floors(self, p)

    def test_missing_roles_treated_as_grey(self):
        p = derive_palette({"secondary": "#123456", "surface": "#000000"})
        self.assertLessEqual(hue_diff(hex_to_oklch(p["a1"])[2], 195), 5)
        self.assertLessEqual(hue_diff(hex_to_oklch(p["a2"])[2], 345), 8)
        check_floors(self, p)
        check_floors(self, derive_palette({}))

    def test_invalid_hex_raises(self):
        with self.assertRaisesRegex(ValueError, "primary"):
            derive_palette({"primary": "red", "tertiary": "#ff2e88"})
        with self.assertRaises(ValueError):
            derive_palette({"primary": "#7df9ff", "tertiary": "#12345"})

    def test_hue_sweep(self):
        for h in range(0, 360, 10):
            p = derive_palette({"primary": oklch_to_hex(.7, .15, h), "tertiary": oklch_to_hex(.7, .15, h + 25)})
            self.assertEqual(set(p), KEYS)
            for v in p.values():
                self.assertRegex(v, HEX)
            check_floors(self, p)

    def test_neon_rain_seed(self):
        self.assertEqual(set(NEON_RAIN), KEYS)
        for v in NEON_RAIN.values():
            self.assertRegex(v, HEX)


if __name__ == "__main__":
    unittest.main()
