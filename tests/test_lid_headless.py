"""lid and headless scripts (dot_local/bin) against fake hyprctl/sudo.

The scripts run with PATH set to a temp dir that holds ONLY the fakes and links to
the few real tools they need, so the real sudo, headless-peripherals and hyprctl are
unreachable from these tests. The fake hyprctl answers like Hyprland 0.56 under the
Lua config ("lua") or the legacy hyprlang config ("legacy"): a refused request prints
an error (with exit status 0 for `keyword`, as the real one does) instead of "ok".
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LID = REPO / "dot_local/bin/executable_lid"
HEADLESS = REPO / "dot_local/bin/executable_headless"
PERIPH = "/usr/local/bin/headless-peripherals"

FAKE_HYPRCTL = r"""#!/bin/bash
echo "hyprctl $*" >> "$FAKE_LOG"
mode=$(cat "$FAKE_DIR/mode")
case "$1" in
  monitors)
    n=$(cat "$FAKE_DIR/enabled"); lit=$(cat "$FAKE_DIR/dpms")
    echo "["
    for ((i = 0; i < n; i++)); do
      echo "  { \"name\": \"M$i\", \"dpmsStatus\": $lit, \"disabled\": false },"
    done
    echo "]" ;;
  eval)
    if [ "$mode" = lua ]; then echo ok; else echo "unknown request"; fi ;;
  keyword)
    if [ "$mode" = legacy ]; then echo ok; else echo "keyword can't work with non-legacy parsers. Use eval."; fi ;;
  dispatch)
    [ -e "$FAKE_DIR/dpms-broken" ] && { echo "error: dpms broken"; exit 7; }
    case "$2" in
      hl.dsp.*) [ "$mode" = lua ] && echo ok || echo "Invalid dispatcher" ;;
      *) [ "$mode" = legacy ] && echo ok || { echo "error: ')' expected"; exit 7; } ;;
    esac ;;
  reload) echo ok ;;
  *) echo "fake hyprctl: unexpected $*" >&2; exit 9 ;;
esac
"""

FAKE_SUDO = r"""#!/bin/bash
echo "sudo $*" >> "$FAKE_LOG"
[ -e "$FAKE_DIR/sudo-fails" ] && exit 1
exit 0
"""


class Rig:
    def __init__(self, mode="lua", enabled=2, dpms="true"):
        self.tmp = Path(tempfile.mkdtemp(prefix="lidtest-"))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.run_dir = self.tmp / "run"
        self.run_dir.mkdir()
        for name, body in (("hyprctl", FAKE_HYPRCTL), ("sudo", FAKE_SUDO)):
            p = self.bin / name
            p.write_text(body)
            p.chmod(0o755)
        for tool in ("bash", "grep", "date", "stat", "touch", "cat"):
            real = shutil.which(tool, path="/usr/bin:/bin")
            assert real, tool
            (self.bin / tool).symlink_to(real)
        self.log = self.tmp / "log"
        self.log.write_text("")
        self.set(mode=mode, enabled=enabled, dpms=dpms)

    def set(self, **kw):
        for k, v in kw.items():
            (self.tmp / k).write_text(str(v))

    def flag(self, name):
        (self.tmp / name).write_text("")

    def run(self, script, *args):
        env = {"PATH": str(self.bin), "FAKE_LOG": str(self.log), "FAKE_DIR": str(self.tmp),
               "XDG_RUNTIME_DIR": str(self.run_dir)}
        return subprocess.run(["/usr/bin/env", "bash", str(script), *args], env=env,
                              capture_output=True, text=True, timeout=20)

    def calls(self):
        return [l for l in self.log.read_text().splitlines() if not l.startswith("hyprctl monitors")]

    def close(self):
        shutil.rmtree(self.tmp)


class RigTest(unittest.TestCase):
    def rig(self, **kw):
        r = Rig(**kw)
        self.addCleanup(r.close)
        # Guard: the real sudo must never be reachable from the test PATH.
        self.assertEqual(shutil.which("sudo", path=str(r.bin)), str(r.bin / "sudo"))
        return r


class LidTest(RigTest):
    def test_close_lua_disables_panel_with_eval(self):
        r = self.rig(mode="lua", enabled=2)
        res = r.run(LID, "close")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), ['hyprctl eval hl.monitor({ output = "eDP-1", disabled = true })'])

    def test_close_legacy_falls_back_to_keyword(self):
        r = self.rig(mode="legacy", enabled=2)
        res = r.run(LID, "close")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), ['hyprctl eval hl.monitor({ output = "eDP-1", disabled = true })',
                                     "hyprctl keyword monitor eDP-1, disable"])

    def test_close_with_only_the_panel_does_nothing(self):
        r = self.rig(enabled=1)
        res = r.run(LID, "close")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [])

    def test_close_warns_when_both_forms_fail(self):
        r = self.rig(mode="neither", enabled=2)
        res = r.run(LID, "close")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("could not disable eDP-1", res.stderr)

    def test_open_reloads(self):
        r = self.rig()
        res = r.run(LID, "open")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), ["hyprctl reload"])

    def test_usage(self):
        r = self.rig()
        res = r.run(LID)
        self.assertEqual(res.returncode, 1)
        self.assertIn("usage", res.stderr)


class HeadlessTest(RigTest):
    OFF_LUA = 'hyprctl dispatch hl.dsp.dpms({ action = "off" })'
    ON_LUA = 'hyprctl dispatch hl.dsp.dpms({ action = "on" })'

    def test_off_lua_dpms_before_cutting_peripherals(self):
        r = self.rig(mode="lua", dpms="true")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [self.OFF_LUA, f"sudo -n {PERIPH} off"])

    def test_off_legacy_fallback(self):
        r = self.rig(mode="legacy", dpms="true")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [self.OFF_LUA, "hyprctl dispatch dpms off", f"sudo -n {PERIPH} off"])

    def test_off_dpms_failure_never_cuts_peripherals(self):
        r = self.rig(mode="lua", dpms="true")
        r.flag("dpms-broken")
        res = r.run(HEADLESS)
        self.assertNotEqual(res.returncode, 0)
        self.assertFalse([c for c in r.calls() if c.startswith("sudo")], r.calls())
        self.assertIn("peripherals left powered", res.stderr)

    def test_on_restores_peripherals_before_dpms(self):
        r = self.rig(mode="lua", dpms="false")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [f"sudo -n {PERIPH} on", self.ON_LUA])

    def test_on_legacy_fallback(self):
        r = self.rig(mode="legacy", dpms="false")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [f"sudo -n {PERIPH} on", self.ON_LUA, "hyprctl dispatch dpms on"])

    def test_on_sudo_failure_still_lights_displays(self):
        r = self.rig(mode="lua", dpms="false")
        r.flag("sudo-fails")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(r.calls(), [f"sudo -n {PERIPH} on", self.ON_LUA])

    def test_off_sudo_failure_is_ignored(self):
        r = self.rig(mode="lua", dpms="true")
        r.flag("sudo-fails")
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0, res.stderr)
        # The displays still went dark first and the peripheral cut was attempted once.
        self.assertEqual(r.calls(), [self.OFF_LUA, f"sudo -n {PERIPH} off"])

    def test_second_press_within_two_seconds_is_ignored(self):
        r = self.rig(mode="lua", dpms="true")
        r.run(HEADLESS)
        before = r.log.read_text()
        res = r.run(HEADLESS)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(r.log.read_text(), before)


if __name__ == "__main__":
    unittest.main()
