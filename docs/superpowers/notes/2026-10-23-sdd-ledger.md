# SDD ledger — plan: docs/superpowers/plans/2026-10-23-quickshell-terminal-desktop.md

Spec: docs/superpowers/specs/2026-10-23-quickshell-terminal-desktop-design.md (binding authority).
Worktree: /home/vyrus-extreme/.local/share/chezmoi/.claude/worktrees/quickshell-rice-spec
Branch: feat/quickshell-terminal-desktop (fresh from origin/main c7478dd; spec+plan cherry-picked as c8eb630, 26fb0d5)
Mode: unattended night run. Owner is away; no questions, no permission stops. Deliverable: DRAFT PR at the end.
WARNING for all workers: `.superpowers/` is NOT git-ignored. Never `git add -A` / `git add .`; add explicit paths only.

## Environment facts (checked 2026-10-23 ~19:00)
- sudo needs a password (sudo -n fails) -> no system installs possible.
- gh authenticated as BrunoLoureirooo (ssh). Draft PR is possible.
- quickshell 0.3.1, matugen 4.2.0, wev, wtype not installed. Their packages (plus libdwarf, cpptrace, qt6-wayland) can be downloaded from the mirror via `pacman -Sp` URLs and extracted into a private prefix (no root).
- grim, slurp, bsdtar, curl, zstd, lua, luajit, python3.14, qt6-shadertools present. aquamarine 0.15.1, hyprland 0.56.2.
- A LIVE Hyprland session is running (owner's desktop). Workers must never touch it.

## Rulings (made before execution)
- Ruling: No live-system changes. No `chezmoi apply` into $HOME, no writes under ~/.config, no session restart, no sudo/pacman/yay, no edit of ~/.claude/settings.json, no deletion of retired configs (waybar/wofi/hyprpaper/hyprland.conf stay). — The owner said not to stop, not that destructive/security-sensitive actions are pre-approved; they are also impossible (no sudo) or would risk the owner's session and this job. — Cost if wrong: owner runs a short deploy checklist (written in docs) instead of finding it deployed.
- Ruling: Plan steps that are ask-first gates (Task 0 step 4, Task 3 step 5, Task 6 step 3, Task 13 step 2, Task 20, Task 24 step 4) are NOT executed; each is rewritten as an item in `docs/deploy.md` (owner follow-ups) and in the PR description. — see above. — Cost: none beyond owner effort.
- Ruling: Runtime verification uses a private test rig, not the live session: binaries extracted to ~/.cache/rice-testbin (outside the repo), a HEADLESS nested Hyprland (AQ_BACKENDS=headless, own instance signature, virtual outputs) and Quickshell run against it, driven with wtype and hyprctl -i, screenshots with grim. Rig scripts live in the repo under tests/rig/ and must refuse to run against the live instance signature. — gives real screenshots and bind tests without disturbing the desktop. — Cost: if headless nested Hyprland cannot work, runtime checks are reported UNVERIFIED instead.
- Ruling: Anything that cannot be exercised in the rig (physical mouse side buttons, xremap against real devices, lid switch on the live session, AirPods battery, Claude Code status line in a real session) is reported UNVERIFIED in the PR with exactly what was and was not run. Mouse codes default to 275/276 (plan's expectation).
- Ruling: Ask-first gates in the plan's Review Focus tests stay as tests but run in the rig (dock unplug = `hyprctl output remove` on a headless output, not the owner's real monitor).
- Ruling: Task 4's `tests/tools/uinput_keys.py` also exposes a CLI (`python3 uinput_keys.py KEY KEY ...` calls press(*argv[1:])) because tests/hypr/check_pools.sh calls it that way (the plan's Interfaces block only named press()). In the rig, key injection uses wtype against the nested compositor; uinput_keys.py is kept for the live-session case and for owner use.
- Ruling: check_pools.sh and other hyprctl-using tests take the target instance from HYPRLAND_INSTANCE_SIGNATURE set by tests/rig/rig_env.sh and abort if it equals the live signature recorded at rig setup.
- Ruling: Dispatch order is strictly sequential per the skill (shared files hyprland.lua, shell.qml, Rail.qml). Work packages (units) group plan tasks that share a review surface. Models: opus for rig/integration/QML work, sonnet for pure-logic Python/Lua and docs, reviewers sonnet (opus for QML-heavy diffs), final review fable.
- Ruling: Task 22 (glitch) runs as a time-boxed spike only if the rig can run Quickshell with ScreencopyView; go/no-go recorded; default OFF either way.
- Ruling: `git push` of the feature branch and opening a DRAFT PR against main are explicitly requested by the owner; nothing is pushed to main, nothing merged.

