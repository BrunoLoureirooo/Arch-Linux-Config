"""qs-supervise loop logic against a FAKE qs.

PATH holds only a temp dir with the fake `qs` and links to bash and sleep, so the real
Quickshell can never start. The fake records a start time per run and behaves per run
number from a plan file ("fail" = exit 1 at once, "<n>" = run n seconds, then exit 1).
"""

import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SUP = REPO / "dot_local/bin/executable_qs-supervise"

FAKE_QS = r"""#!/bin/bash
n=$(( $(cat "$FAKE_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_DIR/count"
echo "$n $EPOCHREALTIME" >> "$FAKE_DIR/starts"
what=$(sed -n "${n}p" "$FAKE_DIR/plan" 2>/dev/null)
[ -z "$what" ] && what=fail
[ "$what" = fail ] && exit 1
sleep "$what"
exit 1
"""


class Supervisor:
    def __init__(self, plan, sig=None):
        self.tmp = Path(tempfile.mkdtemp(prefix="qssup-"))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        qs = self.bin / "qs"
        qs.write_text(FAKE_QS)
        qs.chmod(0o755)
        for tool in ("bash", "sleep", "sed", "cat"):
            (self.bin / tool).symlink_to(shutil.which(tool, path="/usr/bin:/bin"))
        (self.tmp / "plan").write_text("\n".join(plan) + "\n")
        self.run_dir = self.tmp / "run"
        env = {"PATH": str(self.bin), "FAKE_DIR": str(self.tmp), "XDG_RUNTIME_DIR": str(self.run_dir)}
        if sig:
            (self.run_dir / "hypr" / sig).mkdir(parents=True)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        self.proc = subprocess.Popen(["/usr/bin/env", "bash", str(SUP)], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

    def starts(self):
        try:
            lines = (self.tmp / "starts").read_text().splitlines()
        except FileNotFoundError:
            return []
        return [float(l.split()[1]) for l in lines]

    def wait_starts(self, n, timeout):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if len(self.starts()) >= n:
                return self.starts()
            time.sleep(0.05)
        return self.starts()

    def stop(self):
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        shutil.rmtree(self.tmp, ignore_errors=True)


class QsSuperviseTest(unittest.TestCase):
    def sup(self, plan, sig=None):
        s = Supervisor(plan, sig)
        self.addCleanup(s.stop)
        return s

    def test_instant_failures_back_off_by_doubling(self):
        s = self.sup(["fail"] * 5)
        t = s.wait_starts(4, timeout=12)
        self.assertEqual(len(t), 4, t)
        gaps = [b - a for a, b in zip(t, t[1:])]
        for gap, want in zip(gaps, (1, 2, 4)):
            self.assertGreaterEqual(gap, want - 0.1, gaps)
            self.assertLess(gap, want + 0.9, gaps)

    def test_long_run_resets_the_back_off(self):
        # fail, fail (delay now 4), a 5.5 s run (long), fail: the gap after the long run is 1 s again
        s = self.sup(["fail", "fail", "5.5", "fail", "fail"])
        t = s.wait_starts(5, timeout=20)
        self.assertEqual(len(t), 5, t)
        gaps = [b - a for a, b in zip(t, t[1:])]
        self.assertGreaterEqual(gaps[1], 1.9, gaps)  # backed off to 2 s first
        self.assertLess(gaps[3], 1.9, gaps)          # after the long run: back to 1 s
        self.assertGreaterEqual(gaps[3], 0.9, gaps)
        self.assertGreaterEqual(gaps[2], 5.5 + 0.9, gaps)  # long run itself plus 1 s

    def test_exits_when_the_compositor_is_gone(self):
        sig = "fake-sig"
        s = self.sup(["2", "fail"], sig=sig)
        self.assertEqual(len(s.wait_starts(1, timeout=3)), 1)
        shutil.rmtree(s.run_dir / "hypr" / sig)
        s.proc.wait(timeout=6)
        self.assertEqual(s.proc.returncode, 0)
        self.assertEqual(len(s.starts()), 1, "no restart after the compositor went away")
        self.assertIn("compositor", s.proc.stderr.read())

    def test_sigterm_stops_loop_and_child(self):
        s = self.sup(["30"])
        self.assertEqual(len(s.wait_starts(1, timeout=3)), 1)
        time.sleep(0.3)
        s.proc.send_signal(signal.SIGTERM)
        s.proc.wait(timeout=5)
        self.assertEqual(s.proc.returncode, 0)
        time.sleep(1.5)
        self.assertEqual(len(s.starts()), 1, "nothing restarted after SIGTERM")


if __name__ == "__main__":
    unittest.main()
