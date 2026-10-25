# NVIDIA dGPU notes (U15)

The laptop has two GPUs: the AMD Cezanne iGPU (boot display) and an NVIDIA GeForce RTX
3050 Ti Mobile (vendor id 0x10de, 4 GB VRAM, driver `nvidia`, runtime power management
`auto`). This note records how the shell treats the NVIDIA card, what the memory
measurements say, and the decisions left to the owner.

## Power state seen on this machine (sysfs only, read-only)

- `power/runtime_status` of the NVIDIA PCI device read `suspended` at the start of U15
  (three reads 2 s apart), with `runtime_suspended_time` about 635,000 s against
  `runtime_active_time` about 9,900 s since boot. **The dGPU sleeps most of the time**:
  the session does not keep it busy, although the live Hyprland and hyprpaper hold
  `/dev/nvidia0` open (open device files do not stop the card from suspending).
- It read `active` while the test rig was running. See "What wakes the card" below.

### What wakes the card (rig, sysfs reads every 5 s)

| step | runtime_status |
|---|---|
| rig stopped | `active` for ~20 s, then `suspending`, then `suspended` |
| nested rig started (labwc + nested Hyprland, NVIDIA EGL loaded through glvnd) | `active` for ~20 s, then `suspended` |
| plus a small `qs` window on the default stack (Mesa EGL, RICE_NO_NVIDIA=1) | stays `suspended` for 40 s |

So starting a compositor wakes the card for about 20 s, and a Quickshell process on
the default stack does not. **At login the card is therefore probably `active` for the
first ~20 s, while the shell starts.** If the shell starts in that window, the NVIDIA
stream starts too and keeps the card awake for the whole session (owner decision 1).

## Part A: memory under the NVIDIA GL stack: SKIPPED

The brief allows the measurement only while the card is already `active`. At the
moment of measurement the card was `suspended` (it suspends whenever the rig is idle),
and starting any NVIDIA-stack client would have woken it, so the NVIDIA-stack
measurement was not run. nvidia-smi was never run (neither the one-off VRAM readings
nor anything else), so the shell's VRAM need is unmeasured.

What was measured without waking the card (a 400x300 Quickshell window with three
Rectangles and a Text, default stack, `tests/rig/qs-mem.py`, kB):

| | RSS | PSS | USS | anon |
|---|---|---|---|---|
| tiny qs, Mesa radeonsi | 402,616 | 168,420 | 108,380 | 92,024 |

| mapping (same process) | RSS | PSS | private |
|---|---|---|---|
| libLLVM.so (Mesa) | 99,776 | 21,399 | 2,168 |
| libnvidia-gpucomp.so | 77,212 | 17,519 | 2,832 |
| libgallium (Mesa) | 36,388 | 7,705 | 1,676 |
| libnvidia-glcore.so | 24,912 | 11,683 | 2,000 |
| libnvidia-eglcore.so | 20,764 | 5,510 | 1,752 |

Conclusions:
- Even on the AMD/Mesa stack, glvnd already loads the NVIDIA EGL/GL libraries into
  every Qt Quick process: about 123 MB RSS but only about 35 MB PSS and 6.6 MB private,
  because those pages are shared with every other GL process (the live Hyprland and
  hyprpaper map them too). The earlier U9 numbers (full shell ~620 MB RSS, ~345 MB PSS)
  already include them. Loading them does not wake the card.
- Comparable: the library mappings, since the same NVIDIA libraries are mapped either
  way. Not comparable: the NVIDIA driver's own heap and its per-context and per-window
  allocations, which only exist when NVIDIA renders. Those are unmeasured.
- Estimate for the real session (UNVERIFIED): if the shell rendered on NVIDIA, the
  Mesa libraries (~136 MB RSS, ~29 MB PSS) would drop out and NVIDIA driver heap would
  come in. A guess, not a measurement: the PSS total moves by tens of MB, not hundreds,
  and stays far above the 156 MB RSS budget either way. The budget problem is the GL scene graph, not the
  vendor. The real session's environment (`__GLX_VENDOR_LIBRARY_NAME=nvidia`,
  `GBM_BACKEND=nvidia-drm`) does not by itself make a Wayland EGL client render on
  NVIDIA: EGL picks the vendor through glvnd and the compositor's device, so a qs
  started from this Hyprland may well stay on the iGPU. The 4 GB VRAM is not the
  constraint: the budget is system RAM.
