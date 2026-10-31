# Deploying the Quickshell terminal desktop

Owner's guide. Written 2026-10-25 for branch `feat/quickshell-terminal-desktop`. Read all of it
once before you touch anything; the commands are copy-pasteable in the order given.

Contents: 1 what this is, 2 prerequisites, 3 xremap permissions, 4 back up and apply,
5 first-boot checklist, 6 key scheme, 7 terminal-safety checklist, 8 Claude limits,
9 wallpapers, 10 NVIDIA / GPU, 11 memory (budget NOT met), 12 known issues, 13 rollback,
14 cleanup, 15 every ruling made during the build, 16 everything that was not verified.

## 1. What this is, and the warning

This branch replaces waybar + wofi + mako + hyprpaper with one Quickshell shell (a bar on each
screen, a right-hand rail on the main screen, wallpaper layer, launcher, notification toasts,
wallpaper carousel), moves Hyprland to a Lua config with one workspace pool per screen, adds an
xremap config that gives you Mac-style Super/Alt shortcuts, a kitty config, and two small tools
(`rice-palette` for the wallpaper palette, `claude-limits-statusline` for Claude usage limits).

**Nothing was deployed while this was built.** The whole build ran against a private, headless,
nested Hyprland test rig under `tests/rig/`; your live session, `~/.config`, `~/.claude` and the
system packages were never changed. So every claim about your real screens, keyboard, mouse,
lid, GPU and Bluetooth devices is unverified (full list in section 16).

**Apply the whole branch at once, and only after reading this file.** The pieces depend on each
other: the Lua config starts `qs-supervise` and `xremap`, `Super+Space` calls the Quickshell
launcher, and the old waybar/mako/hyprpaper autostart lines are gone from the Lua config.
Applying half of it leaves you without a launcher or without a bar. The old files stay in the
repo and on disk for rollback (section 13).

Behaviour changes you will notice immediately: the terminal is now `Ctrl+Alt+T` (not `Super+T`),
exit is `Ctrl+Alt+Shift+Q`, and `Super+C/V/X...` act like `Ctrl+C/V/X...` (section 6).

Accepted losses against the waybar bar: **there is no system tray**, so the `blueman-applet` and `librepods`
icons (both still started by the autostart) are not shown and their menus are unreachable; the VOL chip is
read-only (no scroll-to-change, no click for pavucontrol; use the volume keys or `pavucontrol` from the
launcher); there is no backlight or temperature chip. If you need the tray, keep waybar's tray (section 11
option 4) or ask for a Quickshell tray widget.

The branch has to be what your chezmoi source directory (`~/.local/share/chezmoi`) has checked
out before you apply, for example after merging the draft PR, or with
`git -C ~/.local/share/chezmoi switch feat/quickshell-terminal-desktop`. To try it from another
checkout, pass its path: `chezmoi -S /path/to/checkout diff` and `chezmoi -S /path/to/checkout apply`.

**Before that, merge the small prerequisite PR "chore: sync live hypr/hyprpaper/waybar configs into the
repo" into `main`** (section 13 explains why: without it `main`'s `hyprland.conf` is a stale stub and a
rollback to `main` would overwrite your real config).

## 2. Prerequisites

Official repos:

```sh
sudo pacman -S --needed quickshell matugen wev
```

Already present on your machine when this was written: `kitty`, `grim`, `slurp`,
`ttf-jetbrains-mono-nerd` (the shell and kitty use "JetBrainsMono Nerd Font Mono"), `python`,
`util-linux` (`setpriv`), `file`.

AUR, the remapper:

```sh
yay -G xremap-hypr-bin          # or: paru -G xremap-hypr-bin   (downloads the PKGBUILD only)
less xremap-hypr-bin/PKGBUILD   # review it first: source URL, checksums, install steps
yay -S xremap-hypr-bin          # or: paru -S xremap-hypr-bin
```

The build and review used xremap 0.15.15 (the Hyprland build); the spec noted `xremap-hypr-bin`
0.15.15 in the AUR on 2026-10-21. Check that `xremap --version` runs and that `xremap` is on the
PATH Hyprland uses (the autostart line is plain `xremap`).

You do NOT need the test rig's private binaries (`tests/rig/setup-testbin.sh` downloads
quickshell, labwc, wtype, a static shellcheck and so on into `~/.cache/rice-testbin/`). That is
for running the rig only.

## 3. xremap permissions

xremap needs read access to `/dev/input/event*` (your keyboards and mouse) and write access to
`/dev/uinput` (to emit the translated keys). Today you are in `users docker wheel`, not
`input`. On this machine `/dev/uinput` was writable by your user through a file ACL (see your uinput
note), but that is not something to rely on across reboots or updates. Without access xremap starts
and then does nothing or exits; the autostart shows no visible error.

Check first:

```sh
id -nG
ls -l /dev/uinput /dev/input/event*
lsmod | grep uinput || echo "uinput module not loaded"
```

If the module is not loaded at boot: `echo uinput | sudo tee /etc/modules-load.d/uinput.conf`.

**Option A: the `input` group (simplest, broadest).**

```sh
sudo gpasswd -a "$USER" input
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
  | sudo tee /etc/udev/rules.d/99-uinput.rules
sudo udevadm control --reload && sudo udevadm trigger
```

Implication: every process you run, from any login (a terminal in the session, an SSH session to
this machine, a cron job), can read every key you type on every keyboard (a keylogger needs no
root) and, because `/dev/uinput` becomes writable, can also inject keystrokes (type commands into
a terminal). Needs a full log out and in (a new login) before the group applies.

**Option B: udev rule with `uaccess`, no group.**

```sh
sudo tee /etc/udev/rules.d/70-xremap.rules <<'RULES'
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
RULES
sudo udevadm control --reload && sudo udevadm trigger
```

The file name matters: systemd turns the `uaccess` tag into ACLs in `73-seat-late.rules`, so a rule
file sorted after 73 (such as `99-...`) adds a tag that is never acted on and you end up with no ACLs
and an xremap that silently does nothing. Keep the number below 73.

Implication: the user logged in at the local seat gets an ACL on all input devices (read every key)
and on `/dev/uinput` (inject keystrokes); SSH sessions and cron jobs do not. Still a keylogger and
key-injection risk for anything running in your graphical session. Log out and
in so the ACLs apply to the new session. Note: both rule sets follow xremap's documented setup and
systemd's `uaccess` convention; they were not run during the build (no sudo was available), so check
`ls -l /dev/uinput` and `getfacl /dev/input/event*` after applying.

Check after re-login: `xremap --list-devices` lists your keyboards and mouse without sudo (this is the
permission test; `xremap --list-windows` only queries the compositor for window class names and does
not test device access), and `pgrep -a xremap` should show the process after Hyprland starts.

**Hot-plug.** The autostart line runs `xremap --watch=device ~/.config/xremap/config.yml`, so xremap also
grabs keyboards that appear after it started: a dock keyboard, and the G502 and the Semico keyboard, which
come back as NEW input devices after the headless toggle restores their USB power. Without `--watch` the
Mac shortcuts would silently stop on the external keyboard until the next login. (`--watch=device` was
checked against xremap 0.15.15's `--help` and with `--validate-config` on this config; xremap re-grabbing
a real re-plugged device was not tested.)

## 4. Diff, back up, apply, log out and in

First look at what chezmoi would do. The live `~/.config/hypr` may have drifted since the repo copy
was synced from it (the build synced live to repo once, on 2026-10-23, before porting), and so may
other managed files (`~/.bashrc`, `~/.gitconfig`, nvim, the caddy/plex/vpn-torrenting compose files,
btop):

