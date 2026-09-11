#!/usr/bin/env bash
#
# Sends the Slack notice for one Claude Follow-up run: what the maintainer
# asked, what Claude replied, any pull request the run opened or marked ready
# for review, and any approved reply it posted upstream.
#
# Triage already alerts on its own PRs and upstream replies (publish-result.sh).
# This covers the other half of the bot's public activity: everything it does in
# response to an @claude comment.
#
# Usage: notify-followup.sh
#
# Environment:
#   GH_TOKEN             token with read access to REPO
#   REPO                 default GITHUB_REPOSITORY
#   PR_NUMBER            PR (or issue) the @claude comment was left on
#   TRIGGER_ACTOR        login of the commenter
#   TRIGGER_COMMENT_URL  link to that comment
#   TRIGGER_COMMENT_BODY text of that comment
#   REPLY_BOT_LOGIN      login Claude posts under (default claude[bot])
#   RUN_STARTED_AT       ISO-8601 time recorded before Claude ran
#   CLAUDE_OUTCOME       outcome of the Claude step (success, failure, ...)
#   UPSTREAM_OUTCOME     outcome of the upstream reply step; a reply that was
#                        queued but not posted fails there, not in the Claude
#                        step, and must still be flagged
#   UPSTREAM_REPLY_URL   optional; set when a reply was posted upstream
#   RUN_URL              link to the workflow run
#   SLACK_BOT_TOKEN, SLACK_CHANNEL_ID   see slack-notify.sh
#
# Best effort throughout: a missing field costs a line of the message, never the
# message, and the script always exits 0.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
PR_NUMBER="${PR_NUMBER:-}"
RUN_STARTED_AT="${RUN_STARTED_AT:-1970-01-01T00:00:00Z}"
RUN_URL="${RUN_URL:-}"
CLAUDE_OUTCOME="${CLAUDE_OUTCOME:-success}"
UPSTREAM_OUTCOME="${UPSTREAM_OUTCOME:-success}"
UPSTREAM_REPLY_URL="${UPSTREAM_REPLY_URL:-}"
bot_login="${REPLY_BOT_LOGIN:-claude[bot]}"

