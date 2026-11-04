# Acceptance run (U14b): success criteria S1-S8

Run on 2026-10-31 against the final tree, commit `78b4e6c` (the commits after it change only docs). It ran
unattended in the private test rig: a headless nested Hyprland 0.56.2 started from `tests/rig/full.lua` (the
production config modules without autostart), with two virtual 1920x1080 outputs `DP-1` and `eDP-1`. Quickshell
0.3.1 ran from the private testbin with a staged HOME (`tests/rig/stage.sh`), `RICE_NO_RELOAD=1` and a private
D-Bus session bus. Nothing touched the live session, the real `~/.config` or the real HOME. No sudo was used,
and every process that was started was stopped by its PID.

How the rig differs from your machine:
- The outputs are headless and have no descriptions. So there is no BenQ `desc:` match: `eDP-1` is pool 1
  (11-15) and `DP-1` is an extra pool (21-25, starting on workspace 6 because there is no persistent rule).
  The rail sits on `DP-1`, the rig's "main" screen.
- Rendering is real GL (Mesa on the AMD iGPU, with the glvnd NVIDIA libraries mapped), but nothing is
  scanned out. The NVIDIA session environment is not set.
- There is no portal and no mako.

Criteria are stated exactly as in spec section 1; none was adjusted.

## Results

| # | Criterion | How measured | Result | Status |
|---|---|---|---|---|
| S1 | All of Quickshell <= 156 MB RSS at idle | rig `qs` with the full shell (bar on both screens, rail, wallpaper on both, default wallpaper staged), 20 s warm-up, then RSS of the qs process tree every 5 s for 60 s (`/proc/<pid>/status`), plus `ps` and `smaps_rollup` | **624 MB RSS** (mean; 638-641 MB range), PSS 338 MB, USS 303 MB. Without the wallpaper image: 550 MB RSS | **NOT MET** (624 vs 156 MB). Indicative only (rig), but it matches the earlier ~620 MB, see `docs/deploy.md` section 11 |
| S2 | Idle CPU < 2 % of one core over 60 s | utime+stime of the qs tree over 63.1 s (`/proc/<pid>/stat`), cross-checked with `top -b` and `ps -o pcpu` | **0.21 %** of one core (0.13 s of CPU in 63.1 s) | VERIFIED in rig (indicative: rig GPU path, no real outputs) |
| S3 | A workspace switch on one screen never changes the other | `tests/hypr/check_pools.sh` (23 checks: Ctrl+N, Ctrl+Alt+Left/Right, the mouse step function, Ctrl+Shift+N) plus `hyprctl monitors -j` before and after, with the full shell running, and both bars' screenshots | Before `DP-1=6 eDP-1=11`; Ctrl+3 on DP-1 gives `DP-1=23 eDP-1=11`; Ctrl+4 on eDP-1 gives `DP-1=23 eDP-1=14`. check_pools 23/23 PASS. Each bar highlights only its own slot (3 on DP-1, 4 on eDP-1) | VERIFIED in rig (real BenQ/panel pool numbers UNVERIFIED: no `desc:` in the rig) |
| S4 | Super+C/V/X/A/Z/F/S/L/T/W/N/R act as Ctrl+key in GUI apps and as kitty's own actions in kitty; Ctrl+C in kitty still interrupts | `python3 -m unittest tests.test_keymap_collisions -v` (the spec table vs `xremap/config.yml`, exact match everywhere) and `xremap --validate-config` (private xremap 0.15.15) | 7/7 tests OK; `Config is valid`, rc 0 | PARTIAL: the mapping is verified statically. The runtime remap on real devices and the behaviour in Firefox, VS Code, JetBrains and kitty are UNVERIFIED (manual matrix in `docs/deploy.md` sections 5 and 7) |
| S5 | No Hyprland bind equals any combination the remapper outputs | `tests/test_keymap_collisions.py::test_no_collisions` (all binds from `binds.lua` via the stubbed `hl`, against every xremap output) | OK (0 collisions; the machinery test proves a planted collision is reported) | VERIFIED in rig (static test) |
| S6 | The two mouse side buttons step the workspace on the focused screen | `hyprctl binds -j` in the rig; check_pools drives the step function behind the buttons | `mouse:275` "previous slot (mouse back)" and `mouse:276` "next slot (mouse forward)" registered (modmask 0). step(+1)/step(-1) move and clamp within the focused pool and leave the other screen alone (PASS) | PARTIAL: real button codes and real presses UNVERIFIED (`wev`, deploy section 5 item 1) |
| S7 | Lid-close and headless behaviour is unchanged | `hyprctl binds -j`, `tests/hypr/lid_headless.sh` (Lua config and the hyprlang stand-in), `tests/test_lid_headless.py` | `switch:on:Lid Switch`, `switch:off:Lid Switch`, `XF86Launch2` registered and locked. The scripts: lid close/open and headless off/on PASS 10/10 (Lua) and 9/9 (legacy), with a fake sudo. Python 14 tests OK | PARTIAL: the switch and the key never fired, and the safe uinput method was not run (it would reach the live session). Real USB power cuts UNVERIFIED. Known behaviour difference: any config reload re-lights a closed lid's panel (deploy section 12) |
| S8 | Shell survives a crash: bar back within 3 s, WM binds unaffected | full shell under the staged `qs-supervise`; SIGKILL the qs child; time until both `rice-bar` layer surfaces are listed again (`hyprctl layers`, polled every 20 ms); Ctrl+2 sent while the shell was down; bind count before and after | Bars gone after 0.05 s, **both bars back after 1.22 s**. Ctrl+2 while the shell was down moved DP-1 to workspace 22. Binds 54 before and 54 after. SIGTERM then stopped the supervisor and its qs. selftest-qs section 4: restart in 1.07 s | VERIFIED in rig |

