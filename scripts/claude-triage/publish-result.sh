#!/usr/bin/env bash
#
# Publishes the outcome of one Claude triage run.
#
#   * High-confidence verified bug fix  -> pushes Claude's branch, opens a ready PR.
#   * Anything else                     -> opens a draft tracking PR on an empty commit
#                                          (no files are committed); summary, questions,
#                                          and draft reply live in the PR body only.
#   * High-confidence reply             -> posted on the upstream issue, but only under a
#                                          bot identity (UPSTREAM_TOKEN). Never as a person.
#   * Slack DM/channel alert with the full summary, questions, and draft reply.
#
# The tracking PR is the dedup record (`apollo-ios#<N>` in its title) and where the
# maintainer answers with `@claude` comments.
#
# Usage: publish-result.sh <result.json>
#
# Environment:
#   GH_TOKEN               token used for dev-repo pushes and PR creation
#   UPSTREAM_TOKEN         bot (GitHub App) token; must never be a person's PAT.
#                          Empty, or a token without access to UPSTREAM_REPO,
#                          means the draft is routed to the maintainer instead.
#   UPSTREAM_REPO          default apollographql/apollo-ios
#   DEV_REPO               default apollographql/apollo-ios-dev
#   TRIAGE_LABEL           default claude-triage
#   ASSIGNEE               GitHub login alerted on results that need input
#   AUTO_COMMENT           default true; "false" disables posting even with a bot token
#   RUN_URL                link to the workflow run
#   ISSUE_NUMBER           upstream issue number (required)
#   TRIGGER_REASON         new | reporter-followup | manual (informational)
#   SLACK_BOT_TOKEN        optional
#   SLACK_CHANNEL_ID       optional channel or member ID

set -euo pipefail

result_file="${1:?usage: publish-result.sh <result.json>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-apollographql/apollo-ios}"
DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
TRIAGE_LABEL="${TRIAGE_LABEL:-claude-triage}"
AUTO_COMMENT="${AUTO_COMMENT:-true}"
UPSTREAM_TOKEN="${UPSTREAM_TOKEN:-}"
RUN_URL="${RUN_URL:-}"
n="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
tmp="${RUNNER_TEMP:-/tmp}"
issue_url="https://github.com/${UPSTREAM_REPO}/issues/${n}"
branch="claude/triage/apollo-ios-${n}"
push_url="https://x-access-token:${GH_TOKEN}@github.com/${DEV_REPO}.git"

ensure_label() {
  gh label create "$1" --repo "$DEV_REPO" --color "$2" --description "$3" --force >/dev/null 2>&1 || true
}
ensure_label "$TRIAGE_LABEL" "1D76DB" "Automated triage of an apollo-ios issue"
ensure_label "needs-input" "D93F0B" "Automated triage needs a maintainer decision"
ensure_label "response-ready" "5319E7" "Automated triage drafted a reply awaiting approval"

slack_notify() {
  [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]] && return 0
  jq -n --arg channel "$SLACK_CHANNEL_ID" --arg text "$1" \
    '{channel: $channel, text: $text, unfurl_links: false}' \
    | curl -sS -X POST https://slack.com/api/chat.postMessage \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H "Content-Type: application/json; charset=utf-8" \
        --data @- \
    | jq -r 'if .ok then "Slack: sent" else "Slack: failed: " + (.error // "unknown") end' >&2
}

nl=$'\n'

existing_open_pr() {
  gh pr list --repo "$DEV_REPO" --head "$1" --state open --json url --jq '.[0].url // empty'
}

# Creates a PR for $1 (head branch), or updates the open one if a re-triage finds it already there.
# $2 = title, $3 = body file, $4 = "draft"|"ready", rest = labels (--label X ...) and other create flags.
triage_marker() {
  printf '\n<!-- claude-triage issue=%s triaged-at=%s -->\n' "$n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Re-stamps the newest tracking or fix PR for this issue (open or closed) so
# discovery does not re-trigger on the same reporter comments.
stamp_latest_record() {
  local record url body
  record="$(gh pr list --repo "$DEV_REPO" --label "$TRIAGE_LABEL" --state all --limit 1 \
    --search "apollo-ios#${n} in:title sort:updated-desc" --json url,body \
    --jq '.[0] // empty | "\(.url)\n\(.body)"')"
  [[ -z "$record" ]] && return 1
  url="${record%%$'\n'*}"
  body="${record#*$'\n'}"
  { printf '%s\n' "$body" | sed '/<!-- claude-triage issue=/d'; triage_marker; } >"$tmp/restamped-body.md"
  gh pr edit "$url" --repo "$DEV_REPO" --body-file "$tmp/restamped-body.md" >/dev/null
  echo "$url"
}

