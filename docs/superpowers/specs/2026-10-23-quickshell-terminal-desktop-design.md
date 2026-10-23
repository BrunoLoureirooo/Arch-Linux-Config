# Quickshell Terminal Desktop: Design Spec

Date: 2026-10-23
Status: draft for review
Visual reference (approved look, private link): https://claude.ai/artifact/SGHt9bagiiej1rGiD5byXP

## 1. Purpose

Replace the current waybar + wofi + mako + hyprpaper desktop on the Victus laptop (Arch, Hyprland 0.56.2) with one Quickshell shell that looks like a cyberpunk terminal and stays light. At the same time, make the keyboard and workspaces behave like the owner's Macs, so muscle memory carries across machines.

What the owner asked for, in their words:

- "migrate to quickshell", with a wallpaper and theme carousel.
- "terminal lightweight distro ... meant to look like a terminal ... match with performance", "cyber punk terminal inspired vibe".
- Mac-like keys: Super is Command, Alt is Option, Control stays Control; "i need the command c to be copy".
- "one pool per screen. like in the mac" for workspaces, and the mouse side buttons switch workspaces as on the Mac.
- A right-hand metrics sidebar with Bluetooth devices and Claude usage limits, no calendar.
- A workspace-switch glitch effect, over the windows, if it can be done cheaply.

### Success criteria

Each is measured, not assumed.

| # | Criterion | How it is measured |
|---|---|---|
| S1 | Quickshell, all of it, uses at most 156 MB RSS at idle (today waybar 79 + mako 24 + hyprpaper 53 = 156 MB, measured 2026-10-23) | `ps -o rss,comm` after 60 s idle on both screens |
| S2 | Idle CPU of the shell averages under 2% of one core over 60 s | `ps -o pcpu` sampled, or `top -b` |
| S3 | Switching a workspace on one screen never changes the other screen | `hyprctl monitors -j` before and after |
| S4 | Super+C/V/X/A/Z/F/S/L/T/W/N/R behave as Ctrl+key in GUI apps, and as the terminal's own copy/paste/tab/window in kitty, while Ctrl+C in kitty still interrupts | manual matrix in the plan, plus `wev` |
| S5 | No Hyprland bind equals any key combination the remapper outputs | automated test over the two config files |
| S6 | The two mouse side buttons step the workspace on the focused screen | manual, after the button codes are read with `wev` |
| S7 | Lid-close and headless behaviour is unchanged | the existing uinput method, safe event only |
| S8 | The shell survives a crash: bar back within 3 s, window-manager binds unaffected | kill the process, time the recovery |

## 2. Non-goals

- No blur, shadows, rounded corners, or easing animations anywhere. The glitch is the single exception (section 8) and is optional.
- No always-running shaders, GIF assets, audio visualizers, minimap, market feed, or sound effects.
- No lock screen or login theme, no window titlebar patches.
- No theming of nvim, GTK or Qt. kitty, btop and the shell follow the palette; nothing else.
- No change to lid, headless, logind or monitor-topology behaviour. They are ported to the Lua config verbatim.
- No per-screen wallpaper picker. Both screens show the same wallpaper (the shell draws one layer per screen, so this can change later without redesign).
- No volume or brightness on-screen display (the render has none).

## 3. Verified facts and constraints

Checked on this machine on 2026-10-23 unless a source is named.