Unmet: **S1** (624 MB RSS against 156 MB). The owner's options are in `docs/deploy.md` section 11.

## Commands and output

### S1/S2 (default wallpaper staged; scratch script, its S1 part is reproduced below)

```
 layers:
   Monitor DP-1:  rice-wallpaper 0 0 1920 1080 | rice-bar 0 0 1920 26 | rice-rail 1488 26 432 1054 | rice-rail-zone 1919 26 1 1054
   Monitor eDP-1: rice-wallpaper 1920 0 1920 1080 | rice-bar 1920 0 1920 26
 processes in the qs tree: qs(3094485)
  t=0s rss_tree=640856 kB  top %CPU(qs)=0.0
  t=30s rss_tree=639592 kB  top %CPU(qs)=0.0
  t=60s rss_tree=638016 kB  top %CPU(qs)=0.0      (13 samples, all top %CPU 0.0)
 CPU over 63.1 s: 0.13 s of CPU = 0.21 % of one core
 RSS (qs tree) min 638016 kB, max 640856 kB, mean 639735 kB = 624 MB over 13 samples
    PID   RSS %CPU ELAPSED COMMAND
3094485 638016 0.8      83 qs
 qs-mem.py:
   RSS 638016  PSS 346217  USS 309896  (Pss_Anon 283740  Pss_File 62469  Pss_Shmem 7)
   GL driver libraries (Mesa, LLVM, glvnd NVIDIA)                 266300    34941    11348
   anon+heap (QML/JS heap, Qt objects, images, driver CPU state)   265588   265588   265588
   Qt / Quickshell code                                            37128    25341    20676
```

(`ps` %CPU is the lifetime average including startup; the 60 s figure is the tick delta.) The same run without
the wallpaper image (the staged HOME has no `~/Pictures/berserk-wallpaper.jpg`) gave a mean of 563916 kB =
550 MB, PSS 276018, USS 240864, and 0.21 % CPU.

### S3

```
 before: DP-1=6 eDP-1=11 | Ctrl+3 on DP-1: DP-1=23 eDP-1=11 | Ctrl+4 on eDP-1: DP-1=23 eDP-1=14
tests/hypr/check_pools.sh: rc=0 PASS=23 FAIL=0
```

The screenshots (reviewer copies in `.superpowers/.../shots/u14b/`, not in the repo) show each bar with only its
own slot highlighted, and the rail only on DP-1.

