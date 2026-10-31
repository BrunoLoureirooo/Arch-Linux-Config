# Workspace-switch glitch: spike result (NO-GO, dropped)

Plan Task 22, spec section 8. Date: 2026-10-25. Measured in the headless nested
Hyprland rig (`tests/rig/full.lua`, staged HOME, private D-Bus). In the rig, qs renders
on the real AMD iGPU through radeonsi.

## Question

Can a click-through overlay on the Overlay layer do the following on a workspace change,
with no stall and no idle cost?

1. Capture the screen with `ScreencopyView`.
2. Distort it for about 250 ms with a `qsb`-compiled `ShaderEffect`.
3. Cover the windows.

## What the spike was

All of it was throwaway. It was deleted after the decision, and nothing from it is in the repo.

- **`fx/glitch.frag`** (GLSL 440, compiled with
  `/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12`, rc 0). The effects:
  - nine hash-jittered horizontal bands, displaced sideways by `amp`;
  - at high amp, a band may be inverted, red-only or cyan-only;
  - red and cyan ghost copies offset by `ghost`, screen-blended;
  - hash-grid corrupted blocks, either colour-inverted or 6 px saturated noise.

  Every random value derives from `seed`, so a given frame is reproducible.
- **`fx/Glitch.qml`**: one `PanelWindow` on the focused screen with these settings:
  - `WlrLayer.Overlay`, all anchors, `ExclusionMode.Ignore`;
  - `mask: Region {}`, keyboard focus None;
  - namespace `rice-glitch`, hidden at rest.

  It holds two `ScreencopyView`s (old and new, `live: false`, `captureSource` null at rest).
  Each feeds a `ShaderEffectSource { hideSource: true }`, and that is the shader's `source`.
  It plays the render's `FR` table (six steps, 42 ms `Timer`, 1 em = 1/120 of the screen
  width) and exposes `IpcHandler { target: "glitch"; arm(); play(); enable(); disable() }`.
  - `arm()` captures the old frame.
  - `play()` captures the new frame and starts the steps when it is ready.
  - Without an armed frame, only frames 4 to 6 play (the spec's fallback).
- **`tests/rig/glitch.qml`**: a probe config. It sets a fixed seed and
  `RIG_GLITCH_STEP_MS`, which freezes each step for screenshots. It logs a timestamp at each step.

API findings (Quickshell 0.3.1):
- A `ScreencopyView` cannot be used directly as a `ShaderEffect` source. Both
  `visible: false` and `opacity: 0` gave an all-black texture. A
  `ShaderEffectSource { sourceItem: view; hideSource: true }` works.
- `hasContent` resets when `captureSource` goes back to null, so it signals readiness
  reliably on every play. In the measurement runs, all 81 of 81 plays completed.

## GO criteria (all had to hold)

| # | criterion | measured | result |
|---|-----------|----------|--------|
| 1a | above every window | Mid-effect screenshots show a full-screen rig kitty torn into displaced bands, with inverted and single-channel bands, red/cyan ghosts and noise blocks. This held over the old frame (kitty to empty workspace) and over the new frame (empty workspace to kitty). | pass |
| 1b | click-through | Setup: two kitties tiled on one workspace, B focused. With the overlay up (step 3 frozen), a virtual-pointer click on A made A the active window, and the typed keys landed in A's file (`typedA='z '`, `typedB=''`; wtype's first key per run is lost, a known rig effect). **Control:** the same overlay without `mask` kept B active, and the keys went to B. So the check is not vacuous. | pass |
| 1c | gone afterwards | After every play, `hyprctl layers` showed 0 `rice-glitch` layers. The probe reported `visible:false`. | pass |
| 2 | six steps, no stall | 10 plays at 42 ms (60 intervals): min 41, max 46, mean 42.7 ms, all within 22..62. A further 20 plays (120 intervals) gave the same min/max/mean. Old-frame capture was ready 14-41 ms after `arm`, new-frame capture 3-22 ms after `play`. | pass |
| 3 | idle cost unchanged after hide | **CPU:** 0 ticks per 30 s before and after (unchanged). **RSS:** not unchanged; numbers below. | **FAIL** |
| 4 | off by default, free when off | Not built (the binds wiring was GO-only). The design was a flag file checked with `io.open` in binds.lua, so no process would spawn while it is off. | n/a |

### Criterion 3 numbers (RSS kB, from `/proc/<qs>/smaps_rollup`, anon = Anonymous)

Probe config (Glitch only):

| state | RSS | anon | file |
|---|---|---|---|
| fresh | 351,108 | 53,156 | 297,952 |
| after 1 play | 395,152 | 86,880 | 308,272 |
| after 21 plays | 415,264 | 106,992 | 308,272 |
| after 41 plays | 438,028 | 129,756 | 308,272 |
| after 61 / 81 / 101 plays | 436,928 / 436,120 / 438,244 | ~129,000 | 308,272 |