if [[ -z "$REPO" || ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "REPO and a numeric PR_NUMBER are required; not notifying." >&2
  exit 0
fi

# The identity Claude posts under, matched by login so that neither this
# workflow's own github-actions[bot] plumbing comment nor a CI bot's is
# mistaken for it. Shared by the comment, review, and timeline lookups.
is_claude='def is_claude($l): ($l == $login) or (($l // "") | ascii_downcase | contains("claude"));'

pr_json="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title,url 2>/dev/null || echo '{}')"
pr_title="$(jq -r '.title // ""' <<<"$pr_json")"
pr_url="$(jq -r '.url // ""' <<<"$pr_json")"
[[ -z "$pr_url" ]] && pr_url="https://github.com/${REPO}/issues/${PR_NUMBER}"

# Claude's own reply: the newest thing it wrote since the run started, whether
# that landed as an issue comment, a review comment, or a review body.
fetch() { gh api --paginate "$1" --jq '.[]' 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]'; }
issue_comments="$(fetch "repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100")"
review_comments="$(fetch "repos/${REPO}/pulls/${PR_NUMBER}/comments?per_page=100")"
# Reviews timestamp with submitted_at and may carry no body at all.
reviews="$(fetch "repos/${REPO}/pulls/${PR_NUMBER}/reviews?per_page=100" \
  | jq 'map(select((.body // "") != "") | .created_at = .submitted_at)' 2>/dev/null || echo '[]')"
reply_json="$(printf '%s\n%s\n%s\n' "$issue_comments" "$review_comments" "$reviews" \
  | jq -s --arg since "$RUN_STARTED_AT" --arg login "$bot_login" "$is_claude"'
      (add // [])
      | map(select((.user.type? == "Bot") and (.created_at >= $since) and is_claude(.user.login)))
      | sort_by(.created_at) | last // {}' 2>/dev/null || echo '{}')"
[[ -z "$reply_json" ]] && reply_json='{}'
reply_url="$(jq -r '.html_url // ""' <<<"$reply_json")"
# Sliced by jq, not by the shell: a byte-wise cut can split a multi-byte character.
reply_body="$(jq -r '(.body // "")[0:2500]' <<<"$reply_json" | sed -e '/^<!--/d' -e 's/[[:space:]]*$//')"

# Pull requests the run itself opened. Bot-authored only, so a human opening a
# PR while the follow-up runs is never reported as Claude's work.
new_prs="$(gh pr list --repo "$REPO" --state all --limit 50 \
  --json number,url,title,createdAt,author 2>/dev/null \
  | jq -r --arg since "$RUN_STARTED_AT" --arg pr "$PR_NUMBER" '
      map(select((.createdAt >= $since) and (.author.is_bot // false) and ((.number|tostring) != $pr)))
      | map("• " + .url + " — " + .title) | join("\n")' 2>/dev/null || echo "")"

# Read from the timeline rather than diffing the draft flag: the event carries
# an actor, so a maintainer marking the PR ready mid-run is not reported as
# Claude's doing, and a failed read reports nothing instead of guessing.
marked_ready="$(gh api --paginate "repos/${REPO}/issues/${PR_NUMBER}/timeline?per_page=100" --jq '.[]' 2>/dev/null \
  | jq -s --arg since "$RUN_STARTED_AT" --arg login "$bot_login" "$is_claude"'
      any(.[]; (.event? == "ready_for_review") and (.created_at >= $since) and is_claude(.actor.login))' 2>/dev/null || echo false)"

# Success is the only unflagged outcome for either step. "skipped" on the Claude
# step means an earlier step failed, which is the very case to flag; the upstream
# step is skipped only on cancellation, when this notice is skipped with it.
failed=""
[[ "$CLAUDE_OUTCOME" != "success" ]] && failed="the Claude step (${CLAUDE_OUTCOME})"
if [[ "$UPSTREAM_OUTCOME" != "success" ]]; then
  [[ -n "$failed" ]] && failed="${failed} and "
  failed="${failed}the upstream reply step (${UPSTREAM_OUTCOME})"
fi

if [[ -z "$failed" ]]; then
  header=":robot_face: *Claude responded on ${REPO}#${PR_NUMBER}*"
else
  header=":rotating_light: *Claude follow-up did not complete* — ${failed} — on ${REPO}#${PR_NUMBER}"
fi

{
  printf '%s\n' "$header"
  [[ -n "$pr_title" ]] && printf '*%s*\n' "$pr_title"
  printf '%s\n' "$pr_url"
  if [[ -n "${TRIGGER_COMMENT_BODY:-}" ]]; then
    printf '\n*@%s asked:* %s\n' "${TRIGGER_ACTOR:-someone}" \
      "$(jq -rn --arg b "$TRIGGER_COMMENT_BODY" '($b | gsub("\\s+"; " "))[0:400]')"
  fi
  [[ -n "${TRIGGER_COMMENT_URL:-}" ]] && printf '%s\n' "$TRIGGER_COMMENT_URL"
  [[ -n "$reply_body" ]] && printf '\n*Claude replied:*\n%s\n' "$reply_body"
  [[ -n "$reply_url" ]] && printf '%s\n' "$reply_url"
  [[ -n "$new_prs" ]] && printf '\n*Opened:*\n%s\n' "$new_prs"
  [[ "$marked_ready" == "true" ]] && printf '\n*Marked ready for review:* %s\n' "$pr_url"
  [[ -n "$UPSTREAM_REPLY_URL" ]] && printf '\n*Posted upstream:* %s\n' "$UPSTREAM_REPLY_URL"
  # A queued reply that never posted leaves no URL; say so rather than omitting the line.
  [[ -z "$UPSTREAM_REPLY_URL" && "$UPSTREAM_OUTCOME" == "failure" ]] && \
    printf '\n:warning: *An upstream reply was queued but not confirmed posted.* Check the run log before posting it by hand.\n'
  [[ -n "$RUN_URL" ]] && printf '\n_Run: %s_\n' "$RUN_URL"
} | "$here/slack-notify.sh"
exit 0