## Pre-flight conflict scan (table)
| Pair / task | What one produces vs other consumes | Finding |
|---|---|---|
| T2 -> T4 | pools.lua: ws_id, pool_for, slot_of, step | consistent; T4 uses all four |
| T3 -> T4 | both edit hyprland.lua; T4 requires binds and replaces old binds | consistent; T3 keeps old binds until T4 |
| T3 <-> T17 | colors.lua shape {active={..}, inactive=".."} | consistent with render_hypr |
| T4 <-> T5 <-> T6 | binds.lua strings vs xremap outputs | T5 red until T6; both need binds.lua (T4) first |
| T4 step 2 vs Interfaces | check_pools.sh calls uinput_keys.py as CLI; plan only specifies press() | Ruling above: add CLI wrapper |
| T4 steps 6-8 | require live session | Ruling: run in nested rig |
| T6 <-> T13/T14 | all edit hyprland.lua autostart | additive; order T6, T13, T14 fine |
| T8 -> T9..T21 | Theme singleton API (colors, font, px, preview/clearPreview) | consistent |
| T10 -> T12 | Stats fields cpu, memGb, memPct, gpu | consistent |
| T11 <-> T17 <-> T18 | wallpaper.json shared; apply writes it; carousel calls apply | consistent |
| T12 -> T21 | Rail.qml extended by T21 | additive |
| T15/T18 <-> T4 | bind commands `qs ipc call launcher|carousel toggle` vs IpcHandler targets | consistent |
| T16 -> T17 -> T18 | derive_palette -> CLI derive/apply -> Process in carousel | consistent |
| T19 -> T21 | cache keys five_hour/seven_day {pct, resets_at}, updated_at | consistent |
| T22 | binds.lua + Theme glitchEnabled | optional, last |
| Global "no animation" vs T22 | glitch is declared exception | consistent |
| T0..T24 each (self-consistency) | tests vs code vs files | T3 step 5, T6 step 3, T13 step 2, T20, T24 step 4 are ask-first gates -> rulings above; no other self-contradictions found |

## Todo / progress
(append `Task <N>: complete ...` lines below; units list)
Units: U0 rig+spikes(T0,T1) | U1 T2 | U2 T3+T4 | U3 T5+T6+T7 | U4 T16 | U5 T17 | U6 T19(+T20 doc) | U7 T8+T9 | U8 T10 | U9 T11+T12 | U10 T13+T14+T15 | U11 T18 | U12 T21 | U13 T22 | U14 T23+T24 | FINAL review | integrate | push+draft PR