- Hyprland 0.56.2, built from tag v0.56.2. It ships a Lua config API: `/usr/share/hypr/hyprland.lua` (example) and `/usr/share/hypr/stubs/hl.meta.lua` (types). The current `hyprland.conf` begins with a "this is a STUB" notice.
- Lua API used by this design: `hl.config`, `hl.bind(keys, dispatcher|function, opts)`, `hl.dispatch`, `hl.dsp.focus({workspace})`, `hl.dsp.window.move({workspace})`, `hl.dsp.window.cycle_next`, `hl.dsp.exec_cmd`, `hl.get_active_monitor()`, `hl.monitor`, `hl.workspace_rule`, `hl.on("hyprland.start", fn)`, `hl.env`, `hl.exec_cmd`. `HL.Monitor` has `id`, `name`, `description`, `active_workspace`.
- Monitors: `DP-1` is the BenQ, description `BNQ BenQ EX2510S K8M02386019`, Hyprland id 2, at 0,0. `eDP-1` is the built-in panel, id 0, at 1920,0. Monitor ids are not in screen order, so nothing may derive a workspace range from `monitor.id` arithmetic.
- Quickshell 0.3.1 is in the official `extra` repo (not installed yet). Modules used: `Quickshell`, `Quickshell.Io` (`FileView`, `Process`, `IpcHandler`), `Quickshell.Hyprland`, `Quickshell.Wayland` (`WlrLayershell`, `ScreencopyView`), `Quickshell.Services.Notifications` (`NotificationServer`), `Quickshell.Services.Mpris`, `Quickshell.Services.Pipewire`, `Quickshell.Bluetooth` (`Bluetooth.devices`, `BluetoothDevice.connected/battery/batteryAvailable/name`), `DesktopEntries`.
- matugen 4.2.0 is in `extra`. The documentation reachable here describes an older template syntax, so this design does not use matugen templates. matugen is used only to extract colours as JSON.
- xremap is not in the official repos. `xremap-hypr-bin` 0.15.15 is in the AUR (last modified 2026-10-21). Its `application` filter takes `only`/`not` and matches window class; `xremap --list-windows` prints the names.
- `jq` is not installed. Python 3.14, Lua 5.5 and LuaJIT are installed, so tests use `python3 -m unittest` and `lua`.
- `qt6-shadertools` 6.11.2 is installed (provides `qsb`, at `/usr/lib/qt6/bin/qsb`).
- Hybrid graphics: NVIDIA RTX 3050 Ti (`/sys/class/drm/card1`, vendor 0x10de) and AMD iGPU (`card2`, vendor 0x1002, exposes `gpu_busy_percent`). Card numbers are not guaranteed stable. GPU stats come from the AMD sysfs file located by vendor id, never from `nvidia-smi`, so the shell never wakes the NVIDIA chip.
- Input: Logitech G502 Hero. The expected side-button codes are `mouse:275` and `mouse:276`, to be confirmed with `wev`. Keyboard layout is `pt`.
- Claude Code status line (official docs): `settings.json` takes `"statusLine": {"type": "command", "command": "...", "padding": N, "refreshInterval": N}`. The command receives JSON on stdin after events, debounced at 300 ms. `rate_limits.five_hour` and `rate_limits.seven_day` each carry `used_percentage` (0 to 100) and `resets_at` (Unix seconds). They appear only for Pro and Max plans, only after the session's first API response, and each window may be absent. Configuring a status line makes Claude Code hide most of its footer keyboard hints. An open upstream issue (anthropics/claude-code #45133) reports `rate_limits` missing on some setups.
- The owner has no `statusLine` configured today (`~/.claude/settings.json` has none).
- The dotfiles repo is chezmoi source at `~/.local/share/chezmoi` (remote `BrunoLoureirooo/Arch-Linux-Config`, branch `main`). It has no `.chezmoiignore`, so any `docs/` or `tests/` directory would be copied into the home directory on `chezmoi apply`. This design adds the ignore file.

## 4. Decisions that change earlier statements

These supersede what the render page or older notes said.

1. **Per-screen workspaces are hand-rolled in Lua, with no plugin.** The render named the `hyprsplit` library. The Lua API makes it unnecessary: about 40 lines, no third-party code to break on a Hyprland update.
2. **This replaces the September 2026 decision to keep 9 shared workspaces.** The owner has asked for independent pools per screen. It is not the paired-and-flipped scheme they rejected then: each screen keeps its own five and switching one never moves the other. The memory note `hyprland-workspace-model` must be rewritten when this ships.
3. **The key scheme is changed to avoid a collision.** The remapper emits `Ctrl+←/→` for word jump; a Hyprland bind on the same combination would fire on that output. Workspace stepping therefore moves to `Ctrl+Alt+←/→`, and window focus to `Super+Alt+←↑↓→`. The render page must be corrected to match (section 6).
4. **Alt+arrows are translated, not left alone.** On Linux, Alt+← is "back" in browsers, so Option-style word jump needs Alt+←/→/⌫ turned into Ctrl+←/→/⌫ in GUI apps. Terminals handle Alt natively.
5. **The volume/brightness on-screen display is dropped** from the stack description; the render never showed one.

