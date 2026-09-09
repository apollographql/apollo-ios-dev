#!/usr/bin/env bash
#
# Publishes the outcome of one Claude triage run.
#
#   * High-confidence verified bug fix  -> pushes Claude's branch, opens a ready PR.
#   * High-confidence reply             -> posted on the upstream issue under a bot
#                                          identity via post-upstream-reply.sh; never a person.
#   * Anything else                     -> draft tracking PR on an empty commit (no files
#                                          committed); summary, questions, and draft reply
#                                          live in the PR body only.
#   * Slack alert for every outcome and for any publish failure.
#
# The tracking or fix PR is the dedup record: its body carries
# `<!-- claude-triage issue=N triaged-at=... -->`, which discovery reads.
#
# Usage: publish-result.sh <result.json>
#
# Environment:
#   GH_TOKEN               token for dev-repo pushes and PRs (bot app, else maintainer PAT)
#   UPSTREAM_TOKEN         optional bot app token with issues:write on UPSTREAM_REPO (direct post)
#   UPSTREAM_DISPATCH_TOKEN
#                          token with write access to UPSTREAM_REPO used only to fire the
#                          post-triage-reply relay; the comment is authored by that repo's
#                          github-actions[bot]. With neither set, posting is disabled and the
#                          draft is routed to the maintainer.
#   UPSTREAM_REPO          default apollographql/apollo-ios
#   DEV_REPO               default apollographql/apollo-ios-dev
#   TRIAGE_LABEL           default claude-triage
#   ASSIGNEE               GitHub login alerted on results that need input
#   AUTO_COMMENT           default true; "false" disables posting even with a bot token
#   TRIAGED_AT             ISO-8601 time the triage run read the issue (default: now)
#   TRIGGER_REASON         new | reporter-followup | manual (informational)
#   RUN_URL                link to the workflow run
#   ISSUE_NUMBER           upstream issue number (required)
#   SLACK_BOT_TOKEN        optional
#   SLACK_CHANNEL_ID       optional channel or member ID

set -Eeuo pipefail

result_file="${1:?usage: publish-result.sh <result.json>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-apollographql/apollo-ios}"
DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
TRIAGE_LABEL="${TRIAGE_LABEL:-claude-triage}"
AUTO_COMMENT="${AUTO_COMMENT:-true}"
UPSTREAM_TOKEN="${UPSTREAM_TOKEN:-}"
UPSTREAM_DISPATCH_TOKEN="${UPSTREAM_DISPATCH_TOKEN:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIAGED_AT="${TRIAGED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
RUN_URL="${RUN_URL:-}"
n="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
[[ "$n" =~ ^[0-9]+$ ]] || { echo "ISSUE_NUMBER must be an integer" >&2; exit 2; }
tmp="${RUNNER_TEMP:-/tmp}"
issue_url="https://github.com/${UPSTREAM_REPO}/issues/${n}"
branch="claude/triage/apollo-ios-${n}"
push_url="https://x-access-token:${GH_TOKEN}@github.com/${DEV_REPO}.git"
nl=$'\n'

slack_notify() {
  [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]] && return 0
  jq -n --arg channel "$SLACK_CHANNEL_ID" --arg text "${1:0:30000}" \
    '{channel: $channel, text: $text, unfurl_links: false}' \
    | curl -sS -X POST https://slack.com/api/chat.postMessage \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H "Content-Type: application/json; charset=utf-8" \
        --data @- \
    | jq -r 'if .ok then "Slack: sent" else "Slack: failed: " + (.error // "unknown") end' >&2 || true
}

# A marker file, not a variable: the trap also fires inside command substitutions.
on_error() {
  local line="$1"
  [[ -e "$tmp/.publish-error-reported" ]] && return 0
  touch "$tmp/.publish-error-reported"
  echo "publish-result.sh failed at line ${line}" >&2
  slack_notify ":rotating_light: Apollo iOS triage publish failed for ${issue_url} (script line ${line}). Run: ${RUN_URL}"
}
trap 'on_error $LINENO' ERR

ensure_label() {
  gh label create "$1" --repo "$DEV_REPO" --color "$2" --description "$3" --force >/dev/null 2>&1 || true
}
ensure_label "$TRIAGE_LABEL" "1D76DB" "Automated triage of an apollo-ios issue"
ensure_label "needs-input" "D93F0B" "Automated triage needs a maintainer decision"
ensure_label "response-ready" "5319E7" "Automated triage drafted a reply awaiting approval"

