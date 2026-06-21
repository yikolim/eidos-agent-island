#!/usr/bin/env bash
#
# eidos-notify.sh — surface Claude Code's attention/approval requests on the
# Eidos island as a centered, auto-dismissing approval card.
#
# Wired to the Notification hook (fires when Claude is waiting on you — a
# permission prompt or an input request). Informational: the terminal remains
# the authoritative place to actually allow/deny. Fire-and-forget, exits 0.
#
payload="$(cat)"
msg="$(printf '%s' "$payload" | /usr/bin/jq -r '.message // "Claude needs your attention"' 2>/dev/null)"
[ -z "$msg" ] && msg="Claude needs your attention"

body="$(/usr/bin/jq -nc --arg m "$msg" \
  '{agent:"claude-code", task:$m, requestID:("cc-" + (now|tostring)), actions:[{op:"open", target:$m}]}')"

/usr/bin/curl -s -m 2 -X POST "${EIDOS_URL:-http://localhost:7799}/notify" \
  -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 &

exit 0