## 5. Architecture

Six units, each with one job and a plain interface between them.

```
 keyboard/mouse
      |
  xremap (evdev level, per-app)  -- Super/Alt combos -> Ctrl combos, GUI apps only
      |
  Hyprland (Lua config)          -- window-manager binds, per-screen workspace pools
      |                \
  kitty (own Super maps)   Quickshell (one process, one QML tree)
                            |-- Wallpaper layer (Background, one per screen)
                            |-- Bar (top, one per screen)
                            |-- Rail (right, main screen only)
                            |-- Launcher, Carousel, Toasts (overlay layer, on demand)
                            |-- Glitch overlay (optional, section 8)
  rice-palette (CLI) --writes--> colors.json / kitty colors / hypr colors.lua
  claude-limits-statusline (CLI, run by Claude Code) --writes--> ~/.cache/claude-limits.json
```

### 5.1 Hyprland Lua config (`~/.config/hypr/`)

Files:

- `hyprland.lua`: monitors, env, look (animations off, 1px gradient border from the palette), autostart via `hl.on("hyprland.start")`, input (`pt`), lid and headless binds ported verbatim, then `require` of the two modules below.
- `binds.lua`: every bind, built from the tables in section 6.
- Autostart (kept from today): `blueman-applet`, `~/.local/bin/librepods --start-minimized`, `~/.local/bin/airpods-autoconnect`. Added: `qs-supervise` and `xremap`. Removed at their cutover phases: `waybar`, `hyprpaper`, `mako`.
- `lib/pools.lua`: pure functions, no `hl` calls, so they run under plain `lua`.
- `colors.lua`: generated palette (border colours). Created once by chezmoi, then owned by `rice-palette`.

`lib/pools.lua` interface:

- `ws_id(pool, slot) -> integer` is `pool * 10 + slot`, with slot 1 to 5. Pool 0 is workspaces 1 to 5, pool 1 is 11 to 15.
- `pool_for(mon, assigned) -> integer`, where `mon` is `{name, description}`. The BenQ (description `BNQ BenQ EX2510S K8M02386019`) is pool 0, `eDP-1` is pool 1, and any other monitor takes the next unused pool and keeps it for the session. `assigned` is the session table that remembers it.
- `slot_of(workspace_id, pool) -> integer`: the slot (1 to 5) of a workspace id within that pool, or 1 if the id belongs to another pool (this happens after a monitor was unplugged and its workspaces moved).
- `step(slot, delta) -> integer`: slot plus delta, clamped to 1..5. Stepping does not wrap, as in macOS Spaces.

Behaviour: `Ctrl+1..5` focuses `ws_id(pool_for(active monitor), n)`. `Ctrl+Shift+1..5` moves the active window to that id. `Ctrl+Alt+←/→` and the two mouse side buttons step within the active monitor's pool. Each id is pinned to its monitor with `hl.workspace_rule({workspace, monitor, persistent = true})`, and workspace 1 keeps `default = true` on the BenQ so startup lands there. Unplugging a monitor lets Hyprland move its workspaces onto the remaining one; replugging returns them. No window is lost.

### 5.2 Remapper (xremap, `~/.config/xremap/config.yml`)

All entries are `keymap` rules with `exact_match: true`, so `Super-c` never fires for `Super-Alt-c`. Two rule groups:

- Group A, `application: not: [kitty]` (the exact class is confirmed with `xremap --list-windows`): the combinations in section 6, mapped to their Ctrl-based outputs.
- No group for kitty: Super combinations pass through, and kitty's own `map super+c copy_to_clipboard` family (in `kitty.conf`) handles them. Ctrl combinations stay raw there.

Started from `hl.on("hyprland.start")` with `xremap ~/.config/xremap/config.yml`. It needs read access to `/dev/input/event*` and write access to `/dev/uinput`. `/dev/uinput` is already user-writable here (file ACL). The user is not in the `input` group (groups are `users docker wheel`), so the plan adds either the group or a udev rule, and asks before doing either.

### 5.3 Quickshell (`~/.config/quickshell/`)