### S4/S5

```
$ python3 -m unittest tests.test_keymap_collisions -v
test_collision_machinery_reports_a_colliding_bind ... ok
test_exact_match_everywhere ... ok
test_no_collisions ... ok
test_normalize_forms ... ok
test_parsers_find_sentinels ... ok
test_spec_table_complete ... ok
test_xremap_validates_config ... ok
Ran 7 tests in 0.008s
OK
$ ~/.cache/rice-testbin/root/usr/bin/xremap --validate-config dot_config/xremap/config.yml
Config is valid
rc=0        (xremap 0.15.15)
```

### S6/S7 (`hyprctl binds -j`, rig)

```
{'modmask': 0, 'key': 'mouse:275', 'locked': False, 'dispatcher': '__lua', 'description': 'previous slot (mouse back)'}
{'modmask': 0, 'key': 'mouse:276', 'locked': False, 'dispatcher': '__lua', 'description': 'next slot (mouse forward)'}
{'modmask': 0, 'key': 'XF86Launch2', 'locked': True, 'dispatcher': '__lua', 'description': ''}
{'modmask': 0, 'key': 'switch:on:Lid Switch', 'locked': True, 'dispatcher': '__lua', 'description': ''}
{'modmask': 0, 'key': 'switch:off:Lid Switch', 'locked': True, 'dispatcher': '__lua', 'description': ''}
total binds: 54
tests/hypr/lid_headless.sh (full.lua):    rc=0 PASS=10 FAIL=0
tests/hypr/lid_headless.sh (legacy.conf): rc=0 PASS=9 FAIL=0
```

### S8

```
 supervisor 3092074, qs 3092084, bars up: 2
 SIGKILL qs at 0; bars gone after 0.05 s; both bars back after 1.22 s
 new qs 3092498; DP-1 active workspace after Ctrl+2 while the shell was down: 22; binds before/after: 54/54
 supervisor stopped; qs 3092498 alive: no
   qs-supervise: qs exited (status 137) after 3 s, restarting in 1 s
```

## Whole suite (tree of commit 78b4e6c, exported from the index and run in sequence)

```
LUA 4/4 ok                         (test_autostart, test_binds_nil, test_media_keys, test_pools)
Ran 111 tests in 24.670s  OK       (python3 -m unittest discover -s tests -p 'test_*.py')
SELFTEST OK                        (tests/rig/selftest.sh)
selftest-qs rc=0 PASS=218 FAIL=0   (tests/rig/selftest-qs.sh: SELFTEST-QS OK)
PALETTE_LID OK                     (tests/hypr/palette_lid.sh)
check_pools   rc=0 PASS=23 FAIL=0
lid_headless  rc=0 PASS=10 FAIL=0  (Lua config)   lid_headless rc=0 PASS=9 FAIL=0 (hyprlang stand-in)
pool_hop      rc=0 PASS=10 FAIL=0
dock_scenario rc=0 PASS=8  FAIL=0
```

## `Hyprland --verify-config`

The checks ran on copies, so the live files were untouched (`tests/rig/verify-config.sh`: clean environment and
scratch XDG dirs).

```
# the deployed layout: a copy of dot_config/hypr with create_colors.lua seeded as colors.lua
$ cp -r dot_config/hypr /tmp/final/vc/hypr && mv /tmp/final/vc/hypr/create_colors.lua /tmp/final/vc/hypr/colors.lua
$ tests/rig/verify-config.sh /tmp/final/vc/hypr/hyprland.lua
======== Config parsing result:
config ok
rc=0
# today's live hyprland.conf (the rollback config), copied out first
$ cp -a ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprpaper.conf /tmp/final/vc-live/
$ tests/rig/verify-config.sh /tmp/final/vc-live/hyprland.conf
======== Config parsing result:
config ok
rc=0
$ cmp ~/.config/hypr/hyprland.conf dot_config/hypr/hyprland.conf   -> identical
```

(Hyprland 0.56.2, commit efb50993.)

## qs log cleanliness

