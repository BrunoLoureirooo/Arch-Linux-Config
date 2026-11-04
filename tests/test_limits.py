import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "dot_local" / "share" / "rice"))

import limits  # noqa: E402

CLI = ROOT / "dot_local" / "bin" / "executable_claude-limits-statusline"
NOW = 1999990000
BOTH = {"rate_limits": {"five_hour": {"used_percentage": 38.4, "resets_at": 2000000000},
                        "seven_day": {"used_percentage": 19, "resets_at": 2000100000}}}
FIVE = {"rate_limits": {"five_hour": {"used_percentage": 38.4, "resets_at": 2000000000}}}


def win(pct, resets=2000000000):
    return {"rate_limits": {"five_hour": {"used_percentage": pct, "resets_at": resets}}}


class ParseTests(unittest.TestCase):
    def test_both_windows(self):
        d = limits.parse_rate_limits(BOTH, NOW)
        self.assertEqual(d["five_hour"], {"pct": 38.4, "resets_at": 2000000000})
        self.assertEqual(d["seven_day"]["pct"], 19)
        self.assertEqual(d["updated_at"], NOW)
        self.assertEqual(limits.render_line(d), "5h 38% · 7d 19%")

    def test_missing_rate_limits(self):
        d = limits.parse_rate_limits({}, NOW)
        self.assertIsNone(d["five_hour"])
        self.assertIsNone(d["seven_day"])
        self.assertEqual(limits.render_line(d), "")

    def test_one_window_absent(self):
        d = limits.parse_rate_limits(FIVE, NOW)
        self.assertIsNone(d["seven_day"])
        self.assertEqual(limits.render_line(d), "5h 38%")

    def test_expired_window_dropped(self):
        d = limits.parse_rate_limits(win(10, NOW - 1), NOW)
        self.assertIsNone(d["five_hour"])
        d = limits.parse_rate_limits(win(10, NOW), NOW)
        self.assertIsNone(d["five_hour"])

    def test_rate_limits_not_a_dict(self):
        for bad in ("x", 5, [1], None):
            d = limits.parse_rate_limits({"rate_limits": bad}, NOW)
            self.assertIsNone(d["five_hour"])
            self.assertIsNone(d["seven_day"])

    def test_window_not_a_dict(self):
        d = limits.parse_rate_limits({"rate_limits": {"five_hour": 3}}, NOW)
        self.assertIsNone(d["five_hour"])

    def test_string_percentage_is_invalid(self):
        self.assertIsNone(limits.parse_rate_limits(win("38"), NOW)["five_hour"])
        self.assertIsNone(limits.parse_rate_limits(win(True), NOW)["five_hour"])

    def test_string_resets_at_is_invalid(self):
        self.assertIsNone(limits.parse_rate_limits(win(10, "2000000000"), NOW)["five_hour"])

    def test_percentage_clamped(self):
        self.assertEqual(limits.parse_rate_limits(win(-5), NOW)["five_hour"]["pct"], 0)
        self.assertEqual(limits.parse_rate_limits(win(150), NOW)["five_hour"]["pct"], 100)

    def test_nan_and_inf(self):
        payload = json.loads('{"rate_limits": {"five_hour": {"used_percentage": NaN, '
                             '"resets_at": 2000000000}}}')
        self.assertIsNone(limits.parse_rate_limits(payload, NOW)["five_hour"])
        self.assertIsNone(limits.parse_rate_limits(win(float("inf")), NOW)["five_hour"])
        self.assertIsNone(limits.parse_rate_limits(win(10, float("nan")), NOW)["five_hour"])
        self.assertIsNone(limits.parse_rate_limits(win(10, float("inf")), NOW)["five_hour"])

    def test_resets_at_is_int(self):
        d = limits.parse_rate_limits(win(10, 2000000000.7), NOW)
        self.assertEqual(d["five_hour"]["resets_at"], 2000000000)
        self.assertIsInstance(d["five_hour"]["resets_at"], int)

    def test_huge_int_drops_only_that_window(self):
        payload = json.loads('{"rate_limits": {"five_hour": {"used_percentage": 1%s, '
                             '"resets_at": 2000000000}, "seven_day": {"used_percentage": 19, '
                             '"resets_at": 2000100000}}}' % ("0" * 400))
        d = limits.parse_rate_limits(payload, NOW)
        self.assertIsNone(d["five_hour"])
        self.assertEqual(d["seven_day"]["pct"], 19)

    def test_render_rounds(self):
        d = limits.parse_rate_limits(win(38.6), NOW)
        self.assertEqual(limits.render_line(d), "5h 39%")