One process, started by `qs-supervise` (a loop that restarts it within 2 s if it exits). Layout:

- `shell.qml`: root. Instantiates the pieces below with `Variants` over `Quickshell.screens`.
- `Theme.qml` (singleton): the eight palette tokens, read from `colors.json` with a watching `FileView`, plus fonts and sizes. Every colour in the shell comes from here.
- `services/Stats.qml` (singleton): CPU from `/proc/stat`, memory from `/proc/meminfo`, AMD GPU from the vendor-matched sysfs file. One 2 s timer, shared.
- `bar/Bar.qml`, `bar/Workspaces.qml`, `bar/Chip.qml`, `bar/Meter.qml`: top bar on every screen. `Workspaces` shows the workspaces Hyprland reports on its own screen (ids 1 to 5 or 11 to 15; slot is `((id - 1) mod 10) + 1`), active slot filled, occupied slots underlined. It reads Hyprland's own data, so the pool assignment lives only in `lib/pools.lua`.
- `rail/Rail.qml` plus one file per widget (`ClockWidget`, `SysWidget`, `MediaWidget`, `BluetoothWidget`, `ClaudeWidget`): right-hand panel with cut corners, on the main screen only (the screen whose description starts with `BNQ BenQ`, else the first screen).
- `wallpaper/Wallpaper.qml`: `PanelWindow` on `WlrLayershell.layer: Background`, one per screen, showing the chosen image.
- `wallpaper/Carousel.qml`: overlay with the cut-corner strip, left/right to select, Enter to apply, Escape to cancel. Shows live as you scroll; Escape reverts.
- `launcher/Launcher.qml`: overlay over `DesktopEntries`, substring match, up/down, Enter to run, Escape to close.
- `notifications/Toasts.qml`: a `NotificationServer` (replaces mako). Bottom-right of the tiling area, at most three at once, five-second default timeout, click to dismiss.
- Each of `Launcher.qml` and `Carousel.qml` holds an `IpcHandler` (targets `launcher` and `carousel`, function `toggle`), so Hyprland binds open them with `qs ipc call launcher toggle` and `qs ipc call carousel toggle`.

Cut corners are drawn with a small shared `Chamfer.qml` shape (one `Shape` with a path), used by the rail, launcher, toasts and carousel. Windows keep Hyprland's rectangular 1px gradient border; Hyprland cannot cut window corners.

State files: `~/.local/state/quickshell/wallpaper.json` (`{ "path": "...", "palette": "..." }`) so the choice survives restarts. Wallpapers are read from `~/Pictures/wallpapers/`.

### 5.4 Palette pipeline (`rice-palette`)

CLI: `rice-palette apply <image>`. Steps: run `matugen image <image> --json hex --dry-run -m dark -t scheme-vibrant` (flags confirmed against `matugen image --help` first), read the JSON, call `derive_palette`, write four files, send reload signals.

`derive_palette(roles: dict[str, str]) -> dict[str, str]` in `~/.local/share/rice/palette.py` is the testable core. It takes matugen's role colours (hex) and returns the eight tokens `bg panel line dim fg a1 a2 warn` (hex). Rules, in OKLCH (L lightness 0 to 1, C chroma, h hue in degrees):

- Hue 1 comes from the `primary` role, hue 2 from `tertiary`. If they differ by less than 40 degrees, hue 2 becomes hue 1 plus 150.
- If the source chroma is below 0.02 (a grey or black wallpaper), hue 1 becomes 195 (cyan) and hue 2 becomes 345 (magenta) so the palette is never muddy.
- `a1 = (L .86, C .17, hue 1)`, `a2 = (L .70, C .22, hue 2)`; chroma is reduced step by step until the colour fits sRGB.
- `bg = (L .12, C .02, hue 1)`, `panel = (L .16, C .025, hue 1)`, `line = (L .26, C .04, hue 1)`.
- `fg = (L .92, C .015, hue 1)`, `dim = (L .66, C .05, hue 1)`.
- `warn = (L .88, C .15, hue 95)`, independent of the wallpaper.
- Contrast guarantees, enforced by nudging lightness: fg on bg at least 7:1, a1 on bg at least 7:1, a2 on bg at least 4.5:1, dim on bg at least 4.5:1.

