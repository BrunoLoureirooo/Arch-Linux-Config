# dotfiles

Personal Arch Linux dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Contents

| Path | Description |
|------|-------------|
| `~/.bashrc` | Shell config — zoxide, fastfetch on login, nvim as `$EDITOR` |
| `~/.gitconfig` | Git user identity |
| `~/.config/hypr/` | Hyprland compositor config in Lua (`hyprland.lua`, `binds.lua`, `autostart.lua`, per-screen workspace pools in `lib/pools.lua`); the old `hyprland.conf` and `hyprpaper.conf` stay as the rollback copy |
| `~/.config/quickshell/` | Quickshell shell (bar on each screen, right-hand rail, wallpaper layer, launcher, notification toasts, wallpaper carousel) replacing waybar, wofi, mako and hyprpaper |
| `~/.config/xremap/` | xremap config: Mac-style Super/Alt shortcuts in GUI apps (not kitty) |
| `~/.config/kitty/` | kitty config (JetBrainsMono Nerd Font, Super copy/paste/tab maps, palette colours) |
| `~/.local/bin/rice-palette`, `~/.local/share/rice/` | Palette tool: derives the neon palette from a wallpaper with matugen and writes the shell, kitty, Hyprland and btop colours |
| `~/.local/bin/claude-limits-statusline` | Claude Code status line command that caches the 5 h / 7 d usage limits for the rail ([setup](docs/claude-statusline.md)) |
| `~/.local/bin/qs-supervise` | Restarts Quickshell if it exits |
| `~/.config/waybar/` | Waybar status bar config and stylesheet (retired by the Quickshell shell, kept for rollback) |
| `~/.config/wofi/` | Wofi launcher config and stylesheet (retired by the Quickshell launcher, kept for rollback) |
| `~/.config/nvim/` | Neovim config via [LazyVim](https://lazyvim.org/) |
| `~/.config/btop/` | btop system monitor config |
| `tests/` | Unit tests (`lua tests/lua/*.lua`, `python3 -m unittest discover -s tests -p 'test_*.py'`) and `tests/rig/`, a private headless nested-Hyprland rig for testing the shell without touching the live session. Not deployed |
| `docs/` | [Deployment guide](docs/deploy.md), [Claude limits setup](docs/claude-statusline.md), [design reference](docs/superpowers/design/) (render page and mock screenshots), spec, plan and notes under `docs/superpowers/`. Not deployed |

## Install

```sh
chezmoi init --apply https://github.com/brunoLoureiro/dotfiles
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
(a translated key press re-enters the compositor, so a bind on the same combination would fire on it;
`tests/test_keymap_collisions.py` checks this).

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
| Super + the key under Esc (code:49) | focus the other monitor (bound by keycode: on the owner's pt layout that key's keysym is backslash, not grave) |
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

Workspaces are two pools of five, one per screen: 1-5 on the BenQ, 11-15 on the laptop panel.
