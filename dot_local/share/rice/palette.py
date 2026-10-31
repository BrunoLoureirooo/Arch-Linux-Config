"""Neon palette derivation: matugen role colours -> eight shell tokens.

Pure standard library. Colour maths is sRGB <-> linear <-> OKLab <-> OKLCH
(Bjorn Ottosson's matrices). See spec section 5.4.
"""
import math
import re

NEON_RAIN = {
    "bg": "#07070d", "panel": "#0c0d16", "line": "#1b1d30", "dim": "#6a7399",
    "fg": "#d7e3f0", "a1": "#00f0ff", "a2": "#ff2e88", "warn": "#ffd23f",
}

_HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
_STEP = 0.01


def _parse(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def _to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _from_linear(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hex_to_oklch(h):
    r, g, b = (_to_linear(c) for c in _parse(h))
    l = math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def _oklch_to_linear(L, C, h):
    a = C * math.cos(math.radians(h))
    b = C * math.sin(math.radians(h))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def _in_gamut(rgb):
    return all(-1e-9 <= c <= 1 + 1e-9 for c in rgb)


def oklch_to_hex(l, c, h):
    """Convert to #rrggbb, reducing chroma by bisection until inside sRGB."""
    l = min(max(l, 0.0), 1.0)
    if not _in_gamut(_oklch_to_linear(l, c, h)):
        lo, hi = 0.0, c
        for _ in range(40):
            mid = (lo + hi) / 2
            if _in_gamut(_oklch_to_linear(l, mid, h)):
                lo = mid
            else:
                hi = mid
        c = lo
    rgb = _oklch_to_linear(l, c, h)
    return "#" + "".join(
        "%02x" % round(min(max(_from_linear(min(max(v, 0.0), 1.0)), 0.0), 1.0) * 255) for v in rgb
    )


def _luminance(h):
    r, g, b = (_to_linear(c) for c in _parse(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = _luminance(a), _luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _hue_diff(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def _read_role(roles, name):
    """Return (chroma, hue) of a role, or None if absent. Bad hex raises."""
    if name not in roles:
        return None
    v = roles[name]
    if not isinstance(v, str) or not _HEX.match(v):
        raise ValueError(f"role {name!r} is not a #rrggbb colour: {v!r}")
    _, c, h = hex_to_oklch(v)
    return c, h


def _lift(l, c, h, bg, floor):
    """Raise lightness in 0.01 steps (bounded) until contrast with bg holds."""
    for i in range(101):
        hx = oklch_to_hex(min(l + i * _STEP, 1.0), c, h)
        if contrast(hx, bg) >= floor:
            return hx
    raise ValueError(f"cannot reach contrast {floor}:1 against {bg} (L={l}, C={c}, h={h})")


def derive_palette(roles):
    primary = _read_role(roles, "primary")
    tertiary = _read_role(roles, "tertiary")

    if primary is None or primary[0] < 0.02:
        h1, h2 = 195.0, 345.0
    else:
        h1 = primary[1]
        if tertiary is None or tertiary[0] < 0.02 or _hue_diff(h1, tertiary[1]) < 40:
            h2 = (h1 + 150) % 360
        else:
            h2 = tertiary[1]

    bg = oklch_to_hex(.12, .02, h1)
    return {
        "bg": bg,
        "panel": oklch_to_hex(.16, .025, h1),
        "line": oklch_to_hex(.26, .04, h1),
        "dim": _lift(.66, .05, h1, bg, 4.5),
        "fg": _lift(.92, .015, h1, bg, 7),
        "a1": _lift(.86, .17, h1, bg, 7),
        "a2": _lift(.70, .22, h2, bg, 4.5),
        "warn": oklch_to_hex(.88, .15, 95),
    }