create_or_update_pr() {
  local head="$1" title="$2" body_file="$3" mode="$4"; shift 4
  local url
  triage_marker >>"$body_file"
  url="$(existing_open_pr "$head")"
  if [[ -n "$url" ]]; then
    local edit_args=()
    for arg in "$@"; do
      case "$arg" in
        --label) edit_args+=(--add-label) ;;
        --assignee) edit_args+=(--add-assignee) ;;
        --reviewer) edit_args+=(--add-reviewer) ;;
        *) edit_args+=("$arg") ;;
      esac
    done
    gh pr edit "$url" --repo "$DEV_REPO" --title "$title" --body-file "$body_file" "${edit_args[@]}" >/dev/null
    gh pr comment "$url" --repo "$DEV_REPO" --body "Re-triaged by automation; description updated. Run: ${RUN_URL}" >/dev/null
    echo "$url"
  else
    local draft_flag=()
    [[ "$mode" == "draft" ]] && draft_flag=(--draft)
    gh pr create --repo "$DEV_REPO" --base main --head "$head" ${draft_flag[@]+"${draft_flag[@]}"} \
      --title "$title" --body-file "$body_file" "$@"
  fi
}

# Opens (or updates) a draft tracking PR. $1 = title, $2 = body file, rest = extra gh flags.
# Any commits Claude left on the branch are preserved so an unverified fix attempt is not lost;
# otherwise the branch is a single empty commit on top of origin/main.
open_tracking_pr() {
  local title="$1" body_file="$2"; shift 2
  if git rev-parse --verify --quiet "$branch" >/dev/null && \
     [[ "$(git rev-list --count "origin/main..$branch")" -gt 0 ]]; then
    git checkout -q "$branch"
    printf '\n> **Note:** this branch carries an unverified fix attempt from the triage run. Review it before building on it.\n' >>"$body_file"
  else
    git checkout -q -B "$branch" origin/main
    git commit -q --allow-empty -m "Triage tracking for apollo-ios#${n}"
  fi
  git push -q --force "$push_url" "${branch}:refs/heads/${branch}"
  create_or_update_pr "$branch" "$title" "$body_file" draft --label "$TRIAGE_LABEL" "$@"
}

if [[ ! -s "$result_file" ]] || ! jq -e . "$result_file" >/dev/null 2>&1; then
  printf 'Automated triage of %s did not produce a result.\n\nWorkflow run: %s\n\nRe-run `Claude Issue Triage` with `issue_number=%s` and `force=true` after fixing the cause, then close this PR.\n' \
    "$issue_url" "$RUN_URL" "$n" >"$tmp/tracking-body.md"
  url="$(open_tracking_pr "[triage] apollo-ios#${n}: triage failed" "$tmp/tracking-body.md" \
    --label "needs-input" ${ASSIGNEE:+--assignee "$ASSIGNEE"})"
  slack_notify ":warning: Apollo iOS triage failed for ${issue_url}. Tracking: ${url}"
  echo "tracking_url=$url" >>"${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

r() { jq -r "$1" "$result_file"; }

title="$(r '.issue_title')"
category="$(r '.category')"
confidence="$(r '.confidence')"
confidence_reason="$(r '.confidence_reason // ""')"
summary="$(r '.summary')"
affected="$(r '.affected_area // ""')"
questions="$(jq -r '(.questions_for_maintainer // []) | map("- " + .) | join("\n")' "$result_file")"
related="$(jq -r '(.related // []) | map("- " + .) | join("\n")' "$result_file")"
response_draft="$(r '.response_draft // empty')"
fix_branch="$(r '.fix.branch // empty')"
fix_verified="$(r '.fix.verified // false')"

trigger="${TRIGGER_REASON:-new}"

