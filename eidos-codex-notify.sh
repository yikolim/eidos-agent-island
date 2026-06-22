#!/usr/bin/env bash
#
# eidos-codex-notify.sh — Codex `notify` wrapper.
#
# Wired into ~/.codex/config.toml:
#   notify = ["…/eidos-codex-notify.sh", "turn-ended"]
# Codex invokes it as:  eidos-codex-notify.sh turn-ended <event-json>
#
# It does two things:
#   1. Forwards the event UNCHANGED to the existing Codex Computer Use client,
#      so that integration keeps working.
#   2. Reflects Codex activity on the Eidos island (agent "codex").
#
# Fire-and-forget; always exits 0 so it never disrupts Codex.
#
SKY="/Users/yikoli/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
ISLAND="${EIDOS_URL:-http://localhost:7799}"
STAMP="/tmp/eidos-codex-last"
IDLE_AFTER=35   # seconds of no turns before Codex is shown idle

# 1) Preserve existing Computer Use behaviour — forward all args verbatim.
[ -x "$SKY" ] && "$SKY" "$@" >/dev/null 2>&1 &

# 2) Reflect on the island. Codex passes the event JSON as the last argument.
json="${*: -1}"
task="$(printf '%s' "$json" | /usr/bin/jq -r '
  ."last-assistant-message" // .last_assistant_message // .message // .summary // empty' 2>/dev/null | tr '\n' ' ' | cut -c1-60)"
[ -z "$task" ] && task="Codex working"

body="$(/usr/bin/jq -nc --arg t "$task" '{agent:"codex", status:"running", task:$t}')"
/usr/bin/curl -s -m 1 -X POST "$ISLAND/event" \
  -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 &

# 3) Debounced idle: Codex only notifies on turn-end, so keep it "running" while
#    turns keep arriving and mark it done once they stop for IDLE_AFTER seconds.
date +%s > "$STAMP"
(
  sleep "$IDLE_AFTER"
  last="$(cat "$STAMP" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if [ $((now - last)) -ge "$IDLE_AFTER" ]; then
    /usr/bin/curl -s -m 1 -X POST "$ISLAND/event" \
      -H 'Content-Type: application/json' -d '{"agent":"codex","status":"done"}' >/dev/null 2>&1
  fi
) &

exit 0