class CacheTests(unittest.TestCase):
    def test_write_is_atomic(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "sub" / "c.json"
            limits.write_cache(str(p), limits.parse_rate_limits(BOTH, NOW))
            self.assertEqual(os.listdir(p.parent), ["c.json"])
            self.assertEqual(json.loads(p.read_text())["five_hour"]["pct"], 38.4)

    def test_failed_write_leaves_no_temp(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "c.json"
            with self.assertRaises(TypeError):
                limits.write_cache(str(p), {"x": object()})
            self.assertEqual(os.listdir(t), [])


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cache = Path(self.tmp.name) / "cache" / "claude-limits.json"

    def run_cli(self, stdin, explicit=True):
        env = {**os.environ, "HOME": str(self.home)}
        env.pop("CLAUDE_LIMITS_CACHE", None)
        if explicit:
            env["CLAUDE_LIMITS_CACHE"] = str(self.cache)
        data = stdin if isinstance(stdin, bytes) else json.dumps(stdin).encode()
        return subprocess.run([sys.executable, str(CLI)], input=data, capture_output=True,
                              env=env, timeout=30)

    def seed(self):
        self.cache.parent.mkdir(parents=True, exist_ok=True)
        self.cache.write_text('{"five_hour": null, "seven_day": null, "updated_at": 1}')
        return self.cache.read_bytes()

    def test_cli_happy_path(self):
        far = win(38.4, 4000000000)
        r = self.run_cli(far)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"5h 38%\n", b""))
        d = json.loads(self.cache.read_text())
        self.assertEqual(d["five_hour"], {"pct": 38.4, "resets_at": 4000000000})
        self.assertIsNone(d["seven_day"])
        self.assertIsInstance(d["updated_at"], int)

    def test_cli_default_cache_path_uses_home(self):
        r = self.run_cli(win(5, 4000000000), explicit=False)
        self.assertEqual(r.returncode, 0)
        self.assertTrue((self.home / ".cache" / "claude-limits.json").is_file())

    def test_cli_bad_input(self):
        before = self.seed()
        r = self.run_cli(b"not json")
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_cli_empty_stdin(self):
        before = self.seed()
        r = self.run_cli(b"")
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_cli_bad_input_creates_nothing(self):
        r = self.run_cli(b"not json")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self.cache.exists())

    def test_cli_non_object_json(self):
        before = self.seed()
        for body in (b"[1]", b"3", b"null", b'"x"'):
            r = self.run_cli(body)
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_cli_closed_stdin(self):
        env = {**os.environ, "HOME": str(self.home), "CLAUDE_LIMITS_CACHE": str(self.cache)}
        r = subprocess.run([sys.executable, str(CLI)], stdin=subprocess.DEVNULL,
                           capture_output=True, env=env, timeout=20)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))

    def test_no_rate_limits_keeps_good_cache(self):
        self.run_cli(win(38.4, 4000000000))
        before = self.cache.read_bytes()
        r = self.run_cli({"model": "x"})
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_no_rate_limits_creates_cache_when_none_exists(self):
        r = self.run_cli({"model": "x"})
        self.assertEqual(r.returncode, 0)
        d = json.loads(self.cache.read_text())
        self.assertIsNone(d["five_hour"])
        self.assertIsNone(d["seven_day"])

    def test_oversized_stdin_ignored(self):
        before = self.seed()
        body = json.dumps(win(50, 4000000000)).encode() + b" " * (1 << 20)
        r = self.run_cli(body)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_missing_cache_dir_created(self):
        self.assertFalse(self.cache.parent.exists())
        r = self.run_cli(win(50, 4000000000))
        self.assertEqual((r.returncode, r.stdout), (0, b"5h 50%\n"))
        self.assertTrue(self.cache.is_file())

    @unittest.skipIf(os.geteuid() == 0, "root ignores directory permissions")
    def test_unwritable_cache_dir(self):
        locked = Path(self.tmp.name) / "locked"
        locked.mkdir()
        self.cache = locked / "sub" / "c.json"
        locked.chmod(0)
        try:
            r = self.run_cli(win(50, 4000000000))
        finally:
            locked.chmod(0o700)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"5h 50%\n", b""))

    def test_library_missing_exits_quietly(self):
        before = self.seed()
        alone = Path(self.tmp.name) / "alone"
        alone.mkdir()
        cli = alone / "claude-limits-statusline"
        cli.write_bytes(CLI.read_bytes())
        env = {**os.environ, "HOME": str(self.home), "CLAUDE_LIMITS_CACHE": str(self.cache)}
        r = subprocess.run([sys.executable, str(cli)],
                           input=json.dumps(win(5, 4000000000)).encode(),
                           capture_output=True, env=env, timeout=30)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, b"", b""))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_closed_stdout_pipe(self):
        env = {**os.environ, "HOME": str(self.home), "CLAUDE_LIMITS_CACHE": str(self.cache)}
        p = subprocess.Popen([sys.executable, str(CLI)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        p.stdout.close()
        _, err = p.communicate(json.dumps(win(50, 4000000000)).encode(), timeout=30)
        self.assertEqual((p.returncode, err), (0, b""))

    def test_executable_bit(self):
        self.assertTrue(os.access(CLI, os.X_OK))


if __name__ == "__main__":
    unittest.main()