The full-shell run logged 6 lines, with one WARN: `qt.qpa.services: Failed to register with host portal ...
org.freedesktop.portal.Desktop was not provided`. This is a rig artefact: the private bus has no portal. The run
without the staged wallpaper also logged `Cannot open: file:///.../Pictures/berserk-wallpaper.jpg`, which is
expected because the image was missing. There were no QML errors, binding loops or TypeErrors. selftest-qs checks
the log per section ("no ERROR/WARN"), and those checks passed.

## No owner Bluetooth names or MAC addresses in the repo

What was grepped: the names and MACs of the 3 devices BlueZ knows (`bluetoothctl devices`, read-only), each MAC in
three forms (`AA:BB:..`, `AABB..`, `AA-BB-..`), case-insensitive. The search covered the tracked files at HEAD
(`git grep`), the worktree (`grep -r`, excluding `.git`, `.superpowers`, `__pycache__`), and all history
(`git log --all -S`). A generic MAC regex `([0-9a-f]{2}:){5}[0-9a-f]{2}` was also run over the tracked files. The
names and MACs themselves are not reproduced here.

Result:
- **One hit, now removed.** The exact BlueZ name of one paired device (a headset model name) was in a
  notes line of `docs/superpowers/design/cyber-terminal-rice.html`. Commit `ef925e1` removed the line
  from the tree; the re-grep shows 0 files at HEAD and 0 in the worktree.
- **The name is still in history.** Commit `ec44ad7` added it, and that commit is already on
  `origin/feat/quickshell-terminal-desktop`. History was not rewritten; that is the owner's call.
- **No MACs anywhere.** Every MAC form gave 0 hits at HEAD, in the worktree and in history, and the
  generic regex matched nothing.
- **Generic model words remain.** "AirPods", "AirPods Pro" and "DualSense" stay in the plan and in the
  mock's example data. They are not the BlueZ names of the owner's devices; the exact-name grep for
  those two devices found nothing.

## Not verified (summary; full list in `docs/deploy.md` section 16)

Everything on the real screens and devices: the memory and CPU on the live session, the BenQ `desc:` matching,
the runtime xremap remap, the physical mouse buttons, the lid switch and headless key firing, real notifications
on the live bus, real apps from the launcher, and real Bluetooth devices.

## Appendix: the S1/S2 measurement (scratch script, run from the repo root)

```bash
R=tests/rig; TB=$HOME/.cache/rice-testbin; H() { "$R/run.sh" hyprctl "$@"; }
"$R/nested-hypr.sh" start "$R/full.lua"
"$R/qs-run.sh" start --restage >/dev/null; "$R/qs-run.sh" stop >/dev/null
mkdir -p "$TB/staged/home/Pictures"; cp ~/Pictures/berserk-wallpaper.jpg "$TB/staged/home/Pictures/"
"$R/qs-run.sh" start
pid=$("$R/qs-run.sh" status | sed -n 's/^running: pid=\([0-9]*\).*/\1/p')
sleep 20
tree() { local p=$1; echo "$p"; for c in $(pgrep -P "$p"); do tree "$c"; done; }
ticks() { local s=0 p; for p in $(tree "$pid"); do
    set -- $(sed 's/^.*) //' "/proc/$p/stat"); s=$((s + ${12} + ${13})); done; echo "$s"; }
rss_tree() { local s=0 p; for p in $(tree "$pid"); do
    s=$((s + $(awk '/^VmRSS/{print $2}' "/proc/$p/status"))); done; echo "$s"; }
t0=$(ticks); for i in $(seq 0 5 60); do rss_tree; [[ $i -lt 60 ]] && sleep 5; done; t1=$(ticks)
echo "CPU % = 100 * (t1 - t0) / $(getconf CLK_TCK) / elapsed"
python3 -I "$R/qs-mem.py" "$pid" 8
"$R/qs-run.sh" stop; "$R/nested-hypr.sh" stop
```

S8 used the same environment as `tests/rig/selftest-qs.sh` section 4, with the full shell. It polled
`hyprctl layers | grep -c 'namespace: rice-bar'` every 20 ms after `kill -KILL <qs child>`.
