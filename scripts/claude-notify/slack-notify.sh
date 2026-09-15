#!/usr/bin/env bash
#
# Posts one message to Slack. The single place any Claude automation talks to
# Slack, so the token handling and truncation live in one file.
#
# Usage: slack-notify.sh <text>   (or pipe the text on stdin with no arguments)
#
# Environment:
#   SLACK_BOT_TOKEN   Slack app token with chat:write (im:write for DMs)
#   SLACK_CHANNEL_ID  channel or member ID
#
#   SLACK_STRICT      set to 1 when the message is the only record of an outcome:
#                     an unconfigured or rejected post then exits 1 and prints
#                     the message to stderr, so the caller can fail loudly.
#
# By default this is a no-op with either variable unset and never exits
# non-zero, so the automation still runs in a fork or a repo without Slack, and
# a Slack outage does not fail a run that has already opened a PR or posted a
# comment.

set -uo pipefail

if [[ $# -gt 0 ]]; then text="$1"; else text="$(cat)"; fi
strict="${SLACK_STRICT:-0}"

fail() {
  echo "Slack: $1" >&2
  if [[ "$strict" == "1" ]]; then
    echo "Message was:" >&2; printf '%s\n' "$text" >&2
    exit 1
  fi
  exit 0
}

[[ -z "$text" ]] && exit 0
[[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]] && fail "not configured"

resp="$(jq -n --arg channel "$SLACK_CHANNEL_ID" --arg text "$text" \
  '{channel: $channel, text: ($text[0:30000]), unfurl_links: false}' \
  | curl -sS -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
      -H "Content-Type: application/json; charset=utf-8" \
      --data @-)" || fail "request failed"
if jq -e '.ok' <<<"$resp" >/dev/null 2>&1; then
  echo "Slack: sent" >&2
  exit 0
fi
fail "failed: $(jq -r '.error // "unknown"' <<<"$resp" 2>/dev/null)"