```sh
chezmoi diff | less -R         # read it all
chezmoi status
```

Then back up with the pattern you already use. Either snapshot every managed target that exists
(simplest and complete), or only the ones `chezmoi status` shows as modified:

```sh
stamp=$(date +%Y%m%d-%H%M%S)
# all managed files that exist now (directories are skipped):
chezmoi managed --include=files --path-style=absolute | while read -r f; do
  [ -f "$f" ] && cp -a "$f" "$f.bak.$stamp"
done
ls ~/.config/hypr/*.bak.* ~/.config/waybar/*.bak.* 2>/dev/null
```

(Whichever way you choose, `hyprland.conf`, `hyprpaper.conf`, the waybar and wofi files, the two
scripts below, and anything `chezmoi status` marks as modified must be covered: section 13 restores
from these backups. Delete the `*.bak.*` files you no longer need later; chezmoi ignores them.)

**`~/.local/bin/lid` and `~/.local/bin/headless` are overwritten.** They are now in the repo
(`dot_local/bin/executable_lid`, `executable_headless`), ported to the Lua config, so `chezmoi apply`
replaces your current copies (the `chezmoi managed` loop above backs them up). Your copies call
`hyprctl keyword monitor` and `hyprctl dispatch dpms`, which Hyprland 0.56 refuses under the Lua config
(`keyword can't work with non-legacy parsers. Use eval.`), so with the old scripts a lid close would not
drop the panel and the headless key would cut the mouse and keyboard but leave the screens lit.
What changed (`chezmoi diff` shows it):

- both scripts try the Lua form first (`hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'`,
  `hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'`) and fall back to the old hyprlang form, so they also
  work after a rollback to `hyprland.conf`; success is the literal `ok` reply (hyprctl exits 0 on a refusal);
- `headless` now turns the displays off BEFORE cutting the peripherals, and only if that worked
  (otherwise it prints `dpms off failed; peripherals left powered` and exits 1); on restore it powers the
  peripherals back BEFORE turning the displays on. Your copy cut the peripherals first;
- `lid close` exits 1 with a message if neither form disabled the panel. The guards (2 s double-tap guard,
  "only while another output is live") and the `sudo -n ... || true` calls are unchanged.

