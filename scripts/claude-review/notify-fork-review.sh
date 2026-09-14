#!/usr/bin/env bash
#
# Posts a Slack heads-up that a fork PR is waiting for a review decision, with a
# link to the PR. Approval is not automated: a maintainer opens the PR and adds
# the `safe to review` label (or `fork-review-declined`) in GitHub's own UI.
#
# WHY THIS IS THE WHOLE MECHANISM
# -------------------------------
# Applying a label is an authenticated action GitHub already gates on repo
# permission: only a user with Triage/Write access can add a label, and a fork
# PR author cannot. So GitHub's own browser auth IS the approval gate — no Slack
# workflow, no bot-applied label, no token stored anywhere. Adding `safe to
# review` (by a human, so not the default GITHUB_TOKEN) fires
# `pull_request_target: labeled`, which starts claude-fork-pr-review.yml.
#
# This job only reads PR metadata and posts a message. It applies no label, holds
# no GitHub write token, and never checks out fork code.
#
# Modes:
#   * Event:   PR_NUMBER (+ PR_TITLE/PR_AUTHOR/PR_URL) set -> notify for that PR.
#   * Catch-up: none set -> list pending fork PRs and notify for each.
#
# Environment:
#   SLACK_BOT_TOKEN    Slack app token with chat:write
#   SLACK_CHANNEL_ID   channel (private maintainer channel recommended)
#   GH_TOKEN           pull-requests:read on REPO (catch-up mode only)
#   REPO               default GITHUB_REPOSITORY
#   TRIGGER_LABEL      default "safe to review"
#   DECLINE_LABEL      default "fork-review-declined"
#   PR_NUMBER, PR_TITLE, PR_AUTHOR, PR_URL   event-mode PR fields
#
# Best effort: a Slack failure is logged, never fatal (exit 0).

set -uo pipefail

SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
SLACK_CHANNEL_ID="${SLACK_CHANNEL_ID:-}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
TRIGGER_LABEL="${TRIGGER_LABEL:-safe to review}"
DECLINE_LABEL="${DECLINE_LABEL:-fork-review-declined}"

if [[ -z "$SLACK_BOT_TOKEN" || -z "$SLACK_CHANNEL_ID" ]]; then
  echo "Slack not configured (SLACK_BOT_TOKEN / SLACK_CHANNEL_ID unset); nothing to do." >&2
  exit 0
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# notify <pr> <title> <author> <url>
# All sanitisation is done in jq: a fork-authored title has newlines flattened,
# is sliced to 200 Unicode codepoints (not bytes, so no UTF-8 is split), and only
# then is &<> escaped so it cannot inject Slack links or a broadcast like
# <!channel>. Slicing before escaping also avoids cutting an entity in half.
notify() {
  local pr="$1" title="$2" author="$3" url="$4" payload resp ok
  payload="$(jq -n \
    --arg c "$SLACK_CHANNEL_ID" --arg pr "$pr" --arg url "$url" \
    --arg title "$title" --arg author "$author" \
    --arg tl "$TRIGGER_LABEL" --arg dl "$DECLINE_LABEL" '
    def esc: gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;");
    ($title | gsub("[\n\r]";" ") | .[0:200] | esc) as $t
    | ($author | esc) as $a
    | { channel: $c,
        text: ( ":mag: *Fork PR needs a review decision* — <" + $url + "|#" + $pr + ">\n"
              + "*" + $t + "*  ·  by `" + $a + "`\n"
              + "Approve by adding the `" + $tl + "` label on the PR (decline with `" + $dl
              + "`). Only maintainers with write access can label, so the click is your GitHub approval." ),
        unfurl_links: false, unfurl_media: false }')"
  resp="$(curl -sS -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data "$payload" 2>/dev/null || echo '{}')"
  ok="$(jq -r '.ok' <<<"$resp" 2>/dev/null || echo false)"
  if [[ "$ok" == "true" ]]; then echo "Notified for PR #${pr}." >&2
  else echo "Slack chat.postMessage failed for PR #${pr}: $(jq -r '.error // "unknown"' <<<"$resp" 2>/dev/null)" >&2; fi
}

if [[ -n "${PR_NUMBER:-}" ]]; then
  notify "${PR_NUMBER}" "${PR_TITLE:-}" "${PR_AUTHOR:-}" "${PR_URL:-}"
  exit 0
fi

# Catch-up: notify for every currently pending fork PR.
: "${REPO:?REPO or GITHUB_REPOSITORY required for catch-up mode}"
: "${GH_TOKEN:?GH_TOKEN required for catch-up mode}"
pending="$(REPO="$REPO" GH_TOKEN="$GH_TOKEN" TRIGGER_LABEL="$TRIGGER_LABEL" DECLINE_LABEL="$DECLINE_LABEL" \
  "$here/list-pending-fork-prs.sh")"
count=0
while IFS= read -r row; do
  [[ -z "$row" || "$row" == "null" ]] && continue
  notify "$(jq -r '.number' <<<"$row")" "$(jq -r '.title' <<<"$row")" \
         "$(jq -r '.author' <<<"$row")" "$(jq -r '.url' <<<"$row")"
  count=$((count+1))
done < <(jq -c '.[]' <<<"$pending")
echo "Catch-up: notified ${count} PR(s)." >&2