Outputs: `~/.config/quickshell/colors.json` (the eight tokens, hot-reloaded by the shell), `~/.config/kitty/colors.conf`, `~/.config/hypr/colors.lua` (`hl.config` border colours, applied by `hyprctl reload`), and `~/.config/btop/themes/rice.theme`. Reload: kitty gets `SIGUSR1` (reload config), Hyprland `hyprctl reload`, btop on its next start.

The five palettes in the render were hand-picked. Real palettes come from the user's actual wallpapers, so they will differ; that is expected.

### 5.5 kitty (`~/.config/kitty/`)

`kitty.conf` (does not exist today): font `JetBrainsMono Nerd Font Mono`, `include colors.conf`, and the Mac maps `super+c` copy, `super+v` paste, `super+t` new tab, `super+w` close tab, `super+n` new OS window. `colors.conf` is generated by `rice-palette`.

### 5.6 Claude limits (`claude-limits-statusline`)

A small script run by Claude Code's status line. Logic lives in `~/.local/share/rice/limits.py`, the executable is a thin wrapper.

- `parse_rate_limits(payload: dict, now: float) -> dict` returns `{"five_hour": {"pct": float, "resets_at": int} | None, "seven_day": {...} | None, "updated_at": int}`. A window that is absent or whose `resets_at` has passed is `None`.
- `render_line(data: dict) -> str` returns a short line for the Claude Code footer, such as `5h 38% · 7d 19%`, or an empty string when both windows are absent.
- The wrapper reads stdin, writes `~/.cache/claude-limits.json` atomically (temp file then rename), prints the line, and always exits 0. Malformed input changes nothing and prints nothing.
- The Quickshell widget watches the file. It shows the two bars, reset times, and how old the data is; past 30 minutes it dims. With no file or no windows it shows "no data".

It never reads or sends the login token. Adding the `statusLine` entry to `~/.claude/settings.json` edits a Claude Code settings file outside the dotfiles repo, so it needs the owner's explicit yes at that step. Side effect to tell them: the footer's keyboard hints are hidden once a custom status line exists.

### 5.7 Repo layout and deployment

Everything lives in the chezmoi source repo and is deployed with `chezmoi apply`, using chezmoi's naming: `dot_config/hypr/hyprland.lua` becomes `~/.config/hypr/hyprland.lua`, scripts are `dot_local/bin/executable_<name>`, and the shared Python modules are `dot_local/share/rice/*.py`. Generated files (`colors.lua`, `colors.json`, `colors.conf`) are committed once as `create_` files, which chezmoi writes only if absent and never overwrites afterwards, so `rice-palette` owns them at runtime. A new `.chezmoiignore` lists `docs/` and `tests/` so they are never copied into the home directory. Before the first apply, `chezmoi diff` is run, because the live `~/.config/hypr` may have drifted from the repo copy.

## 6. Key map

