# dotfiles

Personal Arch Linux dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Contents

| Path | Description |
|------|-------------|
| `~/.bashrc` | Shell config — zoxide, fastfetch on login, nvim as `$EDITOR` |
| `~/.gitconfig` | Git user identity |
| `~/.config/hypr/` | Hyprland compositor config in Lua (`hyprland.lua`, `binds.lua`, `autostart.lua`, per-screen workspace pools in `lib/pools.lua`); the old `hyprland.conf` and `hyprpaper.conf` stay as the rollback copy |
| `~/.config/quickshell/` | Quickshell shell (bar on each screen with VOL, NET, BAT; right-hand rail on the laptop panel `eDP-1` (SYS, DISK, VOLUME, MEDIA, BLUETOOTH, CLAUDE; bar and rail float 6 px off the screen edges like windows), falling back to the main screen with the lid closed, toggled with `qs ipc call rail toggle`; a centred clock on empty workspaces; wallpaper layer, launcher, notification toasts, wallpaper carousel, workspace-switch glitch) replacing waybar, wofi, mako and hyprpaper |
| `~/.config/xremap/` | xremap config: Mac-style Super/Alt shortcuts in GUI apps (not kitty) |
| `~/.config/kitty/` | kitty config (JetBrainsMono Nerd Font, Super copy/paste/tab maps, palette colours) |
| `~/.local/bin/rice-palette`, `~/.local/share/rice/` | Palette tool: derives the neon palette from a wallpaper with matugen and writes the shell, kitty, Hyprland and btop colours |
| `~/.local/bin/claude-limits-statusline` | Claude Code status line command that caches the 5 h / 7 d usage limits for the rail ([setup](docs/claude-statusline.md)) |
| `~/.local/bin/qs-supervise` | Restarts Quickshell if it exits (1 s; backs off up to 30 s if it keeps failing at startup; stops with the compositor); runs it with transparent huge pages off, which cuts its memory ([why](docs/deploy.md#11-memory-the-156-mb-budget-is-not-met)) |
| `~/.local/bin/cursor-shake` | Shake the pointer to enlarge it (like macOS): sleeps on the mouse/touchpad event nodes, reads the position from Hyprland only while the pointer moves, grows the cursor 24 → 96 px on a quick back-and-forth swing and shrinks it 0.8 s after the shaking stops |
| `~/.local/bin/lid`, `~/.local/bin/headless` | Lid switch (drop/restore the laptop panel) and the headless hotkey (displays dark, then mouse/keyboard power cut via `headless-peripherals`); work under the Lua config and the hyprlang rollback |
| `~/.config/waybar/` | Waybar status bar config and stylesheet (retired by the Quickshell shell, kept for rollback) |
| `~/.config/wofi/` | Wofi launcher config and stylesheet (retired by the Quickshell launcher, kept for rollback) |
| `~/.config/nvim/` | Neovim config via [LazyVim](https://lazyvim.org/) |
| `~/.config/btop/` | btop system monitor config |
| `tests/` | Unit tests (`lua tests/lua/*.lua`, `python3 -m unittest discover -s tests -p 'test_*.py'`) and `tests/rig/`, a private headless nested-Hyprland rig for testing the shell without touching the live session (`selftest.sh`, `selftest-qs.sh`, `selftest-rail.sh` for the rail placement/toggle/layout, inner padding and gaps, the CPU temperature, DISK, VOLUME (on a private PipeWire, `fake-pipewire.sh`) and BLUETOOTH sections and the empty-workspace clock). Not deployed |
| `docs/` | [Deployment guide](docs/deploy.md), [Claude limits setup](docs/claude-statusline.md), [design reference](docs/superpowers/design/) (render page and mock screenshots), spec, plan and notes under `docs/superpowers/`. Not deployed |

## Install

```sh
chezmoi init --apply https://github.com/BrunoLoureirooo/Arch-Linux-Config
```

Or if already cloned:

```sh
chezmoi apply
```

The Quickshell desktop is meant to be applied as a whole and has prerequisites and permissions to set up
first: read [docs/deploy.md](docs/deploy.md) before running `chezmoi apply`.

## Hyprland keybinds

Mac-like scheme: Super is Command, Alt is Option, Control stays Control. All window-manager binds use
`Super`, `Ctrl+Alt` or `Ctrl` with a digit; none of them equals a key combination the remapper outputs
(a translated key press re-enters the compositor, so a bind on the same combination would fire on it),
and the remapper never takes a combination Hyprland binds (Hyprland wins; `tests/test_keymap_collisions.py`
checks both).

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
| Super + 1..5, Super + Shift + 1..5 | same as Ctrl + 1..5 and Ctrl + Shift + 1..5 (xremap never remaps them, so Cmd + number does not switch browser tabs) |
| Ctrl + Alt + ← → and mouse side buttons | step previous/next slot on this screen |
| Three-finger swipe on the trackpad (left = next, right = previous) | step the slot on this screen, like macOS Spaces |
| Ctrl + Alt + ↑ ↓ | same slot in the next/previous pool present on this screen (reaches the workspaces a removed screen left here; no-op with one pool) |
| Super + Alt + ←↑↓→ or h j k l | focus window |
| Super + Alt + Shift + ←↑↓→ or h j k l | move window (crosses to the other screen at an edge) |
| Super + the key under Esc (code:49) | focus the other monitor (bound by keycode: on the owner's pt layout that key's keysym is backslash, not grave) |
| Super + Tab | cycle windows on the current workspace (not across the screen or the other workspaces) |
| Super + Space | launcher |
| Super + Q | close window |
| Super + Ctrl + F | fullscreen |
| Super + Alt + Space | toggle floating |
| Super + Alt + R | show/hide the rail (`qs ipc call rail toggle`) |
| Ctrl + Alt + T / F / C / E / R / I | terminal, Firefox, VS Code, yazi, Rider, IntelliJ (the current Super+T/F/C/E/R/I launches) |
| Ctrl + Alt + W | carousel |
| Ctrl + Alt + Shift + Q | exit Hyprland (was Super+M) |
| Print | region screenshot (unchanged) |
| XF86AudioRaiseVolume / LowerVolume / Mute / MicMute | volume ±5 % (capped at 100 %, repeats while held), mute, mic mute via `wpctl`; work on a locked screen. No brightness keys (brightnessctl is not installed) |
| XF86Launch2 | headless toggle (`~/.local/bin/headless`, now in the repo, ported to the Lua config) |
| lid switch on/off | `~/.local/bin/lid close` / `open` (now in the repo, ported to the Lua config) |

Workspaces are two pools of five, one per screen: 1-5 on the BenQ, 11-15 on the laptop panel.

Every workspace change plays a short glitch (about 130 ms) over the windows of that screen. It is on
by default; `qs ipc call glitch disable` turns it off (it creates `~/.local/state/quickshell/glitch-disabled`)
and `qs ipc call glitch enable` turns it back on.