Production `shell.qml` plus `Glitch {}`, compared with production `shell.qml` alone. Both
did the same Ctrl+1/Ctrl+2 workspace switches every 0.5 s:

| | start | after 80 switches | after 160 switches |
|---|---|---|---|
| shell + glitch (arm, switch, play) | 562,208 | 612,592 (+50 MB) | 611,616 (+49 MB) |
| shell alone (switch only), control | 549,916 | 558,208 (+8 MB) | 553,240 (+3 MB) |

The growth stops at a plateau after about 40-80 plays, so it is not a linear leak. It is
also never given back: a 30 s idle sample after the plays stayed flat at the higher value.
In the real shell, that is about **+45 MB retained** above the ±5 MB noise of the control.
Most of it is anonymous memory. The shell is already far over its 156 MB budget (U9), and
this would add a further retained ~8 % for an ornamental effect.

That is not "within noise of before", so criterion 3 fails. The decision rule says all
criteria must hold, so the result is NO-GO.

### Where the cost comes from (bisected; each row is a fresh qs, probe config)

| variant | fresh to plateau (RSS) |
|---|---|
| full effect (two ShaderEffectSources) | 351 → ~437 MB |
| one non-live ShaderEffectSource, `scheduleUpdate()` per capture, `gc()` after | 354 → ~440 MB (no change) |
| full effect with `MALLOC_ARENA_MAX=1` | 354 → ~436 MB (not glibc arenas) |
| full effect with fixed glibc `mmap_threshold`/`trim_threshold` 128 KiB | 354 → ~437 MB (not freed heap that glibc keeps) |
| captures only (no ShaderEffect, no ShaderEffectSource) | 353 → ~377 MB (+24 MB once, then flat) |
| persistent hidden window instead of a LazyLoader window per play | same plateau as LazyLoader |

The captures alone cost about 24 MB once. The rest, about 60 MB in the probe, comes from
rendering the captures through ShaderEffectSource and ShaderEffect. It looks like
driver-side (Mesa/radeonsi) anonymous memory that fills up to a cap. The shape fits:
- the plateau has many fully resident 4 MB anonymous mappings;
- glibc tuning had no effect.

Even the resolve-only fallback uses the same render path, so it would not avoid the cost.

## Other findings

- **Pre-switch capture latency.** A `qs ipc call` process takes about 44 ms, measured with
  the rig wrapper, and the old capture needs another 14-41 ms. So binds.lua would have to
  delay every workspace dispatch by about 60-90 ms (`hl.timer`) for the old frame to be
  correct. Otherwise only the resolving half is reliable.
- **Cursor in captures.** The rig's software cursor appears in the captures (red/cyan ghost
  cursors), even with `paintCursor` at its default of false. On hardware with a cursor
  plane this probably does not happen (unverified).
- **Screens.** One overlay was used, on the focused screen only, because workspaces are
  per screen. Tearing the unchanged screen would be wrong.

## Screenshots (outside the repo: `.superpowers/sdd/2026-10-23-quickshell-terminal-desktop/shots/u13/`)

- `b-before.png`: the full-screen rig kitty with 45 coloured text lines.
- `b-step1.png`: old frame, amp 6. Bands are shifted sideways with red/cyan ghost text, one band is inverted (white), and there are small noise blocks.
- `b-step2.png`: old frame, amp 13. Large band offsets, doubled and tripled ghost text, white blocks, an inverted band at the bottom.
- `b-after.png`: the empty dark workspace, with no overlay left.
- `c-step3.png`: new frame (the kitty workspace). Strong tear, two inverted bands, noise blocks.
- `c-step5.png`: new frame, amp 1.4. A light jitter with thin colour fringes.
- `c-after.png`: the clean kitty.
- `a-step2.png`, `op-step1.png`: failed variants (view used directly as the source), all black apart from blocks and inverted bands. They are kept as evidence for the API finding.
- `clickthrough-during.png`: the frozen overlay at the moment of the click.

## What a GO would need

One of these:
- **(a)** The owner explicitly accepts about +45 MB of retained RSS once the effect has been
  used; it stays bounded and costs no CPU.
- **(b)** A way to release the render path's driver memory after each play. Untested ideas
  to try later:
  - `QQuickWindow::releaseResources()`, or `persistentGraphics: false` / `persistentSceneGraph: false` on the overlay window (not exposed by Quickshell's `PanelWindow` today);
  - rendering into a smaller `textureSize`;
  - a CPU-side distortion of a downscaled capture without a ShaderEffect.

If that comes back, the spike design above (flag file, empty mask, two captures,
ShaderEffectSource) works as is. The pre-switch delay of about 60-90 ms also needs a
decision, or the resolve-only half should be used.

## Owner decision note

The effect is dropped. Nothing else depends on it. The DOM tear in
`docs/superpowers/design/cyber-terminal-rice.html` stays a mock only. No glitch overlay,
shader, IPC target or bind exists in the shell.
