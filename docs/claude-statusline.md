# Claude usage limits status line

`claude-limits-statusline` is a command Claude Code runs as its status line. It reads the
status line JSON on stdin, caches the 5-hour and 7-day usage windows in
`~/.cache/claude-limits.json` (read by the Quickshell widget), and prints a short footer
line such as `5h 38% · 7d 19%`. It always exits 0 and never prints errors. The library is
`~/.local/share/rice/limits.py`.

It reads usage numbers only. It never reads or sends your login token.

## Enable

This is deliberately not applied by the dotfiles. Add this to `~/.claude/settings.json`:

```json
"statusLine": {"type": "command", "command": "~/.local/bin/claude-limits-statusline"}
```

Side effect: once a custom status line exists, Claude Code hides most of its footer
keyboard hints.

## Caveats

`rate_limits` only appears for Pro/Max plans, after the session's first API response, and
each window may be absent (upstream issue anthropics/claude-code #45133 reports it missing
on some setups). Calls without it never erase existing cached data; the widget shows
"no data" if there is none.

## Verify

Send one message in Claude Code, then `cat ~/.cache/claude-limits.json`. Shape:
`{"five_hour": {"pct": 38.4, "resets_at": 2000000000} | null, "seven_day": ... | null, "updated_at": <unix seconds>}`.

Manual test without touching the real cache (use a `resets_at` in the future; expired
windows are dropped):

```sh
echo '{"rate_limits":{"five_hour":{"used_percentage":38.4,"resets_at":2000000000}}}' | CLAUDE_LIMITS_CACHE=/tmp/x.json ~/.local/bin/claude-limits-statusline
```

## Remove

Delete the `statusLine` entry from `~/.claude/settings.json`, then optionally
`rm ~/.cache/claude-limits.json`.
