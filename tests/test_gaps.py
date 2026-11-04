"""The shell's outer gap (Theme.gapOut) must equal Hyprland's general.gaps_out, so the
bar and the rail float off the screen edges exactly like tiled windows."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT / "dot_config" / "hypr" / "hyprland.lua"
THEME = ROOT / "dot_config" / "quickshell" / "Theme.qml"


def one(pattern, text, what):
    found = re.findall(pattern, text, re.M)
    if len(found) != 1:
        raise AssertionError(f"expected exactly one {what}, found {found}")
    return int(found[0])


class GapsTest(unittest.TestCase):
    def test_theme_gap_equals_hyprland_gaps_out(self):
        gaps = one(r"^\s*gaps_out\s*=\s*(\d+)\s*,", HYPR.read_text(), "gaps_out in hyprland.lua")
        theme = one(r"^\s*readonly property int gapOut:\s*(\d+)\s*$", THEME.read_text(), "gapOut in Theme.qml")
        self.assertEqual(theme, gaps, "Theme.gapOut must equal hyprland.lua general.gaps_out")

    def test_bar_and_rail_use_the_theme_gap(self):
        q = ROOT / "dot_config" / "quickshell"
        bar = (q / "bar" / "Bar.qml").read_text()
        rail = (q / "rail" / "Rail.qml").read_text()
        self.assertIn("margins { top: Theme.gapOut; left: Theme.gapOut; right: Theme.gapOut }", bar)
        self.assertIn("right: Theme.gapOut; bottom: Theme.gapOut", rail)
        self.assertIn("exclusiveZone: rail.implicitWidth + Theme.gapOut", rail)


if __name__ == "__main__":
    unittest.main()
