"""Claude Code usage limits: parse the status line payload, render a footer line, cache it."""
import json
import math
import os
import tempfile

WINDOWS = ("five_hour", "seven_day")
LABELS = {"five_hour": "5h", "seven_day": "7d"}


def _number(v):
    """True for a finite int/float (bool, strings and NaN/inf are not numbers here)."""
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _window(w, now):
    if not isinstance(w, dict):
        return None
    pct, resets = w.get("used_percentage"), w.get("resets_at")
    if not _number(pct) or not _number(resets) or resets <= now:
        return None
    return {"pct": min(100.0, max(0.0, float(pct))), "resets_at": int(resets)}


def parse_rate_limits(payload, now):
    limits = payload.get("rate_limits") if isinstance(payload, dict) else None
    if not isinstance(limits, dict):
        limits = {}
    data = {name: _window(limits.get(name), now) for name in WINDOWS}
    data["updated_at"] = int(now)
    return data


def render_line(data):
    parts = [f"{LABELS[n]} {round(data[n]['pct'])}%" for n in WINDOWS if data.get(n)]
    return " · ".join(parts)


def write_cache(path, data):
    """Write data as JSON to path atomically: temp file in the same directory, then rename."""
    path = os.fspath(path)
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".claude-limits.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