# Model-authored text that is written into dev-repo PRs and comments: remove any
# planted dedup stamps and defuse @mentions so reporters are not pinged from here.
sanitize_internal() {
  sed -e '/<!-- *claude-triage/d' -e 's/@\([A-Za-z0-9]\)/@\xe2\x80\x8b\1/g'
}

triage_marker() {
  printf '\n<!-- claude-triage issue=%s triaged-at=%s -->\n' "$n" "$TRIAGED_AT"
}

# The newest tracking or fix PR for this issue, open or closed. Prints its URL.
latest_record_url() {
  gh pr list --repo "$DEV_REPO" --label "$TRIAGE_LABEL" --state all --limit 20 \
    --search "apollo-ios#${n} in:title sort:updated-desc" --json url,body \
    | jq -r --arg n "$n" 'map(select(.body | test("<!-- claude-triage issue=" + $n + " ")))[0].url // empty'
}

# Re-stamps the newest record so discovery does not re-trigger on the same reporter comments.
stamp_latest_record() {
  local url body
  url="$(latest_record_url)"
  [[ -z "$url" ]] && return 1
  body="$(gh pr view "$url" --repo "$DEV_REPO" --json body --jq '.body')"
  { printf '%s\n' "$body" | sed '/<!-- *claude-triage issue=/d'; triage_marker; } >"$tmp/restamped-body.md"
  gh pr edit "$url" --repo "$DEV_REPO" --body-file "$tmp/restamped-body.md" >/dev/null || return 1
  echo "$url"
}

existing_open_pr() {
  gh pr list --repo "$DEV_REPO" --head "$1" --state open --json url --jq '.[0].url // empty'
}

remote_branch_exists() {
  git ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1
}

# Creates a PR for $1 (head branch), or updates the open one on a re-triage.
# $2 = title, $3 = body file, $4 = draft|ready, rest = --label/--assignee/--reviewer flags.
create_or_update_pr() {
  local head="$1" title="$2" body_file="$3" mode="$4"; shift 4
  local url flag value
  triage_marker >>"$body_file"
  url="$(existing_open_pr "$head")"
  if [[ -n "$url" ]]; then
    gh pr edit "$url" --repo "$DEV_REPO" --title "$title" --body-file "$body_file" >/dev/null
    gh pr comment "$url" --repo "$DEV_REPO" --body "Re-triaged by automation; description updated. Run: ${RUN_URL}" >/dev/null
  else
    local draft_flag=()
    [[ "$mode" == "draft" ]] && draft_flag=(--draft)
    url="$(gh pr create --repo "$DEV_REPO" --base main --head "$head" ${draft_flag[@]+"${draft_flag[@]}"} \
      --title "$title" --body-file "$body_file")"
  fi
  # Labels, assignees, and reviewers are best effort: a rejected login must not lose the PR.
  while [[ $# -gt 0 ]]; do
    flag="$1"; value="${2:-}"; shift 2 || break
    case "$flag" in
      --label) gh pr edit "$url" --repo "$DEV_REPO" --add-label "$value" >/dev/null 2>&1 || true ;;
      --assignee) gh pr edit "$url" --repo "$DEV_REPO" --add-assignee "$value" >/dev/null 2>&1 || true ;;
      --reviewer) gh pr edit "$url" --repo "$DEV_REPO" --add-reviewer "$value" >/dev/null 2>&1 || true ;;
    esac
  done
  echo "$url"
}

# Opens (or updates) the draft tracking PR. $1 = title, $2 = body file, rest = flags.
# Never rewrites a branch that already exists on the remote: a human or the follow-up
# bot may have pushed to it. Uncommitted work Claude left behind is saved to the run
# artifact, and any commits it left on the canonical branch are kept.
open_tracking_pr() {
  local title="$1" body_file="$2"; shift 2
  if remote_branch_exists "$branch"; then
    printf '\n> Branch `%s` already existed on the remote and was left untouched.\n' "$branch" >>"$body_file"
  else
    if git rev-parse --verify --quiet "$branch" >/dev/null && \
       [[ "$(git rev-list --count "origin/main..$branch")" -gt 0 ]]; then
      git checkout -q "$branch"
      printf '\n> **Note:** this branch carries an unverified fix attempt from the triage run. Review it before building on it.\n' >>"$body_file"
    else
      git checkout -q -B "$branch" origin/main
      git commit -q --allow-empty -m "Triage tracking for apollo-ios#${n}"
    fi
    git push -q "$push_url" "${branch}:refs/heads/${branch}"
  fi
  create_or_update_pr "$branch" "$title" "$body_file" draft --label "$TRIAGE_LABEL" "$@"
}