if [[ "$(r '.nothing_to_do // false')" == "true" ]]; then
  if url="$(stamp_latest_record)"; then
    gh pr comment "$url" --repo "$DEV_REPO" --body "$(printf 'Re-triaged after a reporter follow-up (%s); no action needed.\n\n%s\n\n_Run: %s_' "$trigger" "$summary" "$RUN_URL")" >/dev/null
    echo "No action needed; re-stamped $url" >&2
    { echo "tracking_url=$url"; echo "confidence=$confidence"; echo "has_fix=false"; echo "posted_comment_url="; } >>"${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
  echo "nothing_to_do set but no tracking record found; falling through to open one." >&2
fi

posted_comment_url=""
if [[ -n "$response_draft" && "$confidence" == "high" && "$category" != "feature" ]]; then
  if [[ "$AUTO_COMMENT" == "true" && -n "$UPSTREAM_TOKEN" ]]; then
    footer=$'\n\n---\n_This reply was generated automatically by the Apollo iOS team\'s AI assistant after reviewing the code. It may be incomplete; a maintainer will follow up if needed._'
    if posted_comment_url="$(printf '%s%s' "$response_draft" "$footer" \
        | GH_TOKEN="$UPSTREAM_TOKEN" gh issue comment "$n" --repo "$UPSTREAM_REPO" --body-file - 2>"$tmp/comment-error.txt")"; then
      echo "Posted upstream comment: $posted_comment_url" >&2
    else
      posted_comment_url=""
      echo "Upstream comment failed (bot token likely lacks access to ${UPSTREAM_REPO}); routing draft to maintainer." >&2
      cat "$tmp/comment-error.txt" >&2
    fi
  else
    echo "High-confidence reply not posted: AUTO_COMMENT=${AUTO_COMMENT}, bot token $([[ -n "$UPSTREAM_TOKEN" ]] && echo present || echo absent)." >&2
  fi
fi

has_fix=false
if [[ "$category" == "bug" && "$confidence" == "high" && -n "$fix_branch" && "$fix_verified" == "true" ]]; then
  if git rev-parse --verify --quiet "$fix_branch" >/dev/null && \
     [[ "$(git rev-list --count "origin/main..$fix_branch")" -gt 0 ]]; then
    has_fix=true
  else
    echo "Fix branch '$fix_branch' has no commits ahead of origin/main; treating as needs-input." >&2
    confidence="medium"
    confidence_reason="${confidence_reason} (Fix branch was empty at publish time.)"
  fi
fi

{
  printf '**Upstream issue:** %s\n' "$issue_url"
  printf '**Category:** %s  \n**Confidence:** %s\n' "$category" "$confidence"
  [[ -n "$confidence_reason" ]] && printf '_%s_\n' "$confidence_reason"
  printf '\n## Summary\n\n%s\n' "$summary"
  [[ -n "$affected" ]] && printf '\n**Affected area:** `%s`\n' "$affected"
  [[ -n "$related" ]] && printf '\n## Related\n\n%s\n' "$related"
  [[ -n "$questions" ]] && printf '\n## Questions for the maintainer\n\n%s\n' "$questions"
  if [[ -n "$response_draft" ]]; then
    if [[ -n "$posted_comment_url" ]]; then
      printf '\n## Reply posted upstream\n\n%s\n\n<details><summary>Text</summary>\n\n%s\n\n</details>\n' "$posted_comment_url" "$response_draft"
    else
      printf '\n## Draft reply (not posted)\n\n%s\n' "$response_draft"
    fi
  fi
} >"$tmp/triage-section.md"