All window-manager binds use `Super`, `Ctrl+Alt` or `Ctrl` with a digit; none of them equals an xremap output.

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
| Super + Alt + ←↑↓→ or h j k l | focus window |
| Super + Alt + Shift + ←↑↓→ or h j k l | move window (crosses to the other screen at an edge) |
| Super + ` | focus the other monitor |
| Super + Tab | cycle windows on this screen |
| Super + Space | launcher |
| Super + Q | close window |
| Super + Ctrl + F | fullscreen |
| Super + Alt + Space | toggle floating |
| Ctrl + Alt + T / F / C / E / R / I | terminal, Firefox, VS Code, yazi, Rider, IntelliJ (the current Super+T/F/C/E/R/I launches) |
| Ctrl + Alt + W | carousel |
| Ctrl + Alt + Shift + Q | exit Hyprland (was Super+M) |
| Print | region screenshot (unchanged) |
| XF86Launch2 | headless toggle (unchanged) |
| lid switch on/off | lid script (unchanged) |

The render page's keymap table, workspace card and Stack text are updated to this table and to decisions 1 to 5 above.

## 7. Delivery order and rollback

Each phase leaves a working desktop. Before editing, every live file is backed up as `<name>.bak.<YYYYMMDD-HHMMSS>` (the pattern already used). Old configs (waybar, wofi, mako, hyprpaper, `hyprland.conf`) stay in the repo until the final phase, so rollback is: rename `hyprland.lua` away, restore the backup `hyprland.conf`, restart.

0. Baseline and spikes: install packages, read the mouse codes, confirm Lua config precedence and `require` path, confirm xremap permissions and class names, measure baseline memory.
1. Hyprland Lua migration, per-screen pools, new binds, mouse buttons (waybar still runs).
2. Remapper and kitty maps.
3. Quickshell bar, rail (clock, stats, media) and wallpaper layer; retire waybar and hyprpaper.
4. Launcher and notifications; retire wofi and mako.
5. Palette pipeline and carousel.
6. Bluetooth and Claude widgets, status line script.
7. Optional glitch (spike first).
8. Verification, README and memory updates, removal of retired configs.

## 8. Glitch overlay (optional, last)

Goal: a short tear on workspace change, drawn on the top overlay layer so it covers windows. About 250 ms, six staccato frames, no easing: displaced horizontal bands, red and cyan channel ghosts, a few corrupted blocks. Off by default; a setting turns it on. Idle cost is zero because the overlay window is hidden except during the 250 ms.

Implementation: an overlay `PanelWindow` (layer Overlay, click-through) holding a `ScreencopyView` of the screen and a `ShaderEffect` whose fragment shader is compiled with `qsb`. Two risks make it a spike first: capturing the old workspace before the switch (the capture has to be taken as the bind fires, ahead of the dispatch), and shader behaviour on this hybrid NVIDIA/AMD machine. Fallback if the pre-switch capture is unreliable: capture after the switch and play only the resolving half (frames 4 to 6). If the spike fails outright, the feature is dropped and nothing else depends on it.

## 9. Testing strategy

- Pure logic gets unit tests: `lib/pools.lua` (run with `lua`), `palette.py` and `limits.py` (run with `python3 -m unittest`).
- Collision test: parses bind strings from `binds.lua` and output lines from `xremap/config.yml` and fails on any common combination (S5).
- Config sanity: `hyprctl reload` reports no errors; `xremap --list-windows` lists the expected class names; `qs log` shows no QML errors after each shell change.
- Behaviour is checked against the success criteria with commands written into the plan, plus `grim` screenshots compared by eye with the render page.
- The lid binds are re-tested with the uinput method from the memory note, using `SW_TABLET_MODE` unless logind is confirmed set to `ignore` (it is today).

## 10. Risks and unverified items

- Lua config precedence: that a `hyprland.lua` next to `hyprland.conf` is the one loaded, and how `require` resolves paths. Checked first (Phase 0).
- Mouse side-button codes and whether a bind on `mouse:275` with no modifier works as written. Checked with `wev` (Phase 0 and 1).
- `xremap-hypr-bin` builds and starts cleanly here; a report says the stock service can start slowly after login, so it is started from Hyprland instead.
- JetBrains and Electron apps accept the remapped Ctrl keys.
- Quickshell API names beyond those confirmed in the 0.3.1 docs (`Hyprland.rawEvent`, `DesktopEntries` search helpers) are checked when each piece is built.
- Whether the owner's plan reports `rate_limits` at all (upstream issue #45133). If not, the Claude widget is dropped and the Bluetooth list stays.
- AirPods left, right and case battery may not come through BlueZ; `librepods` (already installed) may be needed. The widget shows the single BlueZ level if that is all there is.
- The glitch spike may fail (section 8).
- The idle-memory budget may be missed. Fallback: keep waybar and mako, use Quickshell only for the carousel and launcher.
- `~/.local/bin/lid open` runs `hyprctl reload`, which now reloads the Lua config. The lid script comments mention `hyprland.conf`; behaviour is unchanged.

## 11. Open questions for the owner

- Confirm the key scheme in section 6, especially `Ctrl+Alt+←/→` for stepping and the `Ctrl+Alt+letter` launches.
- Whether the glitch should be on by default once it exists (this spec says off).
- Which wallpapers go in `~/Pictures/wallpapers/` first. Seeds proposed: the existing Berserk image plus the three Hyprland default wallpapers.
