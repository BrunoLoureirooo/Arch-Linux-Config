import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "dot_local" / "share" / "rice"))

import outputs  # noqa: E402
from palette import NEON_RAIN, contrast  # noqa: E402

CLI = ROOT / "dot_local" / "bin" / "executable_rice-palette"
FIXTURE = ROOT / "tests" / "fixtures" / "matugen-berserk.json"
TESTBIN = Path.home() / ".cache" / "rice-testbin"
REAL_MATUGEN = TESTBIN / "root" / "usr" / "bin" / "matugen"
KEYS = {"bg", "panel", "line", "dim", "fg", "a1", "a2", "warn"}
HEX = re.compile(r"^#[0-9a-f]{6}$")
LUA = shutil.which("lua") or shutil.which("luajit")


def png(w, h, rgb=(128, 128, 128), rows=None):
    """Tiny valid truecolour PNG, built by hand. rows limits the data written."""
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    row = b"\x00" + bytes(rgb) * w
    n = h if rows is None else rows
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * n)) + chunk(b"IEND", b""))


def real_env():
    out = subprocess.run(["bash", "-c", f"source {TESTBIN}/env.sh && env -0"],
                         capture_output=True, check=True).stdout
    return dict(kv.split("=", 1) for kv in out.decode().split("\0") if "=" in kv)