# Preserve whatever Claude left uncommitted, then make the tree safe to branch from.
if [[ -n "$(git status --porcelain)" ]]; then
  git status --porcelain >"$tmp/uncommitted-status.txt"
  git diff >"$tmp/uncommitted.diff" || true
  git diff --cached >>"$tmp/uncommitted.diff" || true
  echo "Uncommitted changes found; saved to the run artifact and discarded." >&2
  git reset -q --hard
  git clean -fdq
fi
git fetch -q origin "+refs/heads/main:refs/remotes/origin/main"

if [[ ! -s "$result_file" ]] || ! jq -e . "$result_file" >/dev/null 2>&1; then
  printf 'Automated triage of %s did not produce a result.\n\nWorkflow run: %s\n\nRe-run `Claude Issue Triage` with `issue_number=%s` and `force=true` after fixing the cause, then close this PR.\n' \
    "$issue_url" "$RUN_URL" "$n" >"$tmp/tracking-body.md"
  url="$(open_tracking_pr "[triage] apollo-ios#${n}: triage failed" "$tmp/tracking-body.md" \
    --label "needs-input" ${ASSIGNEE:+--assignee "$ASSIGNEE"})"
  slack_notify ":warning: Apollo iOS triage failed for ${issue_url}. Tracking: ${url}"
  echo "tracking_url=$url" >>"${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

# Read fields defensively: the result is model output.
r() { jq -r "$1" "$result_file"; }
str() { jq -r --arg d "$2" "($1) as \$v | if (\$v|type) == \"string\" then \$v else \$d end" "$result_file"; }
list() { jq -r "($1 // []) | if type == \"array\" then map(if type == \"string\" then . else tojson end) else [tojson] end | map(\"- \" + .) | join(\"\\n\")" "$result_file"; }

title="$(str '.issue_title' "(untitled)" | head -c 200 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
category="$(str '.category' "unclear")"
confidence="$(str '.confidence' "low")"
confidence_reason="$(str '.confidence_reason' "" | sanitize_internal)"
summary="$(str '.summary' "(no summary)" | head -c 4000 | sanitize_internal)"
affected="$(str '.affected_area' "")"
questions="$(list '.questions_for_maintainer' | sanitize_internal)"
related="$(list '.related' | sanitize_internal)"
response_draft="$(str '.response_draft' "" | head -c 6000)"
fix_branch="$(str '.fix.branch' "")"
fix_verified="$(r '.fix.verified // false')"
fix_verification="$(str '.fix.verification' "not recorded")"
nothing_to_do="$(r '.nothing_to_do // false')"
trigger="${TRIGGER_REASON:-new}"

case "$category" in bug|question|feature|unclear) ;; *) category="unclear" ;; esac
case "$confidence" in high|medium|low) ;; *) confidence="low" ;; esac
if [[ "$confidence" == "high" && ( "$category" == "feature" || "$category" == "unclear" ) ]]; then
  confidence="medium"
  confidence_reason="${confidence_reason} (Capped: ${category} issues are never auto-actioned.)"
fi

if [[ "$nothing_to_do" == "true" && "$trigger" == "reporter-followup" ]]; then
  if url="$(stamp_latest_record)"; then
    gh pr comment "$url" --repo "$DEV_REPO" --body "$(printf 'Re-triaged after a reporter follow-up; no action needed.\n\n%s\n\n_Run: %s_' "$summary" "$RUN_URL")" >/dev/null
    echo "No action needed; re-stamped $url" >&2
    { echo "tracking_url=$url"; echo "confidence=$confidence"; echo "has_fix=false"; echo "posted_comment_url="; } >>"${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
  echo "nothing_to_do set but no tracking record found; falling through to open one." >&2