- The NVIDIA stream itself adds one `nvidia-smi` process (it loads libnvidia-ml; its
  RSS is unmeasured here, typically a few tens of MB) and keeps the card powered.

## Final behaviour (Stats.qml, SysWidget.qml)

- `Stats.gpuSource` is `"nvidia"`, `"amd"` or `"none"`; `Stats.gpu` (0-100, -1 when
  unknown) keeps its meaning. New: `vramUsedMb`, `vramTotalMb` (MiB) and `vramPct`
  (0-100), all -1 when unknown.
- At start Stats reads only the `vendor` file of `/sys/class/drm/card0..15/device` and
  remembers the first AMD card (0x1002) and the first NVIDIA card (0x10de).
- NVIDIA is tried once, after that probe, only when the NVIDIA card's
  `power/runtime_status` reads exactly `active` (reading it never wakes the card). Then
  ONE long-lived process runs:
  `setpriv --pdeathsig TERM -- nvidia-smi -l 2 --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits`.
  Every line updates `gpu` and the VRAM values. `gpuSource` becomes `"nvidia"` at the
  first valid line. Lines with `[N/A]`/`[Not Supported]` fields, extra columns, stray
  whitespace or a decimal comma are handled. A line with no number at all does not count.
- `setpriv --pdeathsig TERM` (util-linux) makes the kernel stop nvidia-smi when the shell
  dies, even on SIGKILL. Quickshell 0.3.1 does NOT kill running children when it exits
  on SIGTERM (seen in the rig: a child was reparented to init), and
  `Component.onDestruction` does not run then either.
- Fallback to the AMD sysfs file (`gpuSource = "amd"`; `"none"` and `gpu = -1` without
  an AMD card) when the card is not `active` (no process is started at all), when
  nvidia-smi is missing (exit 127 from setpriv; one info line, no warning), when it
  exits before a valid line (one warning, no retry), or when no valid line arrives
  within 6 s (one warning, the process is stopped, no retry).
- A stream that dies after valid lines falls back to AMD (VRAM values back to -1) and is
  retried after 30 s, 60 s, 120 s, then every 300 s, each time only if
  `runtime_status` still reads `active` (otherwise nothing is started and the next step
  is waited). The steps start over only after a stream that lasted at least 300 s, so a
  stream that keeps dying backs off. One warning per failure kind, ever.
- All timing (start timeout, retries) runs on the existing shared 2 s timer; there is no
  new timer and no process per tick.
- Rail SYS section: the `GPU` row shows `Stats.gpu` as before and is hidden when
  `gpuSource` is `"none"` (or the value is unknown). While `gpuSource` is `"nvidia"` a
  `VRM` row follows (10 segments from `vramPct`, text like `1.5/4.0G`, `--` when
  unknown), and the value column of all rows widens to fit that text so the bars stay
  aligned. The rail column is about 210 px of 1042 px at 1080p with the VRM row, so no
  spacing change was needed.
- `RICE_NO_NVIDIA` set to any non-empty value skips NVIDIA entirely. The test rig sets
  it by default (`tests/rig/rig_env.sh`) so no test ever runs the real nvidia-smi; the
  NVIDIA tests use a FAKE nvidia-smi (`tests/rig/fake-nvidia-smi.sh`, selftest-qs.sh
  section 11).

## Owner decisions

1. **The NVIDIA stream keeps the dGPU awake while the shell runs.** nvidia-smi polling
   every 2 s stops the card from runtime-suspending. The brief assumed this is free
   because the session already uses the card, but the counters above show the card is
   suspended most of the time, so this probably costs battery whenever the shell starts
   while the card happens to be awake. To keep the dGPU free to suspend, use the AMD
   source only. Either:
   - add `hl.env("RICE_NO_NVIDIA", "1")` to `dot_config/hypr/hyprland.lua` (no QML
     change), or
   - change `readonly property bool nvAllowed: ...` in
     `dot_config/quickshell/services/Stats.qml` to `readonly property bool nvAllowed: false`.
   With either, the GPU row shows the AMD iGPU's load and there is no VRM row.
2. **Memory.** The NVIDIA-stack measurement was skipped (card asleep; see Part A). The
   NVIDIA libraries are already mapped, and already counted, in the AMD-stack numbers
   (~35 MB PSS, shared). Vendor choice will not bring the shell near 156 MB RSS; only a
   lighter renderer (U9: `QT_QUICK_BACKEND=software`, ~203 MB PSS) or fewer features
   would. The NVIDIA stream adds one nvidia-smi process on top.