Expected: new files (hyprland.lua, binds.lua, autostart.lua, lib/pools.lua, quickshell/*,
xremap/config.yml, kitty/*, the three new `~/.local/bin` tools, `~/.local/share/rice/*.py`), changed
`~/.local/bin/lid` and `~/.local/bin/headless` (above), and a changed
waybar `config.jsonc` (the interim persistent-workspaces edit). The colour files (`colors.lua`,
`colors.json`, `colors.conf`) are `create_` files: written once if absent, never overwritten
afterwards, because `rice-palette` owns them. `docs/`, `tests/` and the repo `README.md` are not deployed (`.chezmoiignore`).

Apply (this branch is designed to go all at once, so apply everything):

```sh
chezmoi apply
```

Hyprland reloads its config when a file changes, so while the files land the running session may
briefly reload a half-written Lua config. If you prefer, run the apply from a TTY (`Ctrl+Alt+F3`)
after leaving Hyprland. Then check the new config parses before you log out:

```sh
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua    # expect: config ok
```

**Mask mako before the first login on the new config.** mako ships a D-Bus activation file
(`/usr/share/dbus-1/services/fr.emersion.mako.service`, `SystemdService=mako.service`) that claims
`org.freedesktop.Notifications`. Your user bus is dbus-broker and the systemd user environment has
`WAYLAND_DISPLAY`, so any notification sent before the shell registers (an AirPods or blueman notice
from the same `hyprland.start` batch, or the ~1-2 s gap while `qs-supervise` restarts qs) would start
mako; the shell then only gets the name when mako leaves, which it never does, so toasts would silently
never appear for the whole session. Prevent the activation:

```sh
systemctl --user mask mako.service      # or uninstall mako: sudo pacman -Rns mako
```

(`systemctl --user unmask mako.service` undoes it; section 13. The old `hyprland.conf` starts mako by its
`exec-once` line, not through systemd, so the rollback session still gets mako.)

Log out of Hyprland and log in again (needed for `hl.env`, the autostart and the `input` group).
**When both exist, `~/.config/hypr/hyprland.lua` takes precedence over `hyprland.conf`**; checked in
the rig (Hyprland 0.56.2 logs `Using lua config found at .../hyprland.lua`). `hyprland.conf` stays
next to it as the rollback copy.

If something is wrong at login, switch to a TTY (`Ctrl+Alt+F3`) and use section 13.

## 5. First-boot verification checklist

Do these in order. Anything that fails: note it, and use section 13 if the desktop is unusable.

1. **Mouse side buttons.** Run `wev`, move the pointer over its window, press each side button of the
   G502. Expected button codes: `275` (back) and `276` (forward). The binds are
   `hl.bind("mouse:275", ...)` and `hl.bind("mouse:276", ...)` in `dot_config/hypr/binds.lua`. If wev
   shows other numbers, edit those two numbers in the repo copy and re-apply. They step the workspace
   on the focused screen (previous/next slot). Side effect: bare side buttons no longer act as browser
   back/forward.
2. **Key under Esc.** Run `wev` and press the key under Esc (Super not held). Expect `code 49`. The bind
   is `SUPER + code:49` (focus the other monitor). On the pt layout that key gives the keysym
   backslash, not grave, which is why it is bound by code. If your code differs, change the single
   `code:49` in `binds.lua`. Then press `Super` + that key: focus should jump to the other screen.
3. **Lid switch.** The lid binds (`switch:on:Lid Switch` and `switch:off:Lid Switch`, running
   `~/.local/bin/lid close` / `open`) are ported verbatim; the script itself is now the repo's ported copy
   (section 4). Quick check without the switch: `~/.local/bin/lid close` with the BenQ connected must drop
   `eDP-1` (`hyprctl monitors` lists only the BenQ, the panel's workspaces 11-15 move to it), and
   `~/.local/bin/lid open` brings it back (it runs `hyprctl reload`, which re-applies the `hl.monitor` line
   from `hyprland.lua`; that reload is the only thing that re-enables the panel). Do not close the lid to test it. Use your
   existing fake-switch method (your note "simulating input events with uinput"): a virtual device named
   exactly `Lid Switch`, firing `SW_TABLET_MODE`, which logind ignores. First confirm logind really
   ignores the lid, from the live value and not the config file:

   ```sh
   busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
     org.freedesktop.login1.Manager HandleLidSwitch      # want: s "ignore"
   ```

   Expect the first event to disable `eDP-1` (the panel goes dark, its workspaces move to the BenQ)
   and the second to re-enable it. Do NOT fire `SW_LID` unless `HandleLidSwitch`, `HandleLidSwitchExternalPower`
   and `HandleLidSwitchDocked` all read `ignore` (query each with the `busctl get-property` command
   above): if one does not, the machine really suspends. Recipe (python3, no root because `/dev/uinput` is writable
   for you; adapted from your note, NOT run by the author):

   ```python
   import fcntl, os, struct, time
   EV_SW, SW_TABLET_MODE = 5, 1
   fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
   fcntl.ioctl(fd, 0x40045564, EV_SW)                 # UI_SET_EVBIT
   fcntl.ioctl(fd, 0x4004556D, SW_TABLET_MODE)        # UI_SET_SWBIT
   fcntl.ioctl(fd, 0x405C5503, struct.pack("HHHH80sI", 0x03, 0, 0, 0, b"Lid Switch", 0))  # UI_DEV_SETUP
   fcntl.ioctl(fd, 0x5501)                            # UI_DEV_CREATE
   time.sleep(2)                                      # let udev / libinput / Hyprland see it
   def ev(v):
       os.write(fd, struct.pack("llHHi", 0, 0, EV_SW, SW_TABLET_MODE, v))
       os.write(fd, struct.pack("llHHi", 0, 0, 0, 0, 0))   # SYN_REPORT
   ev(1); time.sleep(3); ev(0); time.sleep(1)
   fcntl.ioctl(fd, 0x5502)                            # UI_DEV_DESTROY
   ```

   **Headless key.** Before you press it, know the recovery: if the mouse and keyboard stay dead, run
   `sudo /usr/local/bin/headless-peripherals on` from the laptop's internal keyboard (in a terminal, or from
   a TTY with `Ctrl+Alt+F3`). Press `XF86Launch2`: all screens go dark (`hyprctl monitors -j` shows
   `"dpmsStatus": false` everywhere, check over SSH or after restoring) and then the G502 and the Semico
   keyboard lose power. Wait more than 2 s (double-tap guard), press it again: the peripherals come back
   first, then the screens. If the screens did not go dark, the script printed `dpms off failed;
   peripherals left powered` and did not cut anything (run `~/.local/bin/headless` in a terminal to see it).
   After the restore the external keyboard is a new input device; xremap picks it up again
   (`--watch=device`, section 3), so `Super+C` must still copy in Firefox from the Semico keyboard.
4. **BenQ matching.** `hyprctl monitors`: the BenQ must show description `BNQ BenQ EX2510S K8M02386019`
   (it is matched by description, not by the port name) at `0x0`, and `eDP-1` at `1920x0`. This was not
   testable in the rig (headless outputs have no description). If the BenQ is not matched, the pool
   assignment, the workspace-1 default and the rail's "main screen" choice all fall back and the pools
   may be swapped.
5. **Pool behaviour and unplug.** `Ctrl+1..5` focuses workspaces 1-5 on the BenQ and 11-15 on the laptop
   panel, independently: compare `hyprctl monitors -j` before and after a switch, the other screen's
   workspace must not change. Unplug the BenQ: its windows move onto the panel, none is lost, and they
   return when it is plugged back in. The lid-closed-with-no-external-screen case is covered only by a
   stub test.
   **Moved pools.** While a screen is gone its pool lives on the other one: unplugging the BenQ moves 1-5
   onto the panel, closing the lid moves 11-15 onto the BenQ. `Ctrl+1..5`, `Ctrl+Alt+Left/Right` and the
   mouse side buttons only ever reach the focused screen's OWN pool, so the moved windows are out of their
   reach. `Ctrl+Alt+Up` / `Ctrl+Alt+Down` jump to the same slot in the next/previous pool that has a
   workspace on the focused screen (wrapping; nothing happens when there is only one): on the panel with
   the BenQ unplugged, `Ctrl+3` then `Ctrl+Alt+Up` lands on workspace 3, where the BenQ's slot-3 windows
   are. The bar follows the active workspace's pool, so it shows 1-5 while you are there. From a moved
   workspace, `Ctrl+N` and the step keys go back into the screen's own pool; to reach another slot of the
   moved pool, pick that slot with `Ctrl+N` and hop again. Check it: unplug the BenQ (or
   `~/.local/bin/lid close` for the other direction), hop, see the windows, plug back in.
6. **Bar and rail on both screens.** A bar on the top of each screen showing its own five workspaces
   (active filled, occupied underlined; CPU, MEM, VOL, NET and BAT chips). The rail (clock, sys meters,
   media, bluetooth, claude) only on the BenQ. Wallpaper on both screens (default image
   `~/Pictures/berserk-wallpaper.jpg`).
7. **Launcher.** `Super+Space` opens it; type to filter, Up/Down, Enter runs, Escape closes. After
   closing, typing must reach the window underneath.
8. **Carousel and palette.** Put images in `~/Pictures/wallpapers/` (section 9), press `Ctrl+Alt+W`,
   scroll with Left/Right (the wallpaper previews live), Enter applies (runs `rice-palette apply`,
   recolours kitty, Hyprland borders and the shell), Escape reverts. Or from a terminal:
   `rice-palette apply ~/Pictures/wallpapers/<image>`.
   The carousel runs `$HOME/.local/bin/rice-palette` by its absolute path, because the session's PATH
   has no `~/.local/bin`: read from the running Hyprland's `/proc/<pid>/environ` (session started by
   greetd -> tuigreet -> `start-hyprland`, so `.bashrc` never runs) it is
   `/usr/local/sbin:/usr/local/bin:/usr/bin:...:JetBrains/Toolbox/scripts`. The rig runs the whole
   carousel test with that kind of PATH (no `~/.local/bin` at all). No PATH workaround is needed.
   Escape works even while an apply runs (the apply finishes in the background and the colours land a
   moment later). If an apply gives no result within 15 s the strip shows `✗ apply timed out` and gives
   the keyboard back; close it with `Ctrl+Alt+W`. Applying with the lid closed must leave the panel
   dark: `hyprctl monitors all` still lists eDP-1 as disabled afterwards (the apply recolours the
   borders at runtime and never reloads the config).
   The launcher and the carousel never stay open together: opening one closes the other.
9. **Toasts replace mako.** `pgrep -x mako` must print nothing and the shell must own the notification
   name: `notify-send "test" "hello"` shows a cut-corner toast at the bottom-right of the main screen;
   a click dismisses it; at most three at once. The owner of the name must be the shell, not mako:

   ```sh
   busctl --user status org.freedesktop.Notifications | grep -E '^(PID|Comm)='   # want Comm=qs (or quickshell)
   systemctl --user is-enabled mako.service                                     # want: masked (section 4)
   ```

   If `Comm=mako`, mako was activated before the shell (the mask is missing): mask it, `pkill -x mako`, and
   the shell takes the name.
10. **Volume keys and the tray.** The laptop's volume keys change the volume (`wpctl get-volume
    @DEFAULT_AUDIO_SINK@` before and after, and the VOL chip follows), mute toggles, mic mute toggles the default
    source. No tray: if you depend on the blueman or librepods tray menus, decide now (section 1).
11. **Bluetooth widget.** The rail section lists connected devices with their battery when BlueZ reports
    one (hidden while nothing is connected). Connect a device and see it appear. AirPods left/right/case
    levels are not shown by design.
12. **Status line / Claude limits.** Section 8. The claude section reads `no data` until you enable the
    status line and send one message.
13. **Memory and CPU.** After 60 s idle on both screens:

    ```sh
    pid=$(pgrep -x qs | head -1)
    ps -o rss,pcpu,comm -p "$pid"                                   # RSS in KB
    grep -E '^(Rss|Pss|Private_Clean|Private_Dirty):' /proc/$pid/smaps_rollup
    #   PSS = Pss, USS = Private_Clean + Private_Dirty
    top -b -n 2 -d 30 -p "$pid" | tail -2                           # CPU %, second sample
    python3 ~/.local/share/chezmoi/tests/rig/qs-mem.py "$pid"       # optional: breakdown by mapping
    ```

    Budget and what to expect: section 11.
14. **Collision sanity.** `Ctrl+Left/Right` word jump still works in a GUI text field (it is remapped from
    `Alt+Left/Right`), `Ctrl+Alt+Left/Right` steps workspaces, nothing steps by accident.

## 6. Key scheme

All window-manager binds use `Super`, `Ctrl+Alt` or `Ctrl` with a digit; none of them equals an xremap
output. **The collision rule:** the remapper re-injects its translated keys, which re-enter the
compositor, so no Hyprland bind may equal any combination xremap emits (`Ctrl+Left` is emitted for word
jump, so workspace stepping is `Ctrl+Alt+Left/Right`). `tests/test_keymap_collisions.py` enforces it.

**xremap outputs (GUI apps, not kitty):**

| Pressed | Sent |
|---|---|
| Super + c v x a z f s l t w n r | Ctrl + same letter |
| Super + Shift + t z n | Ctrl + Shift + same letter |
| Super + ← → | Home, End |
| Super + Shift + ← → | Shift + Home, Shift + End |
| Super + ↑ ↓ | Ctrl + Home, Ctrl + End |
| Alt + ← → Backspace | Ctrl + ← → Backspace |
| Alt + Shift + ← → | Ctrl + Shift + ← → |

**Hyprland binds:**

| Keys | Action |
|---|---|
| Ctrl + 1..5 | focus slot on this screen's pool |
| Ctrl + Shift + 1..5 | move window to slot on this screen's pool |
| Ctrl + Alt + ← → and mouse side buttons | step previous/next slot on this screen |
| Ctrl + Alt + ↑ ↓ | same slot in the next/previous pool present on this screen (reaches the workspaces a removed screen left here; no-op with one pool) |
| Super + Alt + ←↑↓→ or h j k l | focus window |
| Super + Alt + Shift + ←↑↓→ or h j k l | move window (crosses to the other screen at an edge) |
| Super + the key under Esc (code:49) | focus the other monitor (bound by keycode: on the owner's pt layout that key's keysym is backslash, not grave) |
| Super + Tab | cycle windows on the current workspace (not across the screen or the other workspaces) |
| Super + Space | launcher |
| Super + Q | close window |
| Super + Ctrl + F | fullscreen |
| Super + Alt + Space | toggle floating |
| Ctrl + Alt + T / F / C / E / R / I | terminal, Firefox, VS Code, yazi, Rider, IntelliJ (the current Super+T/F/C/E/R/I launches) |
| Ctrl + Alt + W | carousel |
| Ctrl + Alt + Shift + Q | exit Hyprland (was Super+M) |
| Print | region screenshot (unchanged) |
| XF86AudioRaiseVolume / LowerVolume / Mute / MicMute | volume ±5 % (capped at 100 %, repeats while held), mute, mic mute via `wpctl`; work on a locked screen. No brightness keys (brightnessctl is not installed) |
| XF86Launch2 | headless toggle (`~/.local/bin/headless`, now in the repo, ported to the Lua config) |
| lid switch on/off | `~/.local/bin/lid close` / `open` (now in the repo, ported to the Lua config) |

In kitty nothing is remapped: Super combinations go to kitty's own maps (`super+c` copy, `super+v`
paste, `super+t` new tab, `super+w` close tab, `super+n` new OS window) and Ctrl combinations stay raw,
so `Ctrl+C` still interrupts.

## 7. Terminal-safety manual checklist

Run on the live desktop after applying, with xremap running. None of this could be tested against real
windows during the build.

1. In kitty: run `sleep 100`, press `Ctrl+C`: the process is interrupted (SIGINT), nothing is pasted or copied.
2. In kitty: select text, press `Super+C`, then `Super+V` in the prompt: the text is pasted. `Ctrl+Shift+C/V` still work.
3. In kitty: `Super+T` opens a tab, `Super+W` closes it, `Super+N` opens a new window; `Ctrl+Left/Right` and `Home/End` behave normally in the shell. With `sleep 100` running in a tab, `Super+W` (and `Super+Q` on the window) must ask before closing: kitty's default `confirm_os_window_close -1` asks only when a command is running, which needs kitty's shell integration (on by default for bash); without it kitty asks for every tab (seen in the test rig).
4. In Firefox and VS Code: `Super+C/V/X/A/Z/F/S` act as `Ctrl+` the same key; `Super+Left/Right` go to line start/end; `Alt+Left/Right` move by word (note: `Alt+Left` in Firefox no longer means Back).
5. In a JetBrains IDE: repeat 4; check `Super+arrows`, `Alt+arrows` and `Alt+Backspace`; confirm with `hyprctl clients` that the class names are matched (kitty is excluded by class `kitty`; `xremap --list-windows` prints the names xremap sees).
6. Confirm `Ctrl+1..5`, `Ctrl+Alt+arrows` and `Super+Space` still trigger Hyprland binds and are not triggered by any remapped key.
7. **Integrated terminals are not kitty.** In the VS Code or JetBrains integrated terminal, `Super+C` becomes `Ctrl+C` (xremap only skips the kitty window class): with nothing selected it interrupts the running process (SIGINT) instead of copying. Run `sleep 100` there and press `Super+C` to see it; use the IDE's own copy binding (or select first) inside those terminals.

## 8. Claude limits

The widget in the rail reads `~/.cache/claude-limits.json`, written by `claude-limits-statusline` when
Claude Code runs it as its status line. Setup, caveats and removal are in
[`docs/claude-statusline.md`](claude-statusline.md).

The `statusLine` entry in `~/.claude/settings.json` was **deliberately NOT applied**: it edits a Claude
Code settings file outside the dotfiles. Add it yourself when you want it (the exact snippet is in the
linked doc). Side effect to expect: once a custom status line exists, Claude Code hides most of its
footer keyboard hints. Whether your plan reports `rate_limits` at all is unverified (upstream issue
anthropics/claude-code #45133); if it does not, the widget shows `no data`.

## 9. Wallpapers and the palette

Put images in `~/Pictures/wallpapers/` (the folder does not exist yet). The carousel (`Ctrl+Alt+W`) lists
that folder. Until you apply one, both screens show `~/Pictures/berserk-wallpaper.jpg`. Seed suggestions
from the spec: that Berserk image and the three Hyprland default wallpapers.

```sh
mkdir -p ~/Pictures/wallpapers
cp ~/Pictures/berserk-wallpaper.jpg ~/Pictures/wallpapers/
~/.local/bin/rice-palette apply ~/Pictures/wallpapers/berserk-wallpaper.jpg
```

`rice-palette apply <image>` runs `matugen` to extract the image's colours, derives the eight palette
tokens (bg panel line dim fg a1 a2 warn) with contrast guarantees, writes `~/.config/quickshell/colors.json`,
`~/.config/kitty/colors.conf`, `~/.config/hypr/colors.lua` and `~/.config/btop/themes/rice.theme`
all-or-nothing, records the choice in `~/.local/state/quickshell/wallpaper.json`, then recolours kitty
(SIGUSR1) and the running Hyprland's borders (`hyprctl eval 'hl.config({ general = { col = ... } })'`;
a failure, for example under the hyprlang rollback config, only prints a warning). It never runs
`hyprctl reload`: a reload re-applies the monitor lines and would light the panel `lid close` disabled.
`hyprland.lua` reads `colors.lua` with `loadfile`, not `require`, so rewriting it does not trigger
Hyprland's autoreload either (it applies at the next login or reload); an unchanged `colors.lua` is not
rewritten at all. Set `RICE_NO_RELOAD=1` to skip the live recolouring. `~/.local/bin` is only on PATH in
interactive shells, so use the full path from scripts. A grey or black wallpaper still
gets a chromatic palette from matugen (accepted). Prefer screen-sized images: an 8000x8000 PNG decodes
fully (hundreds of MB, transient).

## 10. NVIDIA / GPU

Your machine is hybrid: the AMD Cezanne iGPU (drives the display) and a GeForce RTX 3050 Ti Mobile (4 GB).

- **Default: the rail's GPU row reads the AMD iGPU** (`gpu_busy_percent`, found by vendor id). No NVIDIA
  process is ever started.
- The 3050 Ti normally sleeps: sysfs power counters measured it suspended about 98.5 % of the time
  (634,941,149 ms suspended against 9,897,830 ms active since boot). A permanent `nvidia-smi` stream
  would keep it awake all session to show a row near 0 %, so NVIDIA is opt-in.
- **To show the 3050 Ti** (util % and a VRM row), add this line next to the other `hl.env` lines in
  `dot_config/hypr/hyprland.lua` (the repo copy, then apply; an edit of only the live file would be
  overwritten by chezmoi) and log in again:

  ```lua
  hl.env("RICE_NVIDIA", "1")
  ```

  The shell then starts one long-lived `nvidia-smi` stream, only if the card reads `active` when the
  shell starts (a sleeping card is never woken), and falls back to AMD when the stream fails. It keeps
  the dGPU awake while the shell runs; the battery effect is unmeasured. Terminals opened in that session
  inherit `RICE_NVIDIA=1`, which matters if you run `tests/rig/qs-run.sh` by hand.
- Details, measurements and the behaviour table:
  [`docs/superpowers/notes/2026-10-23-nvidia-notes.md`](superpowers/notes/2026-10-23-nvidia-notes.md).
  The memory of qs on the NVIDIA GL stack was NOT measured (the card was asleep); your session's
  `__GLX_VENDOR_LIBRARY_NAME=nvidia` / `GBM_BACKEND=nvidia-drm` may or may not make qs render on NVIDIA.

## 11. Memory: the 156 MB budget is NOT met

State plainly: success criterion S1 (all of Quickshell at most 156 MB RSS, the old waybar + mako +
hyprpaper total) is **not met**. Measured in the test rig (the real AMD iGPU through Mesa radeonsi, two
1920x1080 outputs, not your live session):

| | RSS | PSS | USS |
|---|---|---|---|
| full shell, default (GL) backend | ~620 MB | ~345 MB | ~278 MB |
| bare 90x24 skeleton window alone | 418 MB | | 123 MB |
| full shell, `QT_QUICK_BACKEND=software` | | ~203 MB | ~159 MB |
| waybar + mako + hyprpaper together | 161 MB | 76 MB | 63 MB |

Why: a GL Qt Quick process maps about 264 MB of shared GL libraries before it draws anything, and each
large GL window costs about 17-18 MB private. The wallpaper layer is about +82 MB USS and the rail about
+32 MB USS. CPU at idle was about 0.3-0.5 % of one core (S2 is met in the rig), and a 10-hour run showed
no leak. The numbers on your real session may differ (real GPU path, real outputs, the NVIDIA
environment).

Your options:

1. **Restate the budget in PSS/USS** (what the process costs on top of the shared libraries). The shell is
   then about 4.5x the old trio on PSS.
2. **Run qs with the software renderer** (PSS ~203 MB, USS ~159 MB in the rig; the rig only measured
   static surfaces at under 0.5 % CPU, so the CPU cost under real animation is unmeasured). Set it for the
   shell only, by replacing the `qs-supervise` line in `dot_config/hypr/autostart.lua` with

   ```lua
   hl.exec_cmd("env QT_QUICK_BACKEND=software ~/.local/bin/qs-supervise")
   ```

   then apply and log in again. Do not use `hl.env("QT_QUICK_BACKEND", ...)`: that would put every Qt Quick
   app you start on the software renderer. (The variable was measured in the rig; this exact autostart
   line was not run.)
3. **Accept the cost.**
4. **The fallback from the spec: keep waybar and mako, use Quickshell only for the carousel and launcher.**
   Add these lines back to the `hyprland.start` handler in `dot_config/hypr/autostart.lua`:

   ```lua
   hl.exec_cmd("waybar")
   hl.exec_cmd("mako")
   hl.exec_cmd("sleep 1 && hyprpaper")   -- only with option 5 or if you keep hyprpaper's wallpaper
   ```

   and in `dot_config/quickshell/shell.qml` remove the `Bar` and `Rail` `Variants` blocks and `Toasts {}`
   (and the `Wallpaper` block if hyprpaper keeps the wallpaper), keeping `Launcher {}` and `Carousel {}`.
   That shell.qml cut is an edit you make; there is no switch for it and it was not tested. mako and the
   shell's `Toasts {}` must not both run (only one program can own the notification name). The carousel's
   live wallpaper preview needs the `Wallpaper` layer, so with hyprpaper it does not preview live.
5. **Keep hyprpaper for the wallpaper** (saves about 82 MB USS): drop the `Wallpaper` block from
   `shell.qml` and restore `hl.exec_cmd("sleep 1 && hyprpaper")` in autostart. Same carousel caveat.

Measure on your machine first (section 5, item 13), then decide.

<!-- KNOWN-ISSUES:BEGIN -->
## 12. Known issues and pending items

Tags: `scheduled for fix` = in the controller's final fix wave; `accepted/known` = a decision or a
trade-off, not planned to change. The controller revises this block after the fix wave.

- **A timed-out carousel apply. [accepted/known]** After `✗ apply timed out` the strip stays visible
  without the keyboard (close it with `Ctrl+Alt+W`); the apply process is never killed, and if it
  finishes later its files still recolour the shell. While that late apply is still running, Enter in a
  reopened carousel does nothing.
- **Glitch effect dropped. [accepted/known]** The workspace-switch glitch was evaluated and dropped: idle
  CPU and frame timing were fine, but about +45 MB of memory stayed retained after it had played (562 to
  ~611 MB with it, 550 to ~555 MB without). The glitch toggle on the render page is a mock only. See
  `docs/superpowers/notes/2026-10-23-glitch-spike.md`.
- **The interim waybar edit stays in the repo. [accepted/known]** `dot_config/waybar/config.jsonc` has
  `persistent-workspaces` per output (`DP-1` 1-5, `eDP-1` 11-15) and the hard-coded `wlan0` interface line
  removed, so waybar matches the pools while it is retired but kept. With `all-outputs: true` both bars
  still show both pools. Delete it together with waybar (section 14).
- **Direct scanout. [accepted/known]** The rail ignores exclusive zones and a 1 px invisible overlay
  surface reserves its width. A surface over a fullscreen window can prevent direct scanout (fullscreen
  game/video on the main screen); not measured.
- **Bare mouse side buttons no longer act as browser back/forward. [accepted/known]** They step
  workspaces, as on the Mac (spec-intended).
- **Workspace 11 is also a default workspace on the laptop panel. [accepted/known]** An addition beyond
  the old rules so the panel starts inside its own pool (otherwise Hyprland opens a free id such as 6 there).
- **The launcher and toasts ran on a private D-Bus only in the rig. [accepted/known]** The rig runs qs on a
  private session bus so it cannot touch your notification daemon, PipeWire, BlueZ or MPRIS. On your
  machine qs uses your real session bus; that path (taking `org.freedesktop.Notifications` once mako is
  gone, real notifications, real media players) is unverified.
- **The memory budget is not met.** Section 11. Owner decision pending.
- **NET shows the default-route interface name** (read from `/proc/net/route`), not an SSID. NetworkManager
  is not running on this machine (iwd + systemd-networkd), so nmcli is not used. **[accepted/known]**
- **xremap fails silently without permissions.** Section 3. It runs with `--watch=device` (re-grabs keyboards that reappear); that re-grab is untested on real devices. **[accepted/known]**
- **Carousel first open retains about +60 MB RSS** in the rig, then plateaus (no leak seen); worth
  checking on your machine. **[accepted/known]**
- **`lid close` under the hyprlang rollback config may silently do nothing. [accepted/known]** In one rig
  session on a minimal hyprlang config, after an interrupted test left the panel disabled and a reload
  re-enabled it, `hyprctl keyword monitor "eDP-1, disable"` kept answering `ok` without disabling the output
  (the same command your pre-port script used). Fresh instances passed every time (3 runs in a row). It only
  matters after a rollback; `hyprctl monitors` tells you whether the panel really went away.
- **Any Hyprland config reload re-lights a closed lid's panel. [accepted/known]** With the lid closed
  (`lid close` disabled eDP-1), anything that reloads the config turns the dark panel on again and
  moves workspaces 11-15 back to it: Hyprland's autoreload after a `chezmoi apply` that changes
  `hyprland.lua`, `binds.lua`, `autostart.lua` or `lib/pools.lua`, a hand edit of one of them, or
  `hyprctl reload`. The reload re-applies the `hl.monitor` line for eDP-1 (the same happened under
  hyprlang). A palette apply is NOT such a reload (section 9). Workaround: run `~/.local/bin/lid close`
  again afterwards. A lid-aware monitor line would be a later improvement.
- **No system tray host. [accepted/known]** blueman-applet and librepods icons are not shown; keep waybar's
  tray or ask for a Quickshell tray widget. The VOL chip is read-only; the XF86Audio keys change the volume.
- **mako can take the notification name before the shell. [accepted/known; mitigation unverified]** mako's
  D-Bus activation file claims `org.freedesktop.Notifications`; a notification sent before qs registers
  activates mako and the shell's toasts never appear for that session. Mitigation: `systemctl --user mask
  mako.service` before the first login (section 4), check with `busctl --user status
  org.freedesktop.Notifications` (section 5, item 9). That masking blocks the activation under dbus-broker
  was not tested (nothing was changed on your session).
<!-- KNOWN-ISSUES:END -->

## 13. Rollback

Back to waybar + wofi + mako + hyprpaper and the old `hyprland.conf`. Use a TTY (`Ctrl+Alt+F3`) if the
session is unusable. Backups are `<file>.bak.<stamp>` next to the originals (section 4).

**Prerequisite (before you merge or apply this branch): the live-config sync PR.** On `main`,
`dot_config/hypr/hyprland.conf` is an old stub: no lid or headless binds, no BenQ `desc:` monitor line,
no `XDG_MENU_PREFIX`, no movewindow binds. Only commit 88a1c01 on this branch synced your live file into
the repo. That commit is also offered on its own as a small PR titled **"chore: sync live
hypr/hyprpaper/waybar configs into the repo"**: merge that PR into `main` FIRST. Then `main`'s
`hyprland.conf` (and `hyprpaper.conf`, waybar `config.jsonc`) are your real configs, and going back to
`main` is a safe rollback.

**Step 0: switch the chezmoi source back first**, or the next routine `chezmoi apply` brings
`hyprland.lua` and everything else back.

- **If the prerequisite PR was merged into `main`:** while the source is still on the feature branch,

  ```sh
  git -C ~/.local/share/chezmoi switch main      # the feature branch is feat/quickshell-terminal-desktop
  ```

  If you already merged the feature branch into main, revert that merge in the repo instead.
- **If the prerequisite PR was NOT merged:** do NOT switch to `main` (or to any branch whose
  `hyprland.conf` is the stale stub): your next `chezmoi apply` would overwrite the restored live
  `hyprland.conf` with it, silently dropping the lid/headless binds and the BenQ line. Stay on the feature
  branch and take only the Lua entry point out of the source, committed locally:

  ```sh
  git -C ~/.local/share/chezmoi rm dot_config/hypr/hyprland.lua
  git -C ~/.local/share/chezmoi commit -m "rollback: back to hyprland.conf"
  ```

  (chezmoi does not delete `~/.config/hypr/hyprland.lua` itself; step 2 below moves it away.) The
  feature branch's `hyprland.conf` is the synced live copy, so `chezmoi apply` keeps it correct.

Only then do the steps below.

```sh
# 1. stop the new pieces (the supervisor first, or it restarts qs)
pkill -f qs-supervise; pkill -x qs
pkill -x xremap

# 2. take the Lua config out of the way: Hyprland then falls back to hyprland.conf
mv ~/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua.disabled

# 3. make sure hyprland.conf is the pre-migration one. After step 0 the source's copy is your live file as
#    synced on 2026-10-23 (prerequisite PR on main, or the feature branch), so chezmoi keeps it; restore the
#    backup anyway if you edited the live file after that date, or if in doubt
ls ~/.config/hypr/hyprland.conf.bak.*
cp -a ~/.config/hypr/hyprland.conf.bak.<stamp> ~/.config/hypr/hyprland.conf

# 4. restore the other backed-up files if you changed them
cp -a ~/.config/waybar/config.jsonc.bak.<stamp> ~/.config/waybar/config.jsonc
cp -a ~/.config/hypr/hyprpaper.conf.bak.<stamp> ~/.config/hypr/hyprpaper.conf

# 5. let mako be D-Bus activated again (section 4 masked it)
systemctl --user unmask mako.service

# 6. log out of Hyprland and log in again. Falling back to hyprland.conf starts the old programs
#    through its exec-once lines. (From a TTY, hyprctl and waybar need HYPRLAND_INSTANCE_SIGNATURE and
#    WAYLAND_DISPLAY and will not work; and whether a plain `hyprctl reload` inside the running session
#    drops the Lua config is untested, so log out and in.)
```

`hyprland.conf` still contains the `exec-once` lines for `mako`, `waybar`, `blueman-applet`, `librepods`,
`airpods-autoconnect` and `sleep 1 && hyprpaper`, and its `wofi --show drun` bind on `Super+Space`, so
falling back to it re-enables all of them. If you instead stay on the Lua config and only want the old
programs back, follow section 11 option 4 (restore the autostart lines, stop `Toasts {}`), and bind wofi
(`hl.bind("SUPER + space", hl.dsp.exec_cmd("wofi --show drun"))`) in place of the launcher bind. To stop
xremap permanently, remove its `hl.exec_cmd` line from `autostart.lua` (or delete
`~/.config/xremap/config.yml`). The kitty files (`~/.config/kitty/kitty.conf`, `colors.conf`) did not
exist before; delete them to return to kitty's defaults.

## 14. Cleanup after living with it

Only after you are sure you will not roll back. In the repo (chezmoi does not delete files it no longer
manages, so also remove the live copies):

- `dot_config/waybar/` (including the interim persistent-workspaces edit): the whole directory.
- `dot_config/wofi/`: the whole directory.
- `dot_config/hypr/hyprpaper.conf`.
- `dot_config/hypr/hyprland.conf` (this is your rollback copy: delete it last).
- the live copies: `~/.config/waybar`, `~/.config/wofi`, `~/.config/hypr/hyprpaper.conf`,
  `~/.config/hypr/hyprland.conf`, and the `*.bak.*` backups once you no longer need them.
- optionally uninstall: `sudo pacman -Rns waybar wofi mako hyprpaper` (check first that nothing else needs them).
- your Claude memory note about "9 shared workspaces" is obsolete: the workspace model is now two pools
  of five (1-5 on the BenQ, 11-15 on the panel).

## 15. Every ruling made during the build

Copied verbatim, in order, from the build ledger (`docs/superpowers/notes/2026-10-23-sdd-ledger.md`).
While you were away every decision that would normally have been a question to you was made as a
"Ruling:", with its reasoning and (where recorded) the cost if it was wrong. Read the list and rework
whatever you disagree with. Where a line records no cost, none was recorded. `L<n>` is the ledger line.

1. (L17) Ruling: No live-system changes. No `chezmoi apply` into $HOME, no writes under ~/.config, no session restart, no sudo/pacman/yay, no edit of ~/.claude/settings.json, no deletion of retired configs (waybar/wofi/hyprpaper/hyprland.conf stay). — The owner said not to stop, not that destructive/security-sensitive actions are pre-approved; they are also impossible (no sudo) or would risk the owner's session and this job. — Cost if wrong: owner runs a short deploy checklist (written in docs) instead of finding it deployed.
2. (L18) Ruling: Plan steps that are ask-first gates (Task 0 step 4, Task 3 step 5, Task 6 step 3, Task 13 step 2, Task 20, Task 24 step 4) are NOT executed; each is rewritten as an item in `docs/deploy.md` (owner follow-ups) and in the PR description. — see above. — Cost: none beyond owner effort.
3. (L19) Ruling: Runtime verification uses a private test rig, not the live session: binaries extracted to ~/.cache/rice-testbin (outside the repo), a HEADLESS nested Hyprland (AQ_BACKENDS=headless, own instance signature, virtual outputs) and Quickshell run against it, driven with wtype and hyprctl -i, screenshots with grim. Rig scripts live in the repo under tests/rig/ and must refuse to run against the live instance signature. — gives real screenshots and bind tests without disturbing the desktop. — Cost: if headless nested Hyprland cannot work, runtime checks are reported UNVERIFIED instead.
4. (L20) Ruling: Anything that cannot be exercised in the rig (physical mouse side buttons, xremap against real devices, lid switch on the live session, AirPods battery, Claude Code status line in a real session) is reported UNVERIFIED in the PR with exactly what was and was not run. Mouse codes default to 275/276 (plan's expectation).
5. (L21) Ruling: Ask-first gates in the plan's Review Focus tests stay as tests but run in the rig (dock unplug = `hyprctl output remove` on a headless output, not the owner's real monitor).
6. (L22) Ruling: Task 4's `tests/tools/uinput_keys.py` also exposes a CLI (`python3 uinput_keys.py KEY KEY ...` calls press(*argv[1:])) because tests/hypr/check_pools.sh calls it that way (the plan's Interfaces block only named press()). In the rig, key injection uses wtype against the nested compositor; uinput_keys.py is kept for the live-session case and for owner use.
7. (L23) Ruling: check_pools.sh and other hyprctl-using tests take the target instance from HYPRLAND_INSTANCE_SIGNATURE set by tests/rig/rig_env.sh and abort if it equals the live signature recorded at rig setup.
8. (L24) Ruling: Dispatch order is strictly sequential per the skill (shared files hyprland.lua, shell.qml, Rail.qml). Work packages (units) group plan tasks that share a review surface. Models: opus for rig/integration/QML work, sonnet for pure-logic Python/Lua and docs, reviewers sonnet (opus for QML-heavy diffs), final review fable.
9. (L25) Ruling: Task 22 (glitch) runs as a time-boxed spike only if the rig can run Quickshell with ScreencopyView; go/no-go recorded; default OFF either way.
10. (L26) Ruling: `git push` of the feature branch and opening a DRAFT PR against main are explicitly requested by the owner; nothing is pushed to main, nothing merged.
11. (L36) Ruling: run in nested rig  (cell of the pre-flight table, task T4 steps 6-8)
12. (L55) Ruling: live ~/.config hypr/hyprpaper/waybar configs were ahead of the repo (3 files differ: hyprland.conf, hyprpaper.conf, waybar config.jsonc). Synced live -> repo in commit 88a1c01 BEFORE any port work. — a chezmoi apply from the old repo copy would have reverted the lid/headless binds, BenQ desc match, movewindow, app binds. — Cost if wrong: one extra commit to revert; the owner's live files are untouched (copy was live -> repo only).
13. (L56) Ruling: later units must port from the live-synced repo files (now in dot_config/hypr/hyprland.conf), not the plan's description of the old stub. Notably: lid/headless binds, `desc:BNQ BenQ EX2510S K8M02386019` monitor, `XDG_MENU_PREFIX`, `Super+Tab focusmonitor`, app binds `Super+E` -> `kitty -e yazi`, `Super+Space` wofi (to be replaced).
14. (L57) Ruling: rig shares live D-Bus/PipeWire/BlueZ. Units that start a NotificationServer or touch audio/Bluetooth state must use a private session bus (`dbus-run-session`) in the rig and must not stop mako or any live process. U10 (toasts) gets this in its brief.
15. (L66) Ruling: Super+Space -> qs ipc before the launcher exists is accepted; nothing is deployed until the owner applies the whole branch (docs/deploy.md will say apply all phases together).
16. (L68) Ruling: Super+` is replaced by `SUPER + code:49` (physical key under Esc) — the spec's intent is "the key under Esc", not the grave keysym; pt layout produces no grave keysym there. Docs reworded repo-wide in the fix round. — Cost if wrong: if code:49 is not the key under Esc on the owner's keyboard, one number to change (checkable with wev).
17. (L83) Ruling: grey/black wallpaper getting a chromatic palette from real matugen is accepted (palette valid, contrast floors met; the fallback still protects against a hue-less primary). — Cost if wrong: a grey wallpaper looks blue/orange instead of cyan/magenta; one-line change later (force fallback when the image itself is near-grey).
18. (L85) Ruling: implement real rollback (snapshot targets before replace; restore/delete on failure) rather than a comment — the brief says no output file may change on ANY failure. — Cost if wrong: a little extra code.
19. (L99) Rulings: NET = default-route interface from /proc/net/route read on the shared 2 s timer (no nmcli, no second timer, no Process); BAT on every screen when a battery exists; slots resolved within the active workspace's pool first, ids outside 1..5 slot range never shown; date order `ddd MMM dd` accepted (render is the visual authority); rig RSS investigation goes to U9. — Costs if wrong: small QML edits.
20. (L107) Ruling: do NOT stop or redesign unattended; continue building as specified. The PR records the measurements and the owner's options: (1) restate S1 in PSS/USS, (2) run qs with QT_QUICK_BACKEND=software (documented one-liner for autostart), (3) accept the cost, (4) the spec's fallback (keep waybar+mako; Quickshell only for carousel+launcher), (5) keep hyprpaper for the wallpaper (saves ~82 MB USS). Real-session env (`__GLX_VENDOR_LIBRARY_NAME=nvidia`, `GBM_BACKEND=nvidia-drm` set by hyprland.lua) will make qs use NVIDIA, so real numbers may differ; also qs loads NVIDIA EGL libs (whether that wakes the dGPU is unverified). — Cost if wrong: the owner may prefer the fallback; everything else is reusable.
21. (L110) Rulings: (a) add preview(path)/clearPreview() to WallpaperState (mirrors Theme; no file writes; effective path preview||filePath||defaultPath; followers load previews too; retainWhileLoading if supported) because U11 depends on it; (b) rail date format `ddd MMM dd yyyy` accepted (render authority); (c) rail 1px overlay zone surface accepted, add a comment about direct-scanout trade-off; (d) one-liners: net-history test accepts n_a==24, MediaWidget prefers first isPlaying player + NaN guard. Not in scope: cache:true/duplicate decodes, MALLOC_ARENA_MAX, bar-height constant, rail text size.
22. (L120) Ruling: the U10 fix round is QUEUED until U11 finishes (both touch tests/rig/selftest-qs.sh; avoid concurrent edits/commits of the same file). Then resume the U10 implementer (a22eaad9342c93f76) with the Important finding only; FIX_BASE = ecede93 and the review range will use explicit commits to exclude U11's.
23. (L127) Ruling: include in the FINAL fix wave (one dispatch: let Escape close during an apply and/or add a ~10 s timeout)  (embedded in the U11 minors line)
24. (L129) Ruling: the earlier "never nvidia-smi" rule assumed it would wake a sleeping dGPU; on this machine the session already runs with the NVIDIA stack and the card is active. New unit U15 (queued after U12; rig is single-user): (a) measure qs memory (RSS/PSS/USS) with the NVIDIA GL stack in the rig (the stack the real session uses: __GLX_VENDOR_LIBRARY_NAME=nvidia, GBM_BACKEND=nvidia-drm, NVIDIA EGL vendor) vs the AMD numbers, flag the NVIDIA wake/power implications; (b) the rail GPU row prefers the NVIDIA dGPU: util % + VRAM via ONE long-lived `nvidia-smi -l 2 --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits` Process, started ONLY if runtime_status is `active` at startup (never wake a sleeping dGPU), restarted with back-off if it dies, falling back to the AMD iGPU sysfs source when the card is not active / nvidia-smi is missing / the stream fails; tests with a fake nvidia-smi script on PATH and fixtures (no real nvidia-smi in tests); VRAM shown as an extra `VRM` bar row. The 4 GB VRAM is not the constraint on the 156 MB budget (that is system RAM).
25. (L140) RULING (overturns the earlier "dGPU is active" ruling): a permanent nvidia-smi stream would keep the dGPU awake all session for a ~0% row, so the NVIDIA source becomes OPT-IN (`RICE_NVIDIA=1` via hl.env), default = AMD iGPU (the chip that drives the display). Sent to the U15 implementer before its review. — Cost if wrong: the owner adds one env line to show the 3050 Ti.
26. (L146) Ruling: the U15 fix round is QUEUED until U13 (glitch spike) finishes (rig exclusivity; both touch tests/rig/selftest-qs.sh). Then resume the U15 implementer (a4d1e5f28ec4fa923) with the two Important findings + cheap minors (set nvStatusPath only when nvAllowed so the docs sentence is true; docs: TOCTOU line, setpriv-missing warning text, note measured vs unmeasured claims). FIX_BASE = U13's final head.
27. (L149) Ruling: glitch is DROPPED; the DOM glitch in the render stays a mock only; the notes record the cost source and mitigations to try later.  (embedded in the U13 completion line)

## 16. Everything that was not verified (consolidated)

Nothing below was observed on your machine. "Rig" means the headless nested Hyprland test rig.

**Input and compositor**
- The physical mouse side buttons (275/276 are only registered; the step logic is tested through `hyprctl eval`).
- The key under Esc being `code:49` on your keyboard with Super (the rig sends keycode 49 through a virtual keyboard).
- Lid switch firing and the XF86Launch2 key (registered only); the exec binds (launchers, `qs ipc`, exit, Print) were registered and read back but not fired. The `lid` and `headless` scripts themselves WERE run against the rig, under the Lua config and a minimal hyprlang config (`tests/hypr/lid_headless.sh`; `headless` with a fake `sudo`, so the real `headless-peripherals` never ran): eDP-1 disabled and restored, dpms off/on on every output. Not verified: real USB power cuts, real displays going dark, the rollback `hyprland.conf` itself (a stand-in config was used; in one rig session the hyprlang `keyword monitor` answered `ok` without disabling the output, see section 12).
- BenQ matching by `desc:` (headless outputs have no description): pool 0, the workspace 1-5 rules, the ws 1 default, the `desc:BNQ ...` monitor line at 144 Hz, and `Screens.isMain`; whether `eDP-1` accepts 1920x1080@144.
- A real monitor unplug migrating workspaces; BAT on the undocked laptop; the nil-monitor path (lid closed with no external screen) inside a real Hyprland.
- `tests/tools/uinput_keys.py press()` was never run (it would reach the live session).
- The `env` lines on a real NVIDIA session; the session restart and cutover itself.

**xremap and kitty**
- xremap runtime remapping against real devices; its permissions (input/uinput) and autostart on PATH.
- Firefox, VS Code, JetBrains and Electron acceptance of the translated keys and their window classes (only kitty's class was verified).
- kitty copy/paste, tabs and `Ctrl+C` SIGINT on real windows (parser-level config validation only); `autostart.lua` was only loaded for syntax.

**Shell**
- Everything on your real screens: scaling, 144 Hz, real GPU rendering, the rail font size against the render.
- Taking `org.freedesktop.Notifications` on the live bus once mako is gone; real application notifications; launching real apps from the launcher (only fake `.desktop` entries were executed); a physical keyboard into the launcher (the rig needed a held virtual keyboard); the `Super+Space` bind end to end; the `Ctrl+Alt+W` bind opening the carousel.
- Kitty `SIGUSR1` after `rice-palette apply` (stubbed in every test); the border recolouring through `hyprctl eval` ran only against the nested rig (`tests/hypr/palette_lid.sh`), not your session; the generated btop theme in btop on your real terminal (btop 1.4.7 was run in a pseudo-terminal with a temp HOME: `color_theme = "rice"` picks up a `rice.theme` rendered from the seed palette, and with the file missing btop starts on its built-in colours); the chezmoi-deployed layout of `~/.local/bin` finding `~/.local/share/rice`.
- Your actual wallpapers (JPEG/WebP size parsing is covered by fixtures only), the carousel under rapid scrolling, the startup wallpaper race (guarded but never reproduced).
- Media players other than the one the rig could read; the rail with a 15 % battery row; real PipeWire volume changes; clicking a bar cell with a real pointer.
- Real connected Bluetooth devices and their battery values (none were connected during the build); whether BlueZ reports a single AirPods level at all.
- The carousel on your session: it runs `$HOME/.local/bin/rice-palette` by absolute path; the rig ran it with no `~/.local/bin` on PATH, which is what your session's PATH looks like (read from the live Hyprland process).
- A real Claude Code session feeding the cache, and whether your plan reports `rate_limits`; the 30 s missing-file re-read of the Claude cache via the timer path (seen working once by hand).
- Whether the glvnd NVIDIA EGL probe in qs wakes the dGPU.
- Real `nvidia-smi` streaming (format, locale, first line within 6 s, death under `pdeathsig`), real VRAM numbers, the power/battery effect of the stream, that the card is `active` at login, hot reload while the stream runs; qs memory on the NVIDIA GL stack.
- The idle RSS/CPU/PSS on the live session (the section 11 numbers are rig numbers).
- Stacking with waybar during a transition (the rig has no waybar).

**Process**
- Nothing was applied to `$HOME`: `chezmoi apply`, the `statusLine` entry, package installs and the session restart are all yours.
