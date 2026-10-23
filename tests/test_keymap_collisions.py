"""No Hyprland bind may equal a key combination xremap outputs.

xremap re-emits translated presses through uinput and Hyprland sees them as
real key presses, so an equal bind would fire on every remapped key.
Binds come from actually running binds.lua with a stubbed `hl`; xremap outputs
come from dot_config/xremap/config.yml.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINDS = os.path.join(ROOT, "dot_config/hypr/binds.lua")
DUMP = os.path.join(ROOT, "tests/lua/dump_binds.lua")
XREMAP_CFG = os.path.join(ROOT, "dot_config/xremap/config.yml")

MOD_ORDER = ["ALT", "CTRL", "SHIFT", "SUPER"]
MOD_ALIASES = {
    "ALT": "ALT", "M": "ALT", "META": "ALT", "LEFTALT": "ALT", "RIGHTALT": "ALT",
    "CTRL": "CTRL", "C": "CTRL", "CONTROL": "CTRL", "LEFTCTRL": "CTRL", "RIGHTCTRL": "CTRL",
    "SHIFT": "SHIFT", "LEFTSHIFT": "SHIFT", "RIGHTSHIFT": "SHIFT",
    "SUPER": "SUPER", "WIN": "SUPER", "MOD4": "SUPER", "LOGO": "SUPER", "CMD": "SUPER",
    "LEFTMETA": "SUPER", "RIGHTMETA": "SUPER",
}


def _norm_key(key):
    key = key.strip().upper()
    if key.startswith("KEY_"):
        key = key[4:]
    return key


def _finish(mods, key):
    return "+".join([m for m in MOD_ORDER if m in mods] + [_norm_key(key)])


def normalize_hypr(keys):
    """'CTRL + ALT + Left' / 'SUPER + code:49' -> 'ALT+CTRL+LEFT' / 'SUPER+CODE:49'."""
    parts = [p.strip() for p in keys.split("+") if p.strip()]
    mods = {MOD_ALIASES[p.upper()] for p in parts[:-1]}
    return _finish(mods, parts[-1])


def normalize_xremap(combo):
    """'Super-Shift-t' / 'C-Left' / 'Home' -> normalised form."""
    mods = set()
    rest = combo.strip()
    while True:
        m = re.match(r"^([A-Za-z_0-9]+)-(?=.)", rest)
        if not m or m.group(1).upper() not in MOD_ALIASES:
            break
        mods.add(MOD_ALIASES[m.group(1).upper()])
        rest = rest[m.end():]
    return _finish(mods, rest)


def parse_binds(binds_lua=BINDS):
    """Run binds.lua with a recording `hl` stub and return normalised keys."""
    for interp in ("lua", "luajit"):
        exe = shutil.which(interp)
        if exe:
            break
    else:
        raise AssertionError("neither lua nor luajit is installed")
    out = subprocess.run([exe, DUMP, binds_lua], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout
    return {normalize_hypr(line) for line in out.splitlines() if line.strip()}


def _keymap_blocks(path=XREMAP_CFG):
    """Split the file into keymap entries (each starts with '  - ')."""
    blocks, cur = [], None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if re.match(r"^  - ", line):
                cur = []
                blocks.append(cur)
            if cur is not None:
                cur.append(line)
    return blocks


def _remap_pairs(block):
    pairs, in_remap = [], False
    for line in block:
        if re.match(r"^\s*#", line) or not line.strip():
            continue
        if re.match(r"^\s*remap:\s*$", line):
            in_remap = True
            continue
        m = re.match(r"^\s{6,}([^\s:#][^:#]*):\s*([^\s#]+)\s*(#.*)?$", line)
        if in_remap and m:
            pairs.append((m.group(1).strip(), m.group(2).strip()))
        elif in_remap and not line.startswith(" " * 6):
            in_remap = False
    return pairs


def parse_xremap_outputs(path=XREMAP_CFG):
    return {normalize_xremap(out) for b in _keymap_blocks(path) for _, out in _remap_pairs(b)}


def find_collisions(binds, outputs):
    return sorted(set(binds) & set(outputs))


def find_xremap():
    cached = os.path.expanduser("~/.cache/rice-testbin/root/usr/bin/xremap")
    if os.access(cached, os.X_OK):
        return cached
    return shutil.which("xremap")


class KeymapCollisionTest(unittest.TestCase):
    def test_normalize_forms(self):
        self.assertEqual(normalize_hypr("CTRL + ALT + Left"), "ALT+CTRL+LEFT")
        self.assertEqual(normalize_hypr("ctrl + alt + left"), "ALT+CTRL+LEFT")
        self.assertEqual(normalize_hypr("SUPER + code:49"), "SUPER+CODE:49")
        self.assertEqual(normalize_hypr("Print"), "PRINT")
        for form in ("C-Left", "Ctrl-Left", "Ctrl-left", "Control-LEFT"):
            self.assertEqual(normalize_xremap(form), "CTRL+LEFT")
        for form in ("M-Left", "Alt-Left"):
            self.assertEqual(normalize_xremap(form), "ALT+LEFT")
        for form in ("Super-Shift-t", "Win-Shift-T", "Shift-Super-t"):
            self.assertEqual(normalize_xremap(form), "SHIFT+SUPER+T")
        self.assertEqual(normalize_xremap("Home"), "HOME")
        self.assertEqual(normalize_xremap("Ctrl-Shift-Home"), "CTRL+SHIFT+HOME")
        self.assertEqual(normalize_xremap("C-Alt-KEY_BACKSPACE"), "ALT+CTRL+BACKSPACE")

    def test_parsers_find_sentinels(self):
        binds = parse_binds()
        for s in ("CTRL+1", "ALT+CTRL+LEFT", "SUPER+SPACE"):
            self.assertIn(s, binds)
        outputs = parse_xremap_outputs()
        for s in ("CTRL+C", "CTRL+LEFT", "HOME"):
            self.assertIn(s, outputs)

    def test_no_collisions(self):
        self.assertEqual(find_collisions(parse_binds(), parse_xremap_outputs()), [])

    def test_collision_machinery_reports_a_colliding_bind(self):
        # Copy hypr/ to a temp dir, add a bind equal to an xremap output, and
        # check the machinery reports it (proves the guard can fail).
        with tempfile.TemporaryDirectory() as tmp:
            hypr = os.path.join(tmp, "hypr")
            shutil.copytree(os.path.join(ROOT, "dot_config/hypr"), hypr)
            path = os.path.join(hypr, "binds.lua")
            with open(path, encoding="utf-8") as f:
                src = f.read()
            src = src.replace("return M\n", 'hl.bind("Ctrl + Left", function() end)\nreturn M\n')
            with open(path, "w", encoding="utf-8") as f:
                f.write(src)
            self.assertEqual(
                find_collisions(parse_binds(path), parse_xremap_outputs()), ["CTRL+LEFT"])

    def test_exact_match_everywhere(self):
        blocks = _keymap_blocks()
        self.assertTrue(blocks, "no keymap entries found")
        for b in blocks:
            text = "\n".join(b)
            self.assertRegex(text, r"(?m)^    exact_match: true\s*$", b[0])
            self.assertRegex(text, r"(?m)^\s+not: \[kitty\]\s*$", b[0])

    def test_spec_table_complete(self):
        pairs = {k: v for b in _keymap_blocks() for k, v in _remap_pairs(b)}
        norm = {normalize_xremap(k): normalize_xremap(v) for k, v in pairs.items()}
        want = {}
        for l in "cvxazfslwnrt":
            want[f"SUPER+{l.upper()}"] = f"CTRL+{l.upper()}"
        for l in "tzn":
            want[f"SHIFT+SUPER+{l.upper()}"] = f"CTRL+SHIFT+{l.upper()}"
        want.update({
            "SUPER+LEFT": "HOME", "SUPER+RIGHT": "END",
            "SHIFT+SUPER+LEFT": "SHIFT+HOME", "SHIFT+SUPER+RIGHT": "SHIFT+END",
            "SUPER+UP": "CTRL+HOME", "SUPER+DOWN": "CTRL+END",
            "ALT+LEFT": "CTRL+LEFT", "ALT+RIGHT": "CTRL+RIGHT",
            "ALT+BACKSPACE": "CTRL+BACKSPACE",
            "ALT+SHIFT+LEFT": "CTRL+SHIFT+LEFT", "ALT+SHIFT+RIGHT": "CTRL+SHIFT+RIGHT",
        })
        self.assertEqual(norm, want)

    def test_xremap_validates_config(self):
        exe = find_xremap()
        if not exe:
            self.skipTest("no xremap (run tests/rig/setup-testbin.sh for the private binary)")
        r = subprocess.run([exe, "--validate-config", XREMAP_CFG],
                           capture_output=True, text=True)
        self.assertIn("Config is valid", r.stdout + r.stderr)
        self.assertEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
