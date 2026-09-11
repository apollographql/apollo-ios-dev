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
#   WAS_DRAFT            "true" if PR_NUMBER was a draft before the run
#   CLAUDE_OUTCOME       outcome of the Claude step (success, failure, ...)
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
UPSTREAM_REPLY_URL="${UPSTREAM_REPLY_URL:-}"

if [[ -z "$REPO" || ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "REPO and a numeric PR_NUMBER are required; not notifying." >&2
  exit 0
fi

pr_json="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title,url,isDraft 2>/dev/null || echo '{}')"
pr_title="$(jq -r '.title // ""' <<<"$pr_json")"
pr_url="$(jq -r '.url // ""' <<<"$pr_json")"
is_draft="$(jq -r '.isDraft // false' <<<"$pr_json")"
[[ -z "$pr_url" ]] && pr_url="https://github.com/${REPO}/issues/${PR_NUMBER}"

# Claude's own reply: the newest comment since the run started from the identity
# Claude posts under. Matched by login, so neither this workflow's own
# github-actions[bot] plumbing comment nor a CI bot's is mistaken for it.
issue_comments="$(gh api --paginate "repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100" --jq '.[]' 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')"
review_comments="$(gh api --paginate "repos/${REPO}/pulls/${PR_NUMBER}/comments?per_page=100" --jq '.[]' 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')"
reply_json="$(printf '%s\n%s\n' "$issue_comments" "$review_comments" \
  | jq -s --arg since "$RUN_STARTED_AT" --arg login "${REPLY_BOT_LOGIN:-claude[bot]}" '
      (add // [])
      | map(select((.user.type? == "Bot") and (.created_at >= $since)
                   and ((.user.login == $login)
                        or (.user.login | ascii_downcase | contains("claude")))))
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

if [[ "$CLAUDE_OUTCOME" == "success" ]]; then
  header=":robot_face: *Claude responded on ${REPO}#${PR_NUMBER}*"
else
  header=":rotating_light: *Claude follow-up did not finish* (${CLAUDE_OUTCOME}) on ${REPO}#${PR_NUMBER}"
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
  [[ "${WAS_DRAFT:-}" == "true" && "$is_draft" == "false" ]] && printf '\n*Marked ready for review:* %s\n' "$pr_url"
  [[ -n "$UPSTREAM_REPLY_URL" ]] && printf '\n*Posted upstream:* %s\n' "$UPSTREAM_REPLY_URL"
  [[ -n "$RUN_URL" ]] && printf '\n_Run: %s_\n' "$RUN_URL"
} > "${RUNNER_TEMP:-/tmp}/followup-slack.txt"

"$here/slack-notify.sh" "$(cat "${RUNNER_TEMP:-/tmp}/followup-slack.txt")"
exit 0