fi

posted_comment_url=""
post_unconfirmed=false
if [[ -n "$response_draft" && "$confidence" == "high" && "$category" != "feature" && "$category" != "unclear" ]]; then
  if [[ "$AUTO_COMMENT" == "true" && ( -n "$UPSTREAM_TOKEN" || -n "$UPSTREAM_DISPATCH_TOKEN" ) ]]; then
    printf '%s' "$response_draft" | sed '/<!-- *claude-triage/d' >"$tmp/reply-body.md"
    # No command substitution here: with errtrace a subshell inherits the ERR
    # trap, so the child's non-zero exit would fire it before the || is reached.
    rc=0
    UPSTREAM_TOKEN="$UPSTREAM_TOKEN" UPSTREAM_DISPATCH_TOKEN="$UPSTREAM_DISPATCH_TOKEN" \
      "$here/post-upstream-reply.sh" "$n" "$tmp/reply-body.md" >"$tmp/post-reply.out" 2>"$tmp/post-reply.log" || rc=$?
    posted_comment_url="$(cat "$tmp/post-reply.out")"
    cat "$tmp/post-reply.log" >&2
    if [[ $rc -eq 0 && -n "$posted_comment_url" ]]; then
      echo "Posted upstream comment: $posted_comment_url" >&2
    else
      posted_comment_url=""
      [[ $rc -eq 2 ]] && post_unconfirmed=true
      echo "Upstream reply not confirmed (exit $rc); routing draft to maintainer." >&2
    fi
  else
    echo "High-confidence reply not posted: AUTO_COMMENT=${AUTO_COMMENT}, upstream posting $([[ -n "$UPSTREAM_TOKEN$UPSTREAM_DISPATCH_TOKEN" ]] && echo configured || echo not configured)." >&2
  fi
fi

has_fix=false
if [[ "$category" == "bug" && "$confidence" == "high" && -n "$fix_branch" && "$fix_verified" == "true" ]]; then
  if [[ "$fix_branch" != "$branch" ]]; then
    echo "Refusing fix on branch '$fix_branch'; only '$branch' is publishable." >&2
    confidence="medium"; confidence_reason="${confidence_reason} (Fix was on an unexpected branch and was not published.)"
  elif [[ "$fix_verification" != *xcodebuild* ]]; then
    echo "Fix verification did not include a test run; not publishing." >&2
    confidence="medium"; confidence_reason="${confidence_reason} (Fix lacked a recorded xcodebuild test run.)"
  elif ! git rev-parse --verify --quiet "$fix_branch" >/dev/null || \
       [[ "$(git rev-list --count "origin/main..$fix_branch")" -eq 0 ]]; then
    echo "Fix branch '$fix_branch' has no commits ahead of origin/main." >&2
    confidence="medium"; confidence_reason="${confidence_reason} (Fix branch was empty at publish time.)"
  elif remote_branch_exists "$fix_branch" && ! git merge-base --is-ancestor "origin/$fix_branch" "$fix_branch" 2>/dev/null; then
    echo "Remote '$fix_branch' has commits this run does not include; not overwriting." >&2
    confidence="medium"; confidence_reason="${confidence_reason} (Remote branch already had other commits; fix not pushed.)"
  else
    has_fix=true
  fi
fi

{
  printf '**Upstream issue:** %s\n' "$issue_url"
  printf '**Category:** %s  \n**Confidence:** %s  \n**Trigger:** %s\n' "$category" "$confidence" "$trigger"
  [[ -n "$confidence_reason" ]] && printf '_%s_\n' "$confidence_reason"
  printf '\n## Summary\n\n%s\n' "$summary"
  [[ -n "$affected" ]] && printf '\n**Affected area:** `%s`\n' "$affected"
  [[ -n "$related" ]] && printf '\n## Related\n\n%s\n' "$related"
  [[ -n "$questions" ]] && printf '\n## Questions for the maintainer\n\n%s\n' "$questions"
  if [[ -n "$response_draft" ]]; then
    if [[ -n "$posted_comment_url" ]]; then
      printf '\n## Reply posted upstream\n\n%s\n\n<details><summary>Text</summary>\n\n%s\n\n</details>\n' "$posted_comment_url" "$(printf '%s' "$response_draft" | sanitize_internal)"
    elif [[ "$post_unconfirmed" == true ]]; then
      printf '\n## Draft reply (dispatched to the relay, not confirmed)\n\nCheck %s before posting this manually.\n\n%s\n' "$issue_url" "$(printf '%s' "$response_draft" | sanitize_internal)"
    else
      printf '\n## Draft reply (not posted)\n\n%s\n' "$(printf '%s' "$response_draft" | sanitize_internal)"
    fi
  fi
  if [[ -s "$tmp/uncommitted-status.txt" ]]; then
    printf '\n> Uncommitted changes from the run were discarded; the diff is in the run artifact.\n'
  fi
} >"$tmp/triage-section.md"