if [[ "$has_fix" == true ]]; then
  pr_title="$(r '.fix.pr_title // empty')"
  [[ -z "$pr_title" ]] && pr_title="Fix: ${title}"
  [[ "$pr_title" != *"apollo-ios#${n}"* ]] && pr_title="${pr_title} (apollo-ios#${n})"
  {
    r '.fix.pr_body // ""'
    printf '\n\n**Verification:** %s\n' "$(r '.fix.verification // "not recorded"')"
    printf '\nFixes %s\n\n---\n\n<details><summary>Automated triage details</summary>\n\n' "$issue_url"
    cat "$tmp/triage-section.md"
    printf '\n_Workflow run: %s_\n\n</details>\n' "$RUN_URL"
  } >"$tmp/pr-body.md"
  git push -q --force "$push_url" "${fix_branch}:refs/heads/${fix_branch}"
  tracking_url="$(create_or_update_pr "$fix_branch" "$pr_title" "$tmp/pr-body.md" ready \
    --label "$TRIAGE_LABEL" ${ASSIGNEE:+--reviewer "$ASSIGNEE"})"
  echo "Opened fix PR: $tracking_url" >&2
  reply_line=""
  [[ -n "$posted_comment_url" ]] && reply_line="Reply posted: ${posted_comment_url}${nl}"
  slack_notify "$(printf ':white_check_mark: *Apollo iOS triage opened a fix PR*\n*%s* (apollo-ios#%s)\n%s\n%sPR: %s' \
    "$title" "$n" "$summary" "$reply_line" "$tracking_url")"
elif [[ -n "$posted_comment_url" ]]; then
  # The reply already went out; the tracking PR is only a dedup record, so it is closed immediately.
  {
    printf '# Triage: apollo-ios#%s\n\n' "$n"
    cat "$tmp/triage-section.md"
    printf '\nThe reply above was posted automatically. This PR is a closed tracking record; reopen it and comment with `@claude` if follow-up is needed.\n'
    printf '\n---\n_Workflow run: %s_\n' "$RUN_URL"
  } >"$tmp/tracking-body.md"
  tracking_url="$(open_tracking_pr "[triage] apollo-ios#${n}: ${title}" "$tmp/tracking-body.md")"
  gh pr close "$tracking_url" --repo "$DEV_REPO" --delete-branch >/dev/null
  echo "Reply posted; closed tracking PR: $tracking_url" >&2
  slack_notify "$(printf ':speech_balloon: *Apollo iOS triage replied to a reporter*\n*%s* (apollo-ios#%s) — %s / %s confidence\n%s\nReply: %s\nRecord: %s' \
    "$title" "$n" "$category" "$confidence" "$summary" "$posted_comment_url" "$tracking_url")"
else
  labels=(--label "needs-input")
  [[ -n "$response_draft" ]] && labels+=(--label "response-ready")
  {
    printf '# Triage: apollo-ios#%s\n\n' "$n"
    cat "$tmp/triage-section.md"
    printf '\n## Next steps\n\nThis draft PR is a tracking record opened by automated triage; it contains no file changes. Reply with a comment mentioning `@claude`, for example:\n\n'
    printf -- '- `@claude post the draft reply on the upstream issue and close this PR`\n'
    printf -- '- `@claude the reporter is on 2.3.0 and uses ApolloSQLite; implement the fix on this branch`\n'
    printf -- '- `@claude this is expected behavior; reply upstream explaining why, then close this PR`\n'
    printf '\nWhen a fix lands on this branch, Claude marks the PR ready for review.\n'
    printf '\n---\n_Workflow run: %s_\n' "$RUN_URL"
  } >"$tmp/tracking-body.md"
  tracking_url="$(open_tracking_pr "[triage] apollo-ios#${n}: ${title}" "$tmp/tracking-body.md" \
    "${labels[@]}" ${ASSIGNEE:+--assignee "$ASSIGNEE"})"
  echo "Opened tracking PR: $tracking_url" >&2
  q_text=""
  [[ -n "$questions" ]] && q_text="${nl}${nl}*Questions:*${nl}${questions}"
  d_text=""
  [[ -n "$response_draft" ]] && d_text="${nl}${nl}*Draft reply (not posted):*${nl}${response_draft}"
  slack_notify "$(printf ':mag: *Apollo iOS triage needs your input*\n*%s* (apollo-ios#%s) — %s / %s confidence\n%s\n%s%s%s\n\nAnswer with an @claude comment: %s' \
    "$title" "$n" "$category" "$confidence" "$issue_url" "$summary" "$q_text" "$d_text" "$tracking_url")"
fi

{
  echo "tracking_url=$tracking_url"
  echo "confidence=$confidence"
  echo "has_fix=$has_fix"
  echo "posted_comment_url=$posted_comment_url"
} >>"${GITHUB_OUTPUT:-/dev/null}"
