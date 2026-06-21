#!/usr/bin/env bash
#
# eidos-hook.sh — report Claude Code's status to the Eidos island.
#
# Wired into Claude Code lifecycle hooks (see ~/.claude/settings.json) so the
# floating island reflects whether Claude is working or idle in real time.
#
# Usage:  eidos-hook.sh <status> [task]
#   <status>  running | paused | done | error
#   [task]    optional label; the literal "@tool" derives it from the hook's
#             stdin JSON (.tool_name), e.g. "Using Edit".
#
# Fire-and-forget by design: backgrounds the network call and always exits 0,
# so it never blocks Claude and never fails a hook even if the island is off.
#
status="${1:-running}"
task="${2:-}"
payload="$(cat)"   # hook JSON on stdin (carries session_id, tool_name, …)

# Use a per-session agent id so multiple concurrent Claude Code sessions each
# show as their own running agent instead of collapsing into one.
sid="$(printf '%s' "$payload" | /usr/bin/jq -r '.session_id // empty' 2>/dev/null)"
if [ -n "$sid" ]; then agent="claude-session-${sid:0:8}"; else agent="claude-session-local"; fi

if [ "$task" = "@tool" ]; then
  tool="$(printf '%s' "$payload" | /usr/bin/jq -r '.tool_name // empty' 2>/dev/null)"
  if [ -n "$tool" ]; then task="Using $tool"; else task="Working"; fi
fi

body="$(/usr/bin/jq -nc --arg a "$agent" --arg s "$status" --arg t "$task" \
  '{agent:$a, status:$s} + (if $t == "" then {} else {task:$t} end)')"

/usr/bin/curl -s -m 1 -X POST "${EIDOS_URL:-http://localhost:7799}/event" \
  -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 &

exit 0
