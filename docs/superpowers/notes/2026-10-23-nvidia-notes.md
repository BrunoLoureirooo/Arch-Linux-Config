# NVIDIA dGPU notes (U15)

The laptop has two GPUs: the AMD Cezanne iGPU (boot display) and an NVIDIA GeForce RTX
3050 Ti Mobile (vendor id 0x10de, 4 GB VRAM, driver `nvidia`, runtime power management
`auto`). This note records how the shell treats the NVIDIA card, what the memory
measurements say, and the decisions left to the owner.

**Default: the rail's GPU row reads the AMD iGPU** (the chip that drives the display).
The NVIDIA source is opt-in with `RICE_NVIDIA=1` (see "Owner decisions").

## Power state seen on this machine (sysfs only, read-only)

- On 2026-10-25 at 01:41:48-01:41:52 WEST, three reads 2 s apart of the NVIDIA PCI
  device's `power/` files gave: `runtime_status` = `suspended`, `control` = `auto`,
  `runtime_suspended_time` = 634,941,149 ms (then 634,943,154 and 634,945,159),
  `runtime_active_time` = 9,897,830 ms (unchanged). That is about 176 h suspended
  against 2.7 h active since boot: **the dGPU is suspended about 98.5 % of the time.**
- Corrected premise: the U15 brief assumed the session already keeps the dGPU awake
  (because the Hyprland config sets the NVIDIA GLX/GBM variables), so an nvidia-smi
  stream would cost nothing. It does not. The session barely uses the dGPU, and a
  permanent stream would hold it awake all session for a GPU row reading about 0 %.
  Hence the AMD default and the opt-in.
- The live Hyprland and hyprpaper hold `/dev/nvidia0` open and the card still
  suspends: open device files do not stop runtime suspend, but nvidia-smi/NVML polling
  does.
- It read `active` while the test rig was running. See "What wakes the card" below.

### What wakes the card (rig, sysfs reads every 5 s)

| step | runtime_status |
|---|---|
| rig stopped | `active` for ~20 s, then `suspending`, then `suspended` |
| nested rig started (labwc + nested Hyprland, NVIDIA EGL loaded through glvnd) | `active` for ~20 s, then `suspended` |
| plus a small `qs` window on the default stack (Mesa EGL, NVIDIA source off) | stays `suspended` for 40 s |

So starting a compositor wakes the card for about 20 s, and a Quickshell process on
the default stack does not. **At login the card is therefore probably `active` for the
first ~20 s, while the shell starts.** With the opt-in set, the stream would start in
that window and keep the card awake for the whole session.

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
- **Default (no `RICE_NVIDIA`, or any value other than `1`):** the GPU row uses the AMD
  sysfs file (`gpuSource = "amd"`, `"none"` without an AMD card). No NVIDIA process is
  ever started and nothing of the NVIDIA card but its `vendor` file is read.
- **With `RICE_NVIDIA=1`:** NVIDIA is tried once, after that probe, only when the NVIDIA card's
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
- Tests: the NVIDIA tests set `RICE_NVIDIA=1` explicitly and use a FAKE nvidia-smi
  first on PATH (`tests/rig/fake-nvidia-smi.sh`, selftest-qs.sh section 11).
  selftest-qs.sh unsets `RICE_NVIDIA` at its top, so an opted-in session cannot make
  the other sections run the real nvidia-smi. Section 11 also checks that without the
  opt-in (unset, or `0`) no fake is ever started, even with `runtime_status` `active` and
  the fake on PATH.

## Owner decisions

1. **To show your 3050 Ti in the rail, add `hl.env("RICE_NVIDIA", "1")` to your Hyprland
   config** (`dot_config/hypr/hyprland.lua`, next to the other `hl.env` lines). It will
   keep the dGPU awake while the shell runs (nvidia-smi polling every 2 s stops runtime
   suspend), but only if the card is awake when the shell starts; a sleeping card is
   never woken. You get a `VRM` row as well. **The default is AMD because the session
   barely uses the dGPU** (suspended about 98.5 % of the time, see above).
   Careful: a terminal opened in a session with that setting passes `RICE_NVIDIA=1` on
   to anything started from it, including manual `tests/rig/qs-run.sh` runs (the
   selftest unsets it).
2. **Memory.** The NVIDIA-stack measurement was skipped (card asleep; see Part A). The
   NVIDIA libraries are already mapped, and already counted, in the AMD-stack numbers
   (~35 MB PSS, shared). Vendor choice will not bring the shell near 156 MB RSS; only a
   lighter renderer (U9: `QT_QUICK_BACKEND=software`, ~203 MB PSS) or fewer features
   would. The NVIDIA stream adds one nvidia-smi process on top.

## Separate finding: Quickshell SystemClock and the autumn DST change (not fixed here)

- What: during the repeated hour after the autumn clock change, Quickshell 0.3.1's
  `SystemClock` floods the log with
  `WARN: QTimer::start: negative intervals aren't allowed; the interval will be set to 1ms.`,
  about 2,200 lines/s, with qs at about 30 % CPU.
- How it was seen: on 2026-10-25 the local clock (Europe/Lisbon) went from 02:00 WEST
  back to 01:00 WET in the middle of a `tests/rig/selftest-qs.sh` run. From then on
  every qs log filled with that warning. Section 10 and six section 11 "no WARN" checks
  failed, although a section 11 run before 02:00 had passed with no warnings. At
  01:0x WET a fresh production `shell.qml` in the rig (`tests/rig/qs-run.sh start`) logged
  6,516 such lines after 3 s and 28,520 after 13 s (`qs-run.sh log | grep -c`), and
  `top -b -n 2 -d 3 -p <qs pid>` showed 29.5 % CPU. A full rerun at 02:01 WET
  passed with no warnings.
- Where: the only `SystemClock` users are `dot_config/quickshell/bar/Bar.qml` (line ~50)
  and `dot_config/quickshell/rail/ClockWidget.qml` (line ~17), both
  `precision: SystemClock.Minutes`. Their next-minute timer evidently computes a
  negative interval while local time repeats.
- Impact: once a year, for one hour, the live shell burns CPU and grows its log, and
  any selftest run in that hour fails. The final fix wave should replace these
  `SystemClock`s (for example with a plain `Timer` re-armed from `Date` arithmetic in
  UTC milliseconds), then re-check with a faked clock.
