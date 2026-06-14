# dotfiles

Personal Arch Linux dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Contents

| Path | Description |
|------|-------------|
| `~/.bashrc` | Shell config — zoxide, fastfetch on login, nvim as `$EDITOR` |
| `~/.gitconfig` | Git user identity |
| `~/.config/hypr/` | Hyprland compositor config (kitty, wofi, dolphin, firefox) |
| `~/.config/waybar/` | Waybar status bar config and stylesheet |
| `~/.config/wofi/` | Wofi launcher config and stylesheet |
| `~/.config/nvim/` | Neovim config via [LazyVim](https://lazyvim.org/) |
| `~/.config/btop/` | btop system monitor config |

## Install

```sh
chezmoi init --apply https://github.com/brunoLoureiro/dotfiles
```

Or if already cloned:

```sh
chezmoi apply
```

## Hyprland keybinds

| Key | Action |
|-----|--------|
| `Super + T` | Terminal (kitty) |
| `Super + F` | Firefox |
| `Super + E` | File manager (dolphin) |
| `Super + S` | App launcher (wofi) |
| `Super + Q` | Close window |
| `Super + V` | Toggle floating |
| `Super + H/J/K/L` | Focus left/down/up/right |
| `Super + arrows` | Focus (arrow keys) |