## Execution log
- U0 implementer (opus, agent a87f895d672adc7ee): DONE_WITH_CONCERNS, commit 5299fec (BASE 26fb0d5). Rig works: headless nested Hyprland inside a private headless labwc, grim, wtype, Quickshell renders, ScreencopyView works, 9 modules import. selftest passes. Report: briefs/u0-report.md. Review dispatched (agent acb32be2fbdd4d857).
- Ruling: live ~/.config hypr/hyprpaper/waybar configs were ahead of the repo (3 files differ: hyprland.conf, hyprpaper.conf, waybar config.jsonc). Synced live -> repo in commit 88a1c01 BEFORE any port work. — a chezmoi apply from the old repo copy would have reverted the lid/headless binds, BenQ desc match, movewindow, app binds. — Cost if wrong: one extra commit to revert; the owner's live files are untouched (copy was live -> repo only).
- Ruling: later units must port from the live-synced repo files (now in dot_config/hypr/hyprland.conf), not the plan's description of the old stub. Notably: lid/headless binds, `desc:BNQ BenQ EX2510S K8M02386019` monitor, `XDG_MENU_PREFIX`, `Super+Tab focusmonitor`, app binds `Super+E` -> `kitty -e yazi`, `Super+Space` wofi (to be replaced).
- Ruling: rig shares live D-Bus/PipeWire/BlueZ. Units that start a NotificationServer or touch audio/Bluetooth state must use a private session bus (`dbus-run-session`) in the rig and must not stop mako or any live process. U10 (toasts) gets this in its brief.
- Minor (deferred): U0 commit trailer says "Claude Opus 5.5" (subagent's own identity) vs Sonnet 5.5 requested; left as is (history rewrite not worth it).
- Minor (deferred): three stale instance dirs from early U0 runs in /run/user/1000/hypr (clear on reboot).
- U0 review (sonnet, acb32be2fbdd4d857): spec compliant; 1 Important: stale nested.env PID could make `stop` SIGTERM an unrelated same-uid process (nested-hypr.sh kill_all/cmd_stop/is_running). Fix round 1/5 dispatched to the original implementer (FIX_BASE 88a1c01), also asked for a regression test in selftest.sh.
- U0 minors (deferred): live.sig can go stale (refresh at start); orphan labwc if nested.env deleted; no committed regression tests for live-sig/empty-sig/double-start guards (only the stale-PID one is requested now); downloads unverified by checksum (private prefix, test-only); hypr_cmd quoting breaks on a path with a single quote; selftest uses fixed sleeps; rig_die exits an interactive shell if rig_env.sh is sourced by hand; baseline section does not compare to spec figures (measured waybar 80404 KiB, mako 25776 KiB, hyprpaper 53848 KiB).
Task U0 (Tasks 0,1): complete (commits 26fb0d5..2d4487a incl. controller sync 88a1c01; review clean after fix round 1/5)
Task U1 (Task 2): complete (commits 2d4487a..ba72ab6, review clean, sonnet implementer aa28cdbb3b4d94e22, reviewer a672507909c63ffa6)
- U1 minors (deferred): pool_for with name=nil raises (Hyprland always supplies names); BenQ prefix match shares pool 0 with any second "BNQ BenQ" model (spec-prescribed); slot_of non-integer ids; no test that seeing BenQ/panel first leaves later unknown monitor at pool 2 (code does behave so).
- U2 implementer (opus, a8053321487250905): DONE_WITH_CONCERNS, commits 7592105 fa2f1f4 c25a9dc (BASE ba72ab6). Rig: verify-config ok, check_pools 23/23, dock scenario ok, 48 binds registered. Decisions: pcall(require,"colors") with seed fallback; workspace 11 default on eDP-1. Concerns: Super+Space calls qs ipc (no launcher until U10); SUPER+grave may not fire on pt (dead_grave; code:49?); waybar all-outputs shows both pools on both bars; bare mouse 275/276 steal browser back/forward (spec-intended). Review dispatched (opus, a4e85661c7222e4a4).
- Ruling: Super+Space -> qs ipc before the launcher exists is accepted; nothing is deployed until the owner applies the whole branch (docs/deploy.md will say apply all phases together).
- U2 review (opus, a4e85661c7222e4a4): Needs fixes. Important: (1) binds.lua pool binds not nil-safe (get_active_monitor / active_workspace may be nil: lid closed w/o external monitor); (2) `SUPER + grave` cannot fire on pt layout (dead_grave) — plan-mandated.
- Ruling: Super+` is replaced by `SUPER + code:49` (physical key under Esc) — the spec's intent is "the key under Esc", not the grave keysym; pt layout produces no grave keysym there. Docs reworded repo-wide in the fix round. — Cost if wrong: if code:49 is not the key under Esc on the owner's keyboard, one number to change (checkable with wev).
- U2 fix round 1/5 dispatched to the original implementer (FIX_BASE c25a9dc), with a required nil-safety test.
- U2 minors (deferred): Super+Space before the launcher exists (accepted, all-phases-at-once deploy); ws 11 also default on eDP-1 (beyond live rule, justified; owner to ack in PR); stepping from a foreign-pool workspace after unplug jumps to slot 1+/-1 and is untested after unplug; Ctrl+Shift+3 tested on mons[1] only; expected ids computed by code under test (arithmetic covered by test_pools.lua); M.pool_of(unknown) errors (tests only); waybar interim: all-outputs true shows both pools on both bars, persistent map keyed by connector name; bare mouse 275/276 take browser back/forward (spec-intended, mention in PR).
Task U2 (Tasks 3,4): complete (commits ba72ab6..29885b8, review clean after fix round 1/5)
- TODO for docs unit: render page (artifact) text still says Super+`; change to 'Super + the key under Esc (code:49)'.
- U3 implementer (sonnet, aee5039ae19bf852f): DONE_WITH_CONCERNS, commits 9e3a0c1 32ced54 ffd8f0c (BASE 29885b8). Collision tests RED->GREEN (7 OK), full discover 18 OK, private xremap --validate-config "Config is valid", kitty parsed via `kitty +runpy load_config` (no --debug-config in 0.48.2). color8 set to #7480ad (dim token 4.33:1). xremap started without --watch. Review dispatched (sonnet, aea7be560424b7b18).
- Note: plan task briefs live in .superpowers/sdd/<plan>/task-N-brief.md (workspace root), NOT in briefs/; later dispatches use absolute paths.
Task U3 (Tasks 5,6,7): complete (commits 29885b8..ffd8f0c, review clean first pass, reviewer aea7be560424b7b18)
- U3 minors (deferred): test_no_collisions alone passes on an empty bind set (sentinel test covers it); _remap_pairs ignores non-flat YAML (comment says keep flat; spec-table test catches a dropped entry); xremap without --watch (hot-plugged keyboard not remapped until restart) and silent failure without input group -> owner follow-ups in docs/deploy.md; Super+Up/Down -> Ctrl+Home/End per spec.
- U4 implementer (sonnet, aed2b474a2d1948eb): DONE_WITH_CONCERNS, commit a7991ed (BASE ffd8f0c). 11 palette tests OK, full discover 29 OK. NOT YET REVIEWED (usage limit reached). Concerns: fallback hue rules, lightness only nudges up (bounded 100 steps then ValueError), only primary/tertiary validated, untested against real matugen output.
- STOPPED: usage limit reached after U4 implementation. Remaining: U4 review, U5-U14, final review, integration validation. Briefs for U4/U5/U6 and qml-common.md are written under briefs/ (untracked workspace); U7-U12 briefs not yet written.
