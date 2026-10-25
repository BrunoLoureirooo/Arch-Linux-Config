# Quickshell Terminal Desktop Implementation Plan

> **Superseded by implementation (2026-10-25).** This plan is kept as written. It was executed unattended
> with these deviations (the rulings are in `docs/deploy.md` section 15 and the ledger
> `docs/superpowers/notes/2026-10-23-sdd-ledger.md`):
>
> - **Ask-first gates were not executed** (Task 0 step 4, Task 3 step 5, Task 6 step 3, Task 13 step 2,
>   Task 20, Task 24 step 4). Nothing was applied to the live system, no package installed, no session
>   restart, `~/.claude/settings.json` untouched; each gate became an item in `docs/deploy.md`.
> - **Verification ran in a private headless nested-Hyprland rig** (`tests/rig/`), not on the live
>   desktop; steps that say "apply and check on the live session" were run there or are listed UNVERIFIED.
>   `tests/tools/uinput_keys.py` also has a CLI; the rig injects keys with `wtype`.
> - **Task 0/3:** the live `hyprland.conf`, `hyprpaper.conf` and waybar config were ahead of the repo and were
>   synced into the repo before porting; the Lua config ports the live files.
> - **Task 4:** `Super+grave` became `Super + code:49`; pool binds are nil-safe; workspace 11 is also a default on the panel.
> - **Task 10:** NET is the default-route interface from `/proc/net/route` (no nmcli); BAT on every screen with a battery.
> - **Task 12 (and Task 10's GPU row):** the memory checkpoint failed: the 156 MB budget is not met (about 345 MB PSS in the rig);
>   options in `docs/deploy.md` section 11. The rail's GPU row defaults to the AMD iGPU; NVIDIA is opt-in (`RICE_NVIDIA=1`).
> - **Task 13:** `qs-supervise` replaces waybar and hyprpaper in the autostart (repo only).
> - **Task 17:** `rice-palette` has rollback on write failure; grey wallpapers keep matugen's chromatic palette.
> - **Task 22 (glitch): spike run, NO-GO, dropped** (about +45 MB retained memory); the plan's Step 4 to 5 "go" paths were not built.
> - **Task 24:** the README and `docs/deploy.md` were written; deleting the retired configs is left to the owner
>   (`docs/deploy.md` section 14). `.gitignore` was added and `.chezmoiignore` also lists `**/__pycache__` and `*.pyc`.
> - **Pending (final fix wave):** replace `SystemClock` with a timer-based clock (daylight-saving finding);
>   give the carousel's `rice-palette apply` a timeout.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace waybar + wofi + mako + hyprpaper with one Quickshell shell that looks like a cyberpunk terminal, give Hyprland one workspace pool per screen, and make the keyboard and mouse behave like the owner's Macs.

**Architecture:** A Lua Hyprland config (hand-rolled per-screen pools, collision-free key scheme), an app-aware remapper (xremap) for the Super and Alt combinations, one Quickshell QML tree (per-screen bar, main-screen rail, wallpaper layer, launcher, carousel, toasts), and two small Python tools: `rice-palette` (wallpaper to palette) and `claude-limits-statusline` (Claude Code to a cache file). Each phase leaves a working desktop.

**Tech Stack:** Hyprland 0.56.2 Lua API, Quickshell 0.3.1 (QML), xremap-hypr-bin, matugen 4.2.0, kitty, Python 3.14 (`unittest`), Lua 5.5 (`lua`), chezmoi.

**Spec:** `docs/superpowers/specs/2026-10-23-quickshell-terminal-desktop-design.md` (read it first; this plan does not repeat it).

## Global Constraints

- Hyprland is 0.56.2 and uses the Lua API (`hl.*`). Quickshell is 0.3.1. matugen is 4.2.0 (used for JSON colour extraction only, no matugen templates).
- Idle budget for the whole shell: RSS at most 156 MB (baseline: waybar 79 + mako 24 + hyprpaper 53), CPU under 2% of one core averaged over 60 s.
- No blur, shadows, rounded corners or easing animations. The optional glitch (Task 22) is the only exception.
- Pools: BenQ (description `BNQ BenQ EX2510S K8M02386019`) is pool 0 = workspaces 1 to 5; `eDP-1` is pool 1 = workspaces 11 to 15; unknown monitors take pool 2 and up. `ws_id = pool * 10 + slot`, slot 1 to 5, stepping clamps and never wraps.
- Palette tokens are exactly `bg panel line dim fg a1 a2 warn`. Contrast: fg and a1 at least 7:1 on bg, a2 and dim at least 4.5:1.
- Key scheme is the two tables in spec section 6. No Hyprland bind may equal an xremap output.
- GPU stats come from the AMD sysfs file found by vendor id `0x1002`. Never run `nvidia-smi`. Never read or send the Claude login token.
- Back up every live file before editing it as `<name>.bak.<YYYYMMDD-HHMMSS>`.
- Deploy with `chezmoi -S "$PWD" apply <target path>` from the worktree while on the branch. Never push to `main`; the owner merges.
- Tests: `lua tests/lua/<file>.lua` and `python3 -m unittest discover -s tests -p 'test_*.py' -v`, both from the repo root.
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Ask the owner first, and wait:** anything needing `sudo`, any AUR build, restarting the Hyprland session, editing `~/.claude/settings.json`, udev or group changes, and deleting the retired configs. Suggest they run privileged commands with the `!` prefix.

## Review Focus

Inputs and conditions the spec implies but the happy path will not exercise, most likely first. Each has a test in the task named in brackets.

1. **Dock unplug and replug.** Unplugging the BenQ must move its workspaces and windows to the laptop panel without losing any, and `Ctrl+1..5` must keep working on the remaining screen; replugging restores the pool. [Task 4]
2. **Remapper and Hyprland binds colliding.** A translated key press re-enters the compositor, so an output that equals a bind fires the bind. Also `Super-c` must not fire for `Super-Alt-c`. [Task 6]
3. **Terminal safety.** `Ctrl+C` in kitty must still interrupt, `Super+C` must copy, and Super must not leak into kitty as Ctrl. [Task 7]
4. **Missing or malformed data files.** `colors.json`, the Claude limits cache, the wallpaper state file and the wallpaper folder may be absent, empty or corrupt; the shell must fall back to built-in defaults and show "no data", never a blank or crashing bar. The status line script must exit 0 with no output on bad input, because Claude Code displays whatever it prints. [Tasks 8, 11, 19, 21]
5. **Awkward wallpapers.** A grey or black image (no hue), a tiny or huge image, a non-image file in the folder, and a folder with zero or one image must all give a valid palette or a clear empty state in the carousel. [Tasks 11, 16, 17, 18]

---

## Phase 0: Baseline and spikes

### Task 0: Baseline, drift check, backups, packages

**Files:**
- Create: `docs/superpowers/notes/2026-10-23-baseline.md`

**Interfaces:**
- Produces: the recorded baseline numbers (RSS, CPU) and the confirmed state of the live configs that Tasks 2 to 24 compare against.

- [ ] **Step 1: Record the baseline.** Run `ps -eo rss,pcpu,comm | grep -E 'waybar|mako|hyprpaper|Hyprland'` three times 20 s apart. Write the numbers and `hyprctl version | head -1` into the notes file. Expected: waybar about 79 MB, mako about 24 MB, hyprpaper about 53 MB.
- [ ] **Step 2: Check drift between the live config and the repo.** Run `chezmoi -S "$PWD" diff ~/.config/hypr ~/.config/waybar ~/.config/wofi`. If the live files differ from the repo copies, stop and ask the owner which side wins; do not overwrite either side silently.
- [ ] **Step 3: Back up live files.** For each of `~/.config/hypr/hyprland.conf`, `~/.config/hypr/hyprpaper.conf`, `~/.config/waybar/config.jsonc`, `~/.config/waybar/style.css`, `~/.config/wofi/config`, `~/.config/wofi/style.css`: `cp -a FILE FILE.bak.$(date +%Y%m%d-%H%M%S)`.
- [ ] **Step 4: Ask the owner to install packages.** Suggest: `! sudo pacman -S --needed quickshell matugen wev` and `! yay -S xremap-hypr-bin`. Wait for confirmation. Verify: `qs --version`, `matugen --version` (expect 4.2.0), `xremap --help | head -1`, `wev --help 2>&1 | head -1`.
- [ ] **Step 5: Commit** the notes file: `git add docs/superpowers/notes && git commit -m "docs: record baseline before Quickshell migration"`.

### Task 1: Spikes that decide later tasks

**Files:**
- Modify: `docs/superpowers/notes/2026-10-23-baseline.md` (append findings)

**Interfaces:**
- Produces: four recorded facts used later: (a) the two mouse button codes, (b) which config file Hyprland loads when both exist and how `require` resolves, (c) the exact xremap application class names, (d) the exact JSON structure `matugen image --json hex --dry-run` prints.

- [ ] **Step 1: Mouse codes.** Run `wev -f wl_pointer:button`, click the two side buttons on the G502, press `Ctrl+C`. Record both button codes. Expected: 275 and 276; if different, every `mouse:275/276` in this plan uses the recorded values.
- [ ] **Step 2: Config precedence and `require`.** Fetch https://wiki.hypr.land/Configuring/Start/ and the Lua pages it links; run `Hyprland --help` and find the config-verify flag. Record: (1) whether `~/.config/hypr/hyprland.lua` wins over `hyprland.conf`, (2) the module path form for `require` (for a file at `~/.config/hypr/lib/pools.lua`), (3) the exact syntax of a no-modifier bind such as `mouse:275` and of a switch bind (`switch:on:Lid Switch`) in `hl.bind`. If the docs do not say, test with a throwaway file and `--verify-config` outside the live session; never test by replacing the live config.
- [ ] **Step 3: xremap class names.** With Firefox, kitty, VS Code and dolphin open, run `xremap --list-windows`. Record the class strings (kitty must appear exactly as matched later).
- [ ] **Step 4: matugen JSON shape.** Run `matugen image ~/Pictures/berserk-wallpaper.jpg --json hex --dry-run -m dark -t scheme-vibrant` (adjust flags to what `matugen image --help` lists). Save the output to `tests/fixtures/matugen-berserk.json` and record how the `primary` and `tertiary` role colours are reached in it.
- [ ] **Step 5: Commit** the notes and fixture: `git add docs tests/fixtures && git commit -m "docs: record spike findings (mouse codes, lua precedence, xremap classes, matugen shape)"`.

---

## Phase 1: Hyprland Lua, per-screen pools, new binds

### Task 2: Pool arithmetic (`lib/pools.lua`)

**Files:**
- Create: `dot_config/hypr/lib/pools.lua`
- Test: `tests/lua/test_pools.lua`

**Interfaces:**
- Produces (module returned by the file): `ws_id(pool, slot) -> integer`; `pool_for(mon, assigned) -> integer` where `mon = {name = string, description = string}` and `assigned` is a table the caller keeps for the session; `slot_of(workspace_id, pool) -> integer`; `step(slot, delta) -> integer`.

- [ ] **Step 1: Write the failing test** in `tests/lua/test_pools.lua`. It sets `package.path = "dot_config/hypr/lib/?.lua;" .. package.path`, requires `pools`, and asserts, with a message per line:
  - `ws_id(0,1) == 1`, `ws_id(0,5) == 5`, `ws_id(1,1) == 11`, `ws_id(1,5) == 15`
  - with an empty `assigned`: BenQ `{name="DP-1", description="BNQ BenQ EX2510S K8M02386019"}` gives 0; `{name="eDP-1", description="Chimei Innolux Corporation 0x1609"}` gives 1
  - with a fresh empty `assigned` and only an unknown monitor `{name="HDMI-A-1", description="X"}`: gives 2 (pools 0 and 1 stay reserved even if the BenQ was never seen); a second unknown `{name="DP-3", description="Y"}` gives 3; asking for `HDMI-A-1` again still gives 2
  - `slot_of(13, 1) == 3`, `slot_of(3, 0) == 3`, `slot_of(13, 0) == 1` (id from another pool), `slot_of(15, 1) == 5`
  - `step(5, 1) == 5`, `step(1, -1) == 1`, `step(3, 1) == 4`, `step(3, -1) == 2`
  - ends with `print("ok")`
- [ ] **Step 2: Run it to see it fail.** `lua tests/lua/test_pools.lua`. Expected: error "module 'pools' not found".
- [ ] **Step 3: Implement the four functions** in `dot_config/hypr/lib/pools.lua`, returning a table. No `hl` calls. `pool_for` matches the BenQ by description prefix `BNQ BenQ` and the panel by name `eDP-1`; other monitors are keyed by `name` in `assigned`.
- [ ] **Step 4: Run the test.** `lua tests/lua/test_pools.lua`. Expected: `ok`.
- [ ] **Step 5: Commit.** `git add dot_config/hypr/lib tests/lua && git commit -m "feat(hypr): per-screen workspace pool arithmetic"`.

### Task 3: Port the current config to Lua, unchanged behaviour

**Files:**
- Create: `dot_config/hypr/hyprland.lua`, `dot_config/hypr/create_colors.lua`
- Keep: `dot_config/hypr/hyprland.conf` (rollback copy until Task 24)

**Interfaces:**
- Consumes: the spike notes from Task 1 (precedence, `require` form, bind syntax).
- Produces: `hyprland.lua` that does everything the current `hyprland.conf` does, and requires `colors` for the border colours.

- [ ] **Step 1: Write `hyprland.lua`** translating `hyprland.conf` one to one: monitors (`desc:BNQ BenQ EX2510S K8M02386019` at `1920x1080@144` position `0x0`; `eDP-1` at `1920x1080@144` position `1920x0`), the `workspace = 1 ... default:true` rule, all `env` lines (NVIDIA, Electron, `XDG_MENU_PREFIX`), `input.kb_layout = "pt"`, looks (`gaps_in 3`, `gaps_out 6`, `border_size 1`, rounding 0, blur off, shadow off, animations off), autostart through `hl.on("hyprland.start", ...)` (`mako`, `waybar`, `blueman-applet`, `librepods --start-minimized`, `airpods-autoconnect`, `sleep 1 && hyprpaper`), the current binds exactly as they are today, `Print`, and the lid and `XF86Launch2` binds (`locked = true`). Border colours come from `require("colors")`.
- [ ] **Step 2: Write `create_colors.lua`** returning `{ active = {"rgba(00f0ffff)", "rgba(ff2e88ff)"}, inactive = "rgba(1b1d30ff)" }` (the neon-rain tokens).
- [ ] **Step 3: Verify without touching the live session.** Run the verify command recorded in Task 1 against `dot_config/hypr/hyprland.lua` copied to a temp dir. Expected: no errors reported.
- [ ] **Step 4: Commit.** `git add dot_config/hypr && git commit -m "feat(hypr): Lua config equivalent to current hyprland.conf"`.
- [ ] **Step 5: Cutover, asking first.** Tell the owner this needs a session restart and ask for a good moment. Then `chezmoi -S "$PWD" apply ~/.config/hypr`, move the live `hyprland.conf` aside (`mv hyprland.conf hyprland.conf.disabled`), and ask them to log out and back in. Verify after login: `hyprctl version | head -1`, `hyprctl binds | head`, bar and wallpaper present, lid bind present (`hyprctl binds | grep -i lid`). Rollback if anything is wrong: move `hyprland.conf.disabled` back and restart.

### Task 4: Per-screen pools, mouse buttons, new window-manager binds

**Files:**
- Create: `dot_config/hypr/binds.lua`, `tests/tools/uinput_keys.py`, `tests/hypr/check_pools.sh`
- Modify: `dot_config/hypr/hyprland.lua` (require `binds`, replace the old binds with the section 6 table, add workspace rules), `dot_config/waybar/config.jsonc` (interim per-output workspace list)

**Interfaces:**
- Consumes: `pools` (Task 2).
- Produces: all binds from spec section 6 (Hyprland table); `tests/tools/uinput_keys.py` exposing `press(*keys: str) -> None` (creates a virtual keyboard named `rice-test`, sends the combination down and up, destroys it; key names like `LEFTCTRL`, `LEFTALT`, `2`, `LEFT`) for later tasks.

- [ ] **Step 1: Write `tests/tools/uinput_keys.py`** following the ctypes approach in the memory note `simulating-input-events-uinput` (`UI_SET_EVBIT` EV_KEY, `UI_SET_KEYBIT` per key, `UI_DEV_SETUP`, `UI_DEV_CREATE`, 2 s wait, write events, `UI_DEV_DESTROY`). Signature `press(*keys: str) -> None`.
- [ ] **Step 2: Write `tests/hypr/check_pools.sh`** (the failing check). It records `hyprctl monitors -j` active workspace ids, calls `python3 tests/tools/uinput_keys.py LEFTCTRL 3`, and asserts the focused monitor's active workspace id changed to `ws_id(pool,3)` (3 on the BenQ or 13 on the panel) while the other monitor's id is unchanged; then repeats with `LEFTCTRL LEFTALT RIGHT` to assert a step. Exit non-zero on failure.
- [ ] **Step 3: Run it now.** Expected: FAIL (binds do not exist yet).
- [ ] **Step 4: Implement `binds.lua`.** One local function `active_pool()` using `hl.get_active_monitor()` and `pools.pool_for`, a shared `assigned` table, and: `Ctrl + 1..5` focus, `Ctrl + Shift + 1..5` move window, `Ctrl + Alt + Left/Right` and `mouse:275`/`mouse:276` step (use the Task 1 codes and bind syntax), the Super and Super+Alt binds and app launches from the spec table, `Super + Space` running `qs ipc call launcher toggle`, `Ctrl + Alt + W` running `qs ipc call carousel toggle`. In `hyprland.lua` add, for each id in pools 0 and 1, `hl.workspace_rule({workspace = tostring(id), monitor = <selector>, persistent = true})` (BenQ by `desc:BNQ BenQ EX2510S K8M02386019`, panel by `eDP-1`), with workspace 1 `default = true`. Remove every old bind the table replaces.
- [ ] **Step 5: Interim waybar fix.** In `dot_config/waybar/config.jsonc` set `persistent-workspaces` to `{"DP-1": [1,2,3,4,5], "eDP-1": [11,12,13,14,15]}` so the bar matches until Task 10 replaces it.
- [ ] **Step 6: Apply and run the check.** `chezmoi -S "$PWD" apply ~/.config/hypr ~/.config/waybar`, `hyprctl reload`, then `bash tests/hypr/check_pools.sh`. Expected: PASS for jump and step; manually press both mouse side buttons and confirm the focused screen's workspace steps.
- [ ] **Step 7: Dock test (Review Focus 1).** Check `pacman -Q aquamarine` is 0.15.1 or later first (memory note `aquamarine-0150-stale-crtc`). Open a window on BenQ workspace 2, run `hyprctl keyword monitor "desc:BNQ BenQ EX2510S K8M02386019,disable"`. Assert with `hyprctl clients -j` that the window still exists and `Ctrl+3` (via `uinput_keys.py`) lands on workspace 13. Re-enable with `hyprctl reload` and assert workspaces 1 to 5 return to the BenQ.
- [ ] **Step 8: Lid test.** Following the memory note, confirm `busctl` shows logind lid handling as `ignore`, then fire a safe `SW_TABLET_MODE` switch device named `Lid Switch` and confirm the bind still reaches `~/.local/bin/lid` (check with `hyprctl monitors -j` as before).
- [ ] **Step 9: Commit.** `git add -A && git commit -m "feat(hypr): per-screen pools, mouse step buttons and new bind scheme"`.

---

## Phase 2: Remapper and terminal

### Task 5: Keymap tables as the shared source of truth

**Files:**
- Create: `tests/test_keymap_collisions.py`

**Interfaces:**
- Produces: `parse_binds(lua_text: str) -> set[str]`, `parse_xremap_outputs(yaml_text: str) -> set[str]`, `normalize(combo: str) -> str` (uppercase, modifiers sorted `ALT CTRL SHIFT SUPER`, joined with `+`, accepts `C-`/`Ctrl-`/`CTRL + ` and `M-`/`Alt-`).

- [ ] **Step 1: Write the failing tests.** Names and assertions:
  - `test_normalize_forms`: `normalize("C-Left") == normalize("CTRL + Left") == "CTRL+LEFT"`; `normalize("Super-Alt-c") == "ALT+SUPER+C"`.
  - `test_parsers_find_sentinels`: parsing the real `binds.lua` contains `CTRL+ALT+LEFT` and `CTRL+1`; parsing the real `config.yml` contains `CTRL+C` and `CTRL+LEFT` (guards against parsers that silently find nothing).
  - `test_no_collisions`: `parse_binds(...) & parse_xremap_outputs(...)` is empty; the failure message lists the common combinations.
  - `test_exact_match_everywhere`: every `keymap` entry in `config.yml` has `exact_match: true`.
- [ ] **Step 2: Run to see it fail.** `python3 -m unittest tests.test_keymap_collisions -v`. Expected: FAIL (no `config.yml`).
- [ ] **Step 3: Implement the three helper functions** in the test module (regex over bind strings `hl.bind("...")`, line-based parse of `key: value` pairs in the YAML since it is flat).
- [ ] **Step 4: Commit the test.** `git add tests && git commit -m "test: keymap collision guard (red until Task 6)"`.

### Task 6: xremap config and autostart

**Files:**
- Create: `dot_config/xremap/config.yml`
- Modify: `dot_config/hypr/hyprland.lua` (autostart)

**Interfaces:**
- Consumes: the class names from Task 1; the xremap output table from spec section 6.
- Produces: a `keymap` with `application: not: [<kitty class>]`, `exact_match: true`, containing exactly the "xremap outputs" rows (Super and Alt translations).

- [ ] **Step 1: Write `config.yml`.** One keymap block per output family, each with `exact_match: true` and the `application: not:` filter: Super+letters to Ctrl+letters (`Super-c: C-c`, and so on for `v x a z f s l t w n r`), Super+Shift+`t z n` to Ctrl+Shift+same, `Super-left: home`, `Super-right: end`, Shift variants, `Super-up: C-home`, `Super-down: C-end`, `Alt-left: C-left`, `Alt-right: C-right`, `Alt-backspace: C-backspace`, `Alt-Shift-left: C-Shift-left`, `Alt-Shift-right: C-Shift-right`. Use the exact key spelling xremap accepts (check against its README example forms).
- [ ] **Step 2: Run the collision tests.** `python3 -m unittest tests.test_keymap_collisions -v`. Expected: all four PASS. If a collision is reported, change the Hyprland bind (never the output) and update spec section 6.
- [ ] **Step 3: Autostart, asking first.** Ask the owner whether to add them to the `input` group (`! sudo usermod -aG input $USER`, needs re-login) or use a udev rule; wait. Then add `hl.exec_cmd("xremap ~/.config/xremap/config.yml")` to the `hyprland.start` handler.
- [ ] **Step 4: Apply and verify.** `chezmoi -S "$PWD" apply ~/.config/xremap ~/.config/hypr`, restart xremap by hand once (`pkill xremap; xremap ~/.config/xremap/config.yml &`). With `wev` focused, press `Super+C`: expected `Control_L` then `c`, no Super. Press `Super+Alt+C`: expected Super and Alt held, no Control.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(keys): xremap Super/Alt translations for GUI apps"`.

### Task 7: kitty config with Mac maps

**Files:**
- Create: `dot_config/kitty/kitty.conf`, `dot_config/kitty/create_colors.conf`

**Interfaces:**
- Produces: kitty maps `super+c` copy, `super+v` paste, `super+t` new tab, `super+w` close tab, `super+n` new OS window; `include colors.conf`; font `JetBrainsMono Nerd Font Mono`.

- [ ] **Step 1: Write both files.** `create_colors.conf` holds the neon-rain tokens as kitty colour keys (`foreground`, `background`, `cursor`, `color0..15` derived from the eight tokens, `active_border_color` a1, `inactive_border_color` line).
- [ ] **Step 2: Apply and run the terminal safety matrix (Review Focus 3).** `chezmoi -S "$PWD" apply ~/.config/kitty`, open a new kitty, then check each: (a) select text, `Super+C`, paste into Firefox's URL bar with `Super+V`: text arrives; (b) run `sleep 100`, press `Ctrl+C`: it is interrupted; (c) `Super+T` opens a tab, `Super+W` closes it; (d) in Firefox `Super+T` opens a tab and `Super+L` focuses the address bar.
- [ ] **Step 3: Commit.** `git add -A && git commit -m "feat(kitty): config with Mac-style super maps"`.

---

## Phase 3: Quickshell core

### Task 8: Shell skeleton, Theme singleton, supervisor

**Files:**
- Create: `dot_config/quickshell/shell.qml`, `dot_config/quickshell/Theme.qml`, `dot_config/quickshell/qmldir`, `dot_config/quickshell/create_colors.json`, `dot_local/bin/executable_qs-supervise`

**Interfaces:**
- Produces: `Theme` singleton with colour properties `bg panel line dim fg a1 a2 warn` (all `color`), `font` (string, `JetBrainsMono Nerd Font Mono`), `px` (real, 12), and functions `preview(tokens: var)` and `clearPreview()` for the carousel. `qs-supervise`: runs `qs`, restarts it after 1 s whenever it exits.

- [ ] **Step 1: Write the files.** `Theme.qml` is `pragma Singleton`, reads `colors.json` through a watching `FileView` with a `JsonAdapter` whose defaults are the neon-rain tokens (so a missing or corrupt file falls back to defaults: Review Focus 4). `shell.qml` is a `ShellRoot` containing nothing yet. `qmldir` registers `singleton Theme Theme.qml`.
- [ ] **Step 2: Start it and read the log.** `chezmoi -S "$PWD" apply ~/.config/quickshell ~/.local/bin/qs-supervise`, `qs-supervise &`, then `qs log | grep -Ei 'error|warn' | head`. Expected: no output.
- [ ] **Step 3: Test the fallback and hot reload.** Replace `colors.json` with `{ not json`, confirm the log shows a parse warning and the shell stays up. Restore it, change `a1`, confirm the change is picked up without restarting (`qs log` shows the reload).
- [ ] **Step 4: Supervisor test (S8).** `pkill -x quickshell`; within 3 s `pgrep -x quickshell` must succeed again. Time it with `date +%s.%N` before and after.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(shell): Quickshell skeleton, Theme singleton and supervisor"`.

### Task 9: Chamfer shape and shared parts

**Files:**
- Create: `dot_config/quickshell/components/Chamfer.qml`, `components/Meter.qml`, `components/Chip.qml`

**Interfaces:**
- Produces: `Chamfer` (`Item`) with `property real cut: 10`, `property color fill: Theme.bg`, `property color stroke: Theme.line`, `property bool hot: false` (gradient border a1 to a2 at 45 degrees), `default property alias content: slot.data`; `Meter` (`Item`) with `property real value` (0 to 100), `property int cells: 5`, `property real warnAbove: 75`, `property bool invert: false` (low is bad, for batteries); `Chip` with `property string label`, `property string text`, `property real meter: -1` (negative hides the meter).

- [ ] **Step 1: Write a scratch window** `dot_config/quickshell/scratch.qml` (not committed) showing one `Chamfer` (normal and `hot`), `Meter` at 20, 50 and 90, and a `Chip`. Run `qs -p dot_config/quickshell/scratch.qml`.
- [ ] **Step 2: Implement the three components.** `Chamfer` draws one closed `ShapePath` polygon (top-left and bottom-right corners cut by `cut`); `Meter` is a `Row` of `cells` rectangles, lit up to `value`, `Theme.warn` past `warnAbove` (or at or below 20 when `invert`).
- [ ] **Step 3: Check against the render.** `grim -o DP-1 /tmp/scratch.png` and view it: cut corners match the render page, `hot` border shows both colours. Delete `scratch.qml`.
- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(shell): Chamfer, Meter and Chip components"`.

### Task 10: Stats service and the per-screen bar

**Files:**
- Create: `dot_config/quickshell/services/Stats.qml`, `bar/Bar.qml`, `bar/Workspaces.qml`
- Modify: `dot_config/quickshell/shell.qml`

**Interfaces:**
- Consumes: `Theme`, `Chip`, `Meter`.
- Produces: `Stats` singleton with `cpu` (0 to 100), `memGb` (real), `memPct` (0 to 100), `gpu` (0 to 100, `-1` if no AMD sysfs file) updated every 2000 ms by one timer; `Bar` (`PanelWindow`, top, height 26, one per screen via `Variants`); `Workspaces` with `property var screen`, showing slots 1 to 5 from the workspaces Hyprland reports on that screen (`slot = ((id - 1) % 10) + 1`).

- [ ] **Step 1: Implement `Stats.qml`.** CPU from two `/proc/stat` samples, memory from `/proc/meminfo`, GPU from `/sys/class/drm/card*/device/gpu_busy_percent` located by `vendor == 0x1002` (one lookup at start).
- [ ] **Step 2: Implement `Workspaces.qml` and `Bar.qml`** to match the render: left logo tile, five slot cells (active filled with `a1`, occupied underlined, others dim), `//` and the focused window title; centre clock and date; right chips for CPU (with `Meter`), MEM, VOL (`Quickshell.Services.Pipewire` default sink volume), NET (name of the active `nmcli` connection, polled every 5 s), and BAT on the panel only (`Quickshell.Services.UPower`).
- [ ] **Step 3: Verify independence.** Until Task 13 retires waybar, the old and new bars stack at the top of each screen; that is expected. With both bars up, press `Ctrl+2` on the BenQ: only the BenQ bar's active cell moves. Press `Ctrl+Alt+Right` on the laptop screen: only its bar moves. Take `grim` screenshots of both and compare with the render.
- [ ] **Step 4: Verify the stats.** Compare the CPU chip against `top -bn1 | head -3` and memory against `free -m`; confirm GPU reads a number and that `pgrep -x nvidia-smi` is empty while the shell runs.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(shell): per-screen bar with pool-aware workspaces and stats"`.

### Task 11: Wallpaper layer

**Files:**
- Create: `dot_config/quickshell/wallpaper/Wallpaper.qml`
- Modify: `dot_config/quickshell/shell.qml`

**Interfaces:**
- Produces: `Wallpaper` (`PanelWindow`, `WlrLayershell.layer: WlrLayer.Background`, all anchors, one per screen) with `property string path`; `shell.qml` holds `property string wallpaperPath` read from `~/.local/state/quickshell/wallpaper.json` (`{"path": "...", "palette": "..."}`), defaulting to `~/Pictures/berserk-wallpaper.jpg` when the file is absent or invalid.

- [ ] **Step 1: Implement** with an `Image` (`fillMode: Image.PreserveAspectCrop`, `asynchronous: true`, `sourceSize` capped at the screen size so a huge image does not balloon memory).
- [ ] **Step 2: Verify.** Both screens show the wallpaper (the BenQ had none before). Corrupt the state file; the default image appears, no crash. Point it at a text file; the layer shows the background colour, no crash (Review Focus 4, 5).
- [ ] **Step 3: Commit.** `git add -A && git commit -m "feat(shell): wallpaper layer on every screen"`.

### Task 12: The rail (clock, system, media) and the memory checkpoint

**Files:**
- Create: `dot_config/quickshell/rail/Rail.qml`, `rail/ClockWidget.qml`, `rail/SysWidget.qml`, `rail/MediaWidget.qml`
- Modify: `dot_config/quickshell/shell.qml`

**Interfaces:**
- Consumes: `Chamfer` (hot), `Stats`, `Meter`, `Quickshell.Services.Mpris`.
- Produces: `Rail` (`PanelWindow` on the main screen only: the screen whose `model` or description starts with `BNQ BenQ`, else the first screen), width 22.5% of the screen, `exclusiveZone` set so windows tile beside it. Widgets: clock (large digits, date), SYS (CPU, MEM, GPU segmented bars plus a net sparkline), media (title, artist, progress; hidden when no player).

- [ ] **Step 1: Implement** the rail and three widgets to match the render, using `Stats` for the numbers. The sparkline keeps the last 24 net samples in a `list<real>` and draws one `Shape` polyline.
- [ ] **Step 2: Verify layout.** Windows on the BenQ tile to the left of the rail and never underneath it. The laptop screen has no rail. Play something with Spotify or `mpv` and confirm the media widget appears and hides.
- [ ] **Step 3: Memory and CPU checkpoint (S1, S2).** Run `for i in $(seq 12); do ps -C quickshell -o rss=,pcpu=; sleep 5; done`. Expected: RSS under 156 MB total with waybar and hyprpaper still running separately; record the number in the baseline notes. If the shell alone is already near 120 MB, stop and tell the owner before continuing.
- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(shell): right rail with clock, system and media widgets"`.

### Task 13: Retire waybar and hyprpaper

**Files:**
- Modify: `dot_config/hypr/hyprland.lua` (autostart)

- [ ] **Step 1: Edit the autostart handler:** remove `waybar` and `sleep 1 && hyprpaper`, add `qs-supervise`. Keep `dot_config/waybar` and `hyprpaper.conf` in the repo for rollback.
- [ ] **Step 2: Apply and restart the session, asking first.** Verify after login: no `waybar` or `hyprpaper` process, both bars and wallpapers present, `Ctrl+1..5` still work, memory check from Task 12 repeated with the final process set (expected: total under 156 MB, S1).
- [ ] **Step 3: Commit.** `git add -A && git commit -m "feat(hypr): start Quickshell instead of waybar and hyprpaper"`.

---

## Phase 4: Launcher and notifications

### Task 14: Notification toasts

**Files:**
- Create: `dot_config/quickshell/notifications/Toasts.qml`
- Modify: `dot_config/quickshell/shell.qml`, `dot_config/hypr/hyprland.lua` (remove `mako`)

**Interfaces:**
- Produces: `Toasts` holding one `NotificationServer` (`keepOnReload: true`, `actionsSupported: false`, `bodySupported: true`), rendering `trackedNotifications` as `Chamfer` toasts (`hot` border color a2) at the bottom right of the tiling area, at most three visible, default timeout 5 s, click to dismiss.

- [ ] **Step 1: Implement.** Stop `mako` first (`pkill mako`) so the shell owns the D-Bus name.
- [ ] **Step 2: Verify.** `notify-send "build ok" "shell reloaded"` shows one toast that disappears after 5 s. Run `for i in 1 2 3 4 5; do notify-send "n$i"; done`: three visible at once, the rest queue. `notify-send -u critical "stays"` still times out or stays per the notification's own timeout; click dismisses.
- [ ] **Step 3: Remove `mako` from autostart,** apply, commit: `git add -A && git commit -m "feat(shell): notification toasts replace mako"`.

### Task 15: Launcher

**Files:**
- Create: `dot_config/quickshell/launcher/Launcher.qml`
- Modify: `dot_config/quickshell/shell.qml`, `dot_config/hypr/hyprland.lua` (nothing to remove: `wofi` was only referenced by the old `Super+Space` bind, already replaced in Task 4)

**Interfaces:**
- Produces: `Launcher` overlay (`WlrLayershell.layer: Overlay`, keyboard focus on demand) containing an `IpcHandler { target: "launcher"; function toggle(): void }`. Behaviour: text field, results from `DesktopEntries` filtered by case-insensitive substring on the name, at most 8 rows, up/down moves, Enter runs the entry, Escape closes; result count shown as `n / total`.

- [ ] **Step 1: Confirm the `DesktopEntries` API** by querying the Quickshell 0.3.1 docs for its entry list and the run call before writing code.
- [ ] **Step 2: Implement** the overlay to match the render.
- [ ] **Step 3: Verify.** `Super+Space` opens it centred on the focused screen; type `fir`, Enter starts Firefox; Escape closes with focus returning to the previous window; opening it again clears the text. `qs ipc call launcher toggle` from a terminal does the same.
- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(shell): launcher over desktop entries"`.

---

## Phase 5: Palette pipeline and carousel

### Task 16: Palette derivation (`palette.py`)

**Files:**
- Create: `dot_local/share/rice/palette.py`, `tests/test_palette.py`

**Interfaces:**
- Produces: `hex_to_oklch(h: str) -> tuple[float, float, float]`, `oklch_to_hex(l: float, c: float, h: float) -> str` (reduces chroma until the colour fits sRGB), `contrast(a: str, b: str) -> float`, `derive_palette(roles: dict[str, str]) -> dict[str, str]` returning exactly the keys `bg panel line dim fg a1 a2 warn` as `#rrggbb`.

- [ ] **Step 1: Write the failing tests** in `tests/test_palette.py` (importing from `dot_local/share/rice`):
  - `test_roundtrip`: `oklch_to_hex(*hex_to_oklch("#00f0ff"))` is within 1 per channel of `#00f0ff`.
  - `test_keys_and_format`: output keys equal the eight tokens, each matches `^#[0-9a-f]{6}$`.
  - `test_contrast_floor`: for roles `{"primary": "#7df9ff", "tertiary": "#ff2e88"}`, `contrast(fg,bg) >= 7`, `contrast(a1,bg) >= 7`, `contrast(a2,bg) >= 4.5`, `contrast(dim,bg) >= 4.5`.
  - `test_hue_follows_wallpaper`: hue of `a1` is within 15 degrees of the hue of the `primary` role.
  - `test_close_hues_are_separated`: with `primary` and `tertiary` 10 degrees apart, the hues of `a1` and `a2` differ by at least 40 degrees.
  - `test_grey_wallpaper_falls_back`: roles `{"primary": "#808080", "tertiary": "#808080"}` give an `a1` hue within 5 degrees of 195, and the same contrast floor holds (Review Focus 5).
  - `test_black_wallpaper`: roles all `#000000` give a valid palette meeting the contrast floor.
- [ ] **Step 2: Run to see them fail.** `python3 -m unittest tests.test_palette -v`. Expected: ImportError.
- [ ] **Step 3: Implement the four functions** with the OKLCH rules and numbers in spec section 5.4; nudge lightness in 0.01 steps until each contrast floor holds.
- [ ] **Step 4: Run the tests.** Expected: all PASS.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(palette): neon palette derivation with contrast guarantees"`.

### Task 17: `rice-palette` CLI and output writers

**Files:**
- Create: `dot_local/bin/executable_rice-palette`, `dot_local/share/rice/outputs.py`, `tests/test_outputs.py`

**Interfaces:**
- Consumes: `derive_palette`; the matugen JSON shape recorded in Task 1.
- Produces: `roles_from_matugen(doc: dict) -> dict[str, str]` (the `primary` and `tertiary` role colours as hex); `render_quickshell(tokens) -> str` (JSON), `render_kitty(tokens) -> str`, `render_hypr(tokens) -> str` (a `return { active = {...}, inactive = "..." }` Lua chunk), `render_btop(tokens) -> str`; CLI `rice-palette derive <image>` (prints the tokens as JSON, cached under `~/.cache/rice/<sha1 of file>.json`) and `rice-palette apply <image>` (derive, write the four files, send reloads, update `~/.local/state/quickshell/wallpaper.json`).

- [ ] **Step 1: Write the failing tests** in `tests/test_outputs.py`: `roles_from_matugen` on `tests/fixtures/matugen-berserk.json` returns two `#rrggbb` strings; each `render_*` contains every token's hex value; `render_quickshell` parses as JSON with exactly the eight keys; `render_hypr` output loads under `lua -e` and returns two active colours; a corrupt or non-image input makes the CLI exit non-zero without touching any output file (`test_apply_leaves_files_on_failure`, using a temp HOME).
- [ ] **Step 2: Run to see them fail.** Expected: ImportError.
- [ ] **Step 3: Implement the module and the CLI.** The CLI shells out to `matugen image <file> --json hex --dry-run -m dark -t scheme-vibrant` (flags as confirmed in Task 1), writes each output file atomically, then `pkill -USR1 kitty` and `hyprctl reload`. Reject files that are not images (check by `file --mime-type`) before calling matugen.
- [ ] **Step 4: Run the tests.** Expected: all PASS.
- [ ] **Step 5: Try it for real.** `rice-palette apply ~/Pictures/berserk-wallpaper.jpg`. Expected: bar, rail, window borders and any open kitty recolour; `hyprctl reload` reports no errors. View a `grim` screenshot and compare with the render.
- [ ] **Step 6: Commit.** `git add -A && git commit -m "feat(palette): rice-palette CLI and output writers"`.

### Task 18: Carousel

**Files:**
- Create: `dot_config/quickshell/wallpaper/Carousel.qml`
- Modify: `dot_config/quickshell/Theme.qml` (preview support), `shell.qml`

**Interfaces:**
- Consumes: `Theme.preview/clearPreview`, `rice-palette derive/apply`, `Chamfer`.
- Produces: `Carousel` overlay with an `IpcHandler { target: "carousel"; function toggle(): void }`. Lists images in `~/Pictures/wallpapers/` (`FolderListModel`, filters `*.png *.jpg *.jpeg *.webp`), five items visible with the selected one larger and `hot`-bordered, left/right moves (wrapping), each move calls `rice-palette derive <image>` through a `Process` and passes the tokens to `Theme.preview`; Enter runs `rice-palette apply <image>` and closes; Escape calls `Theme.clearPreview()` and closes.

- [ ] **Step 1: Seed the folder.** `mkdir -p ~/Pictures/wallpapers` and copy `~/Pictures/berserk-wallpaper.jpg` plus the three images in `/usr/share/hypr/` (`wall0.png wall1.png wall2.png`); ask the owner before copying more.
- [ ] **Step 2: Implement** the overlay to match the render, including the empty state ("no wallpapers in ~/Pictures/wallpapers") and the single-image case (no scrolling, still applies).
- [ ] **Step 3: Verify.** `Ctrl+Alt+W` opens it; left and right recolour the whole shell live; Escape restores the original colours and wallpaper; Enter persists (restart `qs-supervise`'s child and confirm the wallpaper and palette survive). Put a text file in the folder: it is not listed. Empty the folder: the empty state shows, no crash (Review Focus 5).
- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(shell): wallpaper carousel with live palette preview"`.

---

## Phase 6: Bluetooth and Claude limits

### Task 19: Claude limits parsing (`limits.py`)

**Files:**
- Create: `dot_local/share/rice/limits.py`, `dot_local/bin/executable_claude-limits-statusline`, `tests/test_limits.py`

**Interfaces:**
- Produces: `parse_rate_limits(payload: dict, now: float) -> dict` returning `{"five_hour": {"pct": float, "resets_at": int} | None, "seven_day": {...} | None, "updated_at": int}`; `render_line(data: dict) -> str`; `write_cache(path: str, data: dict) -> None` (temp file then `os.replace`). The executable reads stdin, writes `~/.cache/claude-limits.json`, prints `render_line`, and always exits 0.

- [ ] **Step 1: Write the failing tests** in `tests/test_limits.py`:
  - `test_both_windows`: payload `{"rate_limits": {"five_hour": {"used_percentage": 38.4, "resets_at": 2000000000}, "seven_day": {"used_percentage": 19, "resets_at": 2000100000}}}` with `now=1999990000` gives pct 38.4 and 19 and `render_line` `5h 38% · 7d 19%`.
  - `test_missing_rate_limits`: `{}` gives both `None`, `render_line` returns `""`.
  - `test_one_window_absent`: only `five_hour` present gives `7d` `None` and line `5h 38%`.
  - `test_expired_window_dropped`: `resets_at` earlier than `now` gives `None`.
  - `test_write_is_atomic`: `write_cache` leaves no `.tmp` file and the target parses as JSON.
  - `test_cli_bad_input`: running the executable with `not json` on stdin exits 0, prints nothing, and leaves an existing cache file byte-identical (Review Focus 4).
  - `test_cli_empty_stdin`: same for empty input.
- [ ] **Step 2: Run to see them fail.** `python3 -m unittest tests.test_limits -v`. Expected: ImportError.
- [ ] **Step 3: Implement the module and the thin executable.**
- [ ] **Step 4: Run the tests.** Expected: all PASS.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(limits): status line script that caches Claude usage limits"`.

### Task 20: Wire the status line (needs the owner's yes)

**Files:**
- Modify: `~/.claude/settings.json` (outside the repo)

- [ ] **Step 1: Ask the owner, and wait.** Say exactly: this adds a `statusLine` entry to `~/.claude/settings.json`; it reads only usage numbers, never the token; and Claude Code will hide most of its footer keyboard hints once a status line exists. If they decline, skip Tasks 20 and 21's Claude half; Bluetooth still ships.
- [ ] **Step 2: Back up and edit.** `cp -a ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d-%H%M%S)`, then add `"statusLine": {"type": "command", "command": "~/.local/bin/claude-limits-statusline"}` keeping every other key as it is. Validate with `python3 -c "import json;json.load(open('/home/vyrus-extreme/.claude/settings.json'))"`.
- [ ] **Step 3: Verify the data actually arrives.** Start a Claude Code session, send one message, then `cat ~/.cache/claude-limits.json`. Expected: a file with `five_hour` and `seven_day` objects. If the file has both as `null`, the plan does not report limits (upstream issue #45133 or plan type): tell the owner, remove the entry if they prefer, and drop the Claude widget.
- [ ] **Step 4: No commit** (the file is outside the repo). Note the outcome in the baseline notes and commit that: `git add docs && git commit -m "docs: record Claude status line outcome"`.

### Task 21: Bluetooth and Claude widgets

**Files:**
- Create: `dot_config/quickshell/rail/BluetoothWidget.qml`, `rail/ClaudeWidget.qml`
- Modify: `dot_config/quickshell/rail/Rail.qml`

**Interfaces:**
- Consumes: `Quickshell.Bluetooth` (`Bluetooth.devices`, `BluetoothDevice.connected`, `.name`, `.battery`, `.batteryAvailable`), `Meter` (battery uses `invert: true`), the cache file from Task 19.
- Produces: `BluetoothWidget` listing devices with `connected == true` (name, 5-cell battery and percent when `batteryAvailable`, otherwise name only; hidden when none); `ClaudeWidget` with a watching `FileView` on `~/.cache/claude-limits.json`, two segmented bars (`5H`, `7D`) with reset time and an age label, dimmed past 30 minutes, and "no data" when the file is missing, unparsable or has both windows `null`.

- [ ] **Step 1: Implement both widgets** to match the render and add them to the rail below the media widget.
- [ ] **Step 2: Verify Bluetooth.** Connect the AirPods: they appear with a battery level (or name only if BlueZ gives none; note which). Connect the DualSense: it appears. Disconnect both: the section hides.
- [ ] **Step 3: Verify Claude, and the failure cases (Review Focus 4).** With a real cache file the bars match `cat ~/.cache/claude-limits.json`. Delete it: "no data". Write `{garbage` into it: "no data", shell still running. Set `updated_at` 40 minutes into the past: bars dim.
- [ ] **Step 4: Re-run the memory checkpoint** from Task 12 (S1, S2) with the rail complete and record it.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(shell): Bluetooth and Claude limits rail widgets"`.

---

## Phase 7: Optional glitch

### Task 22: Glitch spike, then a go or no-go

**Files:**
- Create (spike, throwaway): `dot_config/quickshell/fx/GlitchSpike.qml`, `fx/glitch.frag`
- Create if go: `fx/Glitch.qml`, `fx/glitch.frag.qsb`

**Interfaces:**
- Produces (if go): `Glitch` overlay with `IpcHandler { target: "glitch"; function arm(): void; function play(): void }` and a `Theme`-side setting `glitchEnabled` (default false).

- [ ] **Step 1: Spike question.** Can a click-through Overlay `PanelWindow` capture a screen with `ScreencopyView` and distort it with a `qsb`-compiled `ShaderEffect` on this hybrid-GPU machine at a steady 60 frames for 250 ms? Compile `fx/glitch.frag` with `/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o fx/glitch.frag.qsb fx/glitch.frag`.
- [ ] **Step 2: Try it.** Show the overlay on demand with a static test image over a running window; confirm it covers windows, is click-through, and hides afterwards. Then capture the live screen and run the band-displacement, red/cyan channel offset and block-corruption passes over six staggered steps of 42 ms.
- [ ] **Step 3: Decide and record.** Go if the effect covers windows, plays without a visible stall, and idle memory and CPU are unchanged after it hides. No-go otherwise: delete the spike files, note the reason in the baseline notes, and skip Step 4. If only the pre-switch capture fails, ship the resolve-only half (spec section 8 fallback).
- [ ] **Step 4 (go only): Wire it.** `binds.lua` calls `qs ipc call glitch arm` immediately before each workspace dispatch and `qs ipc call glitch play` immediately after, only when `glitchEnabled` is true; add the toggle to the carousel or a key.
- [ ] **Step 5: Commit** whichever outcome: `git add -A && git commit -m "feat(shell): optional workspace-switch glitch"` or `git commit -m "docs: glitch spike result (dropped)"`.

---

## Phase 8: Verification and cleanup

### Task 23: Full acceptance run

**Files:**
- Modify: `docs/superpowers/notes/2026-10-23-baseline.md` (results table)

- [ ] **Step 1: Run S1 to S8** from the spec, each with the command and expected result named there, and record the actual numbers: RSS and CPU over 60 s, a before and after `hyprctl monitors -j` for S3, the full Super and Alt matrix for S4 (every row of both tables in spec section 6, in Firefox, VS Code and kitty), `python3 -m unittest discover -s tests -p 'test_*.py' -v` and `lua tests/lua/test_pools.lua` for S5 and the pure logic, both mouse buttons for S6, the lid test for S7, the kill-and-time test for S8.
- [ ] **Step 2: Fix or report** anything that fails. A criterion that cannot be met is reported as unmet with the number, not adjusted.
- [ ] **Step 3: Commit** the results: `git add docs && git commit -m "docs: acceptance results"`.

### Task 24: Documentation, memory, retirement of old configs

**Files:**
- Modify: `README.md`
- Delete (only after the owner confirms): `dot_config/waybar/`, `dot_config/wofi/`, `dot_config/hypr/hyprpaper.conf`, `dot_config/hypr/hyprland.conf`

- [ ] **Step 1: Update `README.md`:** the Contents table (Quickshell, xremap, kitty, matugen tools) and the keybinds table, replaced by the spec section 6 tables.
- [ ] **Step 2: Update the memory notes.** Rewrite `hyprland-workspace-model` (per-screen pools since 2026-10-23, superseding the nine shared workspaces), update `laptop-lid-headless-node` (`hyprland.conf` is now `hyprland.lua`, behaviour unchanged), and add a reference note for the new setup (where the pieces live, the key scheme, the unit-test commands). Keep `MEMORY.md` one line per note.
- [ ] **Step 3: Check the render page** at https://claude.ai/artifact/SGHt9bagiiej1rGiD5byXP still matches spec section 6 (it was corrected when the spec was written); fix any drift that implementation introduced.
- [ ] **Step 4: Ask the owner** whether they have lived with the new setup long enough to delete the retired configs. On yes, remove them in one commit and verify `chezmoi -S "$PWD" diff` is clean and the session still starts.
- [ ] **Step 5: Final commit and hand-off.** `git add -A && git commit -m "docs: README and cleanup after Quickshell migration"`, push the branch (never `main`), and tell the owner what to merge.
