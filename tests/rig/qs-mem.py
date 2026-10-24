#!/usr/bin/env python3
"""Memory breakdown of one process (read-only, /proc only): qs-mem.py <pid> [top-n]

Prints RSS / PSS / USS and the anonymous vs file-backed split from smaps_rollup, then
the mappings grouped by kind (libraries by name, GPU/DRM buffers, memfd/shm, heap and
anonymous) and sorted by RSS, with their PSS and private (USS) share. kB throughout.
"""
import collections
import re
import sys

pid = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 15


def fields(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"^(\w+):\s+(\d+) kB", line)
        if m:
            out[m.group(1)] = out.get(m.group(1), 0) + int(m.group(2))
    return out


roll = fields(open(f"/proc/{pid}/smaps_rollup").read())
uss = roll["Private_Clean"] + roll["Private_Dirty"]
anon = roll.get("Anonymous", 0)
print(f"RSS {roll['Rss']}  PSS {roll['Pss']}  USS {uss}  "
      f"(Pss_Anon {roll.get('Pss_Anon', 0)}  Pss_File {roll.get('Pss_File', 0)}  Pss_Shmem {roll.get('Pss_Shmem', 0)})")
print(f"anonymous {anon}  file/shared-backed {roll['Rss'] - anon}  Private_Dirty {roll['Private_Dirty']}  Swap {roll.get('Swap', 0)}")


def kind(name):
    if not name:
        return "[anon]"
    if name.startswith("/dev/dri") or "drm" in name or name.startswith("/dmabuf") or "dmabuf" in name:
        return "[gpu/drm buffers] " + name.split()[0]
    if name.startswith("/memfd:") or name.startswith("/dev/shm") or name.startswith("/SYSV"):
        return "[memfd/shm] " + re.sub(r"\s*\(deleted\)$", "", name.split("/")[-1])[:40]
    if name.startswith("["):
        return name
    base = name.split("/")[-1]
    base = re.sub(r"\.so[.\d]*$", ".so", base)
    return base


groups = collections.defaultdict(lambda: [0, 0, 0])
cur = None
for line in open(f"/proc/{pid}/smaps"):
    if re.match(r"^[0-9a-f]+-[0-9a-f]+ ", line):
        parts = line.split(None, 5)
        cur = kind(parts[5].strip() if len(parts) > 5 else "")
        continue
    m = re.match(r"^(Rss|Pss|Private_Clean|Private_Dirty):\s+(\d+) kB", line)
    if m and cur is not None:
        g = groups[cur]
        if m.group(1) == "Rss":
            g[0] += int(m.group(2))
        elif m.group(1) == "Pss":
            g[1] += int(m.group(2))
        else:
            g[2] += int(m.group(2))

print(f"{'mapping':48s} {'rss':>8s} {'pss':>8s} {'private':>8s}")
for name, (rss, pss, priv) in sorted(groups.items(), key=lambda kv: -kv[1][0])[:top]:
    print(f"{name[:48]:48s} {rss:8d} {pss:8d} {priv:8d}")

cats = collections.defaultdict(lambda: [0, 0, 0])
for name, v in groups.items():
    low = name.lower()
    if name == "[anon]" or name == "[heap]":
        c = "anon+heap (QML/JS heap, Qt objects, images, driver CPU state)"
    elif name.startswith("[gpu") or name.startswith("[memfd"):
        c = "gpu/drm + memfd/shm (window buffers, wl_shm pools)"
    elif any(k in low for k in ("llvm", "gallium", "mesa", "dri", "gl", "egl", "gbm", "vulkan", "nvidia")):
        c = "GL driver libraries (Mesa, LLVM, glvnd NVIDIA)"
    elif "qt6" in low or "libq" in low or low.startswith("qs") or low == "quickshell":
        c = "Qt / Quickshell code"
    elif name.startswith("["):
        c = "other kernel mappings"
    else:
        c = "other files (libs, fonts, locale, caches)"
    for i in range(3):
        cats[c][i] += v[i]
print()
print(f"{'category':60s} {'rss':>8s} {'pss':>8s} {'private':>8s}")
for c, (rss, pss, priv) in sorted(cats.items(), key=lambda kv: -kv[1][0]):
    print(f"{c:60s} {rss:8d} {pss:8d} {priv:8d}")
