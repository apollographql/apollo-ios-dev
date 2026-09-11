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
# With either unset this is a no-op, so the automation still runs in a fork or
# a repo without Slack configured. It never exits non-zero: a Slack outage must
# not fail a run that has already opened a PR or posted a comment.

set -uo pipefail

if [[ $# -gt 0 ]]; then text="$1"; else text="$(cat)"; fi
[[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" || -z "$text" ]] && exit 0

jq -n --arg channel "$SLACK_CHANNEL_ID" --arg text "$text" \
  '{channel: $channel, text: ($text[0:30000]), unfurl_links: false}' \
  | curl -sS -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
      -H "Content-Type: application/json; charset=utf-8" \
      --data @- \
  | jq -r 'if .ok then "Slack: sent" else "Slack: failed: " + (.error // "unknown") end' >&2 || true
exit 0