if [[ "$has_fix" == true ]]; then
  pr_title="$(str '.fix.pr_title' "" | head -c 100 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  [[ -z "$pr_title" ]] && pr_title="Fix: ${title}"
  pr_title="${pr_title} (apollo-ios#${n})"
  {
    str '.fix.pr_body' "" | sanitize_internal
    printf '\n\n**Verification:** %s\n' "$fix_verification"
    printf '\nRelated to %s (upstream issues do not auto-close from this repo; close it after release).\n\n---\n\n<details><summary>Automated triage details</summary>\n\n' "$issue_url"
    cat "$tmp/triage-section.md"
    printf '\n_Workflow run: %s_\n\n</details>\n' "$RUN_URL"
  } >"$tmp/pr-body.md"
  git push -q "$push_url" "${fix_branch}:refs/heads/${fix_branch}"
  tracking_url="$(create_or_update_pr "$fix_branch" "$pr_title" "$tmp/pr-body.md" ready \
    --label "$TRIAGE_LABEL" ${ASSIGNEE:+--reviewer "$ASSIGNEE"})"
  echo "Opened fix PR: $tracking_url" >&2
  reply_line=""
  [[ -n "$posted_comment_url" ]] && reply_line="Reply posted: ${posted_comment_url}${nl}"
  [[ "$post_unconfirmed" == true ]] && reply_line=":warning: A reply was dispatched to the upstream relay but not confirmed; check ${issue_url} before posting manually.${nl}"
  slack_notify "$(printf ':white_check_mark: *Apollo iOS triage opened a fix PR*\n*%s* (apollo-ios#%s)\n%s\n%sPR: %s' \
    "$title" "$n" "$summary" "$reply_line" "$tracking_url")"
elif [[ -n "$posted_comment_url" ]]; then
  # The reply already went out; reporter follow-ups re-trigger triage, so the record is closed.
  {
    printf '# Triage: apollo-ios#%s\n\n' "$n"
    cat "$tmp/triage-section.md"
    printf '\nThe reply above was posted automatically. This PR is a closed tracking record; a reporter follow-up re-triggers triage. Reopen it and comment with `@claude` to intervene.\n'
    printf '\n---\n_Workflow run: %s_\n' "$RUN_URL"
  } >"$tmp/tracking-body.md"
  tracking_url="$(open_tracking_pr "[triage] apollo-ios#${n}: ${title}" "$tmp/tracking-body.md")"
  gh pr close "$tracking_url" --repo "$DEV_REPO" --delete-branch >/dev/null || true
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
  if [[ -n "$response_draft" ]]; then
    if [[ "$post_unconfirmed" == true ]]; then
      d_text="${nl}${nl}:warning: *A reply was dispatched to the upstream relay but not confirmed. Check ${issue_url} before posting this manually:*${nl}${response_draft}"
    else
      d_text="${nl}${nl}*Draft reply (not posted):*${nl}${response_draft}"
    fi
  fi
  slack_notify "$(printf ':mag: *Apollo iOS triage needs your input*\n*%s* (apollo-ios#%s) — %s / %s confidence\n%s\n%s%s%s\n\nAnswer with an @claude comment: %s' \
    "$title" "$n" "$category" "$confidence" "$issue_url" "$summary" "$q_text" "$d_text" "$tracking_url")"
fi

{
  echo "tracking_url=$tracking_url"
  echo "confidence=$confidence"
  echo "has_fix=$has_fix"
  echo "posted_comment_url=$posted_comment_url"
} >>"${GITHUB_OUTPUT:-/dev/null}"