class Sandbox(unittest.TestCase):
    """Every run uses a temp HOME and RICE_NO_RELOAD=1."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = Path(self._tmp.name) / "home"
        self.home.mkdir()
        self.work = Path(self._tmp.name) / "work"
        self.work.mkdir()

    def fake_matugen(self, body=None, fixture=True):
        self._n = getattr(self, "_n", 0) + 1
        p = self.work / f"fake-matugen-{self._n}"
        if body is None:
            body = f"cat {FIXTURE}" if fixture else "exit 3"
        p.write_text("#!/bin/sh\n" + body + "\n")
        p.chmod(0o755)
        return p

    def run_cli(self, *args, matugen=None, real=False):
        env = real_env() if real else dict(os.environ)
        env["HOME"] = str(self.home)
        env["RICE_NO_RELOAD"] = "1"
        for k in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
            env.pop(k, None)
        env["RICE_MATUGEN"] = str(matugen or (REAL_MATUGEN if real else self.fake_matugen()))
        return subprocess.run([sys.executable, str(CLI), *map(str, args)],
                              capture_output=True, text=True, env=env, timeout=120)

    def snapshot(self):
        return {str(p.relative_to(self.home)): p.read_bytes()
                for p in sorted(self.home.rglob("*")) if p.is_file()}

    def outputs_paths(self):
        h = self.home
        return [h / ".config/quickshell/colors.json", h / ".config/kitty/colors.conf",
                h / ".config/hypr/colors.lua", h / ".config/btop/themes/rice.theme",
                h / ".local/state/quickshell/wallpaper.json"]


class TestRoles(unittest.TestCase):
    def test_fixture_roles(self):
        roles = outputs.roles_from_matugen(json.loads(FIXTURE.read_text()))
        self.assertEqual(roles, {"primary": "#ffb3af", "tertiary": "#fcb885"})

    def test_bad_structure(self):
        for doc in ({}, {"colors": {}}, {"colors": {"primary": {"dark": {}}, "tertiary": {}}},
                    {"colors": {"primary": {"dark": {"color": "red"}},
                                "tertiary": {"dark": {"color": "#fcb885"}}}},
                    [], None):
            with self.subTest(doc=doc), self.assertRaises(ValueError):
                outputs.roles_from_matugen(doc)


class TestRenderers(unittest.TestCase):
    def test_each_contains_every_token(self):
        for fn in (outputs.render_quickshell, outputs.render_kitty):
            text = fn(NEON_RAIN).lower()
            for k, v in NEON_RAIN.items():
                if fn is outputs.render_kitty and k == "dim":
                    continue  # kitty uses dim lifted for contrast (color8)
                self.assertIn(v, text, (fn.__name__, k))
        btop = outputs.render_btop(NEON_RAIN).lower()
        for k, v in NEON_RAIN.items():
            if k != "panel":  # btop has no panel slot
                self.assertIn(v, btop, k)
        hypr = outputs.render_hypr(NEON_RAIN)
        for k in ("a1", "a2", "line"):
            self.assertIn(NEON_RAIN[k][1:], hypr)

    def test_quickshell_keys(self):
        text = outputs.render_quickshell(NEON_RAIN)
        self.assertTrue(text.endswith("\n"))
        self.assertEqual(list(json.loads(text)), list(NEON_RAIN))
        self.assertIn('\n  "bg"', text)

    @unittest.skipUnless(LUA, "no lua")
    def test_hypr_loads_under_lua(self):
        out = subprocess.run([LUA, "-e", "local t = load(io.read('a'))(); "
                              "print(#t.active, t.active[1], t.active[2], t.inactive)"],
                             input=outputs.render_hypr(NEON_RAIN), capture_output=True,
                             text=True, check=True).stdout.split()
        self.assertEqual(out, ["2", "rgba(00f0ffff)", "rgba(ff2e88ff)", "rgba(1b1d30ff)"])

    def test_btop(self):
        names = ["main_bg", "main_fg", "title", "hi_fg", "selected_bg", "selected_fg",
                 "inactive_fg", "graph_text", "meter_bg", "proc_misc", "cpu_box", "mem_box",
                 "net_box", "proc_box", "div_line"]
        for g in ("temp", "cpu", "free", "cached", "available", "used", "download", "upload",
                  "process"):
            names += [f"{g}_{s}" for s in ("start", "mid", "end")]
        theme = dict(re.findall(r'^theme\[(\w+)\]="([^"]*)"$', outputs.render_btop(NEON_RAIN), re.M))
        for n in names:
            self.assertIn(n, theme)
            self.assertRegex(theme[n], HEX, n)
        self.assertEqual(theme["main_bg"], NEON_RAIN["bg"])

    def test_color8_keeps_contrast(self):
        c8 = outputs._kitty_pairs(outputs.render_kitty(NEON_RAIN))["color8"]
        self.assertGreaterEqual(contrast(c8, NEON_RAIN["bg"]), 4.5)


class TestSeedsInSync(unittest.TestCase):
    def test_quickshell_seed(self):
        seed = json.loads((ROOT / "dot_config/quickshell/create_colors.json").read_text())
        self.assertEqual(json.loads(outputs.render_quickshell(NEON_RAIN)), seed)

    def test_kitty_seed(self):
        seed = outputs._kitty_pairs((ROOT / "dot_config/kitty/create_colors.conf").read_text())
        self.assertEqual(outputs._kitty_pairs(outputs.render_kitty(NEON_RAIN)), seed)

    @unittest.skipUnless(LUA, "no lua")
    def test_hypr_seed(self):
        def ev(src):
            return subprocess.run([LUA, "-e", "local t = load(io.read('a'))(); "
                                   "print(t.active[1], t.active[2], t.inactive)"],
                                  input=src, capture_output=True, text=True, check=True).stdout
        seed = (ROOT / "dot_config/hypr/create_colors.lua").read_text()
        self.assertEqual(ev(outputs.render_hypr(NEON_RAIN)), ev(seed))


class TestCli(Sandbox):
    def test_executable_bit(self):
        self.assertTrue(CLI.stat().st_mode & stat.S_IXUSR)

    def test_derive_prints_tokens_and_caches(self):
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        r = self.run_cli("derive", img)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(set(json.loads(r.stdout)), KEYS)
        cached = list((self.home / ".cache" / "rice").glob("*.json"))
        self.assertEqual(len(cached), 1)
        self.assertEqual(cached[0].stem, hashlib.sha1(img.read_bytes()).hexdigest())
        # second call must not need matugen
        r2 = self.run_cli("derive", img, matugen=self.fake_matugen(fixture=False))
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertEqual(json.loads(r2.stdout), json.loads(r.stdout))

    def test_apply_writes_everything(self):
        img = self.work / "wall paper.png"
        img.write_bytes(png(8, 8))
        r = self.run_cli("apply", img)
        self.assertEqual(r.returncode, 0, r.stderr)
        for p in self.outputs_paths():
            self.assertTrue(p.is_file(), p)
        tokens = json.loads((self.home / ".config/quickshell/colors.json").read_text())
        self.assertEqual(set(tokens), KEYS)
        self.assertIn(tokens["a1"], (self.home / ".config/kitty/colors.conf").read_text())
        self.assertEqual(json.loads(self.outputs_paths()[4].read_text()),
                         {"path": str(img.resolve()), "palette": "wall paper"})
        self.assertEqual([p.name for p in self.home.rglob("*.tmp*")], [])

    def test_apply_leaves_files_on_failure(self):
        good = self.work / "good.png"
        good.write_bytes(png(8, 8))
        self.assertEqual(self.run_cli("apply", good).returncode, 0)
        before = self.snapshot()
        zero = self.work / "zero.png"
        zero.write_bytes(b"")
        text = self.work / "text.png"
        text.write_text("not an image at all\n")
        adir = self.work / "dir.png"
        adir.mkdir()
        other = self.work / "other.png"
        other.write_bytes(png(9, 9))
        cases = [
            ("missing", ["apply", self.work / "nope.png"], None),
            ("zero", ["apply", zero], None),
            ("text", ["apply", text], None),
            ("dir", ["apply", adir], None),
            ("matugen fails", ["apply", other], self.fake_matugen(fixture=False)),
            ("garbage output", ["apply", other], self.fake_matugen("echo not json")),
            ("bad structure", ["apply", other], self.fake_matugen("echo '{\"colors\": 1}'")),
        ]
        for name, args, mg in cases:
            with self.subTest(name):
                r = self.run_cli(*args, matugen=mg)
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn("Traceback", r.stderr)
                self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_failure_on_fresh_home_creates_nothing(self):
        text = self.work / "text.png"
        text.write_text("hello")
        r = self.run_cli("apply", text)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.snapshot(), {})

    def test_derive_failures(self):
        r = self.run_cli("derive", self.work / "nope.png")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Traceback", r.stderr)

    def test_usage(self):
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.assertNotEqual(self.run_cli("frobnicate", "x").returncode, 0)

    def _stubbed(self, stub_body, no_reload):
        stubs = self.work / "stubs"
        stubs.mkdir(exist_ok=True)
        log = self.work / "calls.log"
        for n in ("pkill", "hyprctl"):
            (stubs / n).write_text(f"#!/bin/sh\necho {n} >> {log}\n{stub_body}\n")
            (stubs / n).chmod(0o755)
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        env = dict(os.environ, HOME=str(self.home), RICE_MATUGEN=str(self.fake_matugen()),
                   PATH=f"{stubs}:{os.environ['PATH']}")
        env.pop("RICE_NO_RELOAD", None)
        if no_reload:
            env["RICE_NO_RELOAD"] = "1"
        r = subprocess.run([sys.executable, str(CLI), "apply", str(img)], env=env,
                           capture_output=True, text=True)
        return r, log

    def test_no_reload_env_skips_reload(self):
        r, log = self._stubbed("exit 0", True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(log.exists())

    def test_reload_runs_and_failure_only_warns(self):
        r, log = self._stubbed("exit 1", False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(log.read_text().split()), ["hyprctl", "pkill"])
        self.assertIn("warning", r.stderr)


    # ---- fix round 1 ----
    def alt_matugen(self):
        doc = json.loads(FIXTURE.read_text())
        doc["colors"]["primary"]["dark"]["color"] = "#7aa2ff"
        doc["colors"]["tertiary"]["dark"]["color"] = "#7aff9a"
        f = self.work / "alt.json"
        f.write_text(json.dumps(doc))
        return self.fake_matugen(f"cat {f}")

    def snap_no_cache(self):
        return {k: v for k, v in self.snapshot().items() if not k.startswith(".cache")}

    def good_apply(self):
        img = self.work / "good.png"
        img.write_bytes(png(8, 8))
        self.assertEqual(self.run_cli("apply", img).returncode, 0)
        other = self.work / "other.png"
        other.write_bytes(png(9, 9))
        return other

    def one_line_failure(self, r):
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Traceback", r.stderr)
        self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
        self.assertNotIn("None", r.stderr)

    def test_unwritable_dir_leaves_files(self):
        other = self.good_apply()
        before = self.snap_no_cache()
        d = self.home / ".config/btop/themes"
        d.chmod(0o500)
        self.addCleanup(d.chmod, 0o700)
        r = self.run_cli("apply", other, matugen=self.alt_matugen())
        self.one_line_failure(r)
        d.chmod(0o700)
        self.assertEqual(self.snap_no_cache(), before)

    def test_blocked_directory_path_fails_cleanly(self):
        other = self.good_apply()
        (self.home / ".config/btop").rename(self.home / "moved")
        (self.home / ".config/btop").write_text("i am a file")
        before = self.snap_no_cache()
        r = self.run_cli("apply", other, matugen=self.alt_matugen())
        self.one_line_failure(r)
        self.assertEqual(self.snap_no_cache(), before)

    def test_replace_failure_rolls_back(self):
        other = self.good_apply()
        last = self.outputs_paths()[-1]
        last.unlink()
        last.mkdir()
        before = self.snap_no_cache()
        r = self.run_cli("apply", other, matugen=self.alt_matugen())
        self.one_line_failure(r)
        self.assertEqual(self.snap_no_cache(), before)
        self.assertTrue(last.is_dir())
        self.assertEqual([p.name for p in self.home.rglob("*.tmp*")], [])

    def test_replace_failure_on_fresh_home_creates_nothing(self):
        last = self.outputs_paths()[-1]
        last.mkdir(parents=True)
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        r = self.run_cli("apply", img)
        self.one_line_failure(r)
        self.assertEqual(self.snap_no_cache(), {})
        self.assertEqual([p.name for p in self.home.rglob("*.tmp*")], [])

    def test_undecodable_matugen_output(self):
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        r = self.run_cli("apply", img, matugen=self.fake_matugen("printf '\\377\\376\\377'"))
        self.one_line_failure(r)
        self.assertEqual(self.snapshot(), {})

    def test_non_executable_matugen(self):
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        mg = self.work / "noexec"
        mg.write_text("#!/bin/sh\ncat x\n")
        mg.chmod(0o644)
        r = self.run_cli("apply", img, matugen=mg)
        self.one_line_failure(r)
        self.assertEqual(self.snapshot(), {})

    def test_bad_cache_entry_is_recomputed(self):
        img = self.work / "a.png"
        img.write_bytes(png(8, 8))
        cache = self.home / ".cache/rice" / (hashlib.sha1(img.read_bytes()).hexdigest() + ".json")
        cache.parent.mkdir(parents=True)
        cache.write_text(json.dumps({f"k{i}": "#000000" for i in range(8)}))
        r = self.run_cli("apply", img)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(set(json.loads(cache.read_text())), KEYS)

    def test_catch_all_in_main(self):
        import contextlib
        import io
        from importlib.machinery import SourceFileLoader
        mod = SourceFileLoader("rice_palette_cli", str(CLI)).load_module()

        def boom(_):
            raise RuntimeError("kaboom")
        mod.derive = boom
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = mod.main(["rice-palette", "derive", "x"])
        self.assertEqual(rc, 1)
        self.assertEqual(len(err.getvalue().strip().splitlines()), 1)
        self.assertNotIn("Traceback", err.getvalue())


@unittest.skipUnless(REAL_MATUGEN.exists(), "private matugen not installed")
class TestRealMatugen(Sandbox):
    def test_grey_and_black_fall_back(self):
        for name, rgb in (("grey", (128, 128, 128)), ("black", (0, 0, 0))):
            img = self.work / f"{name}.png"
            img.write_bytes(png(64, 64, rgb))
            r = self.run_cli("derive", img, real=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            t = json.loads(r.stdout)
            self.assertEqual(set(t), KEYS)
            self.assertGreaterEqual(contrast(t["fg"], t["bg"]), 7)

    def test_huge_dimensions_clean_failure(self):
        img = self.work / "huge.png"
        img.write_bytes(png(60000, 60000, rows=2))
        before = self.snapshot()
        r = self.run_cli("apply", img, real=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Traceback", r.stderr)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
