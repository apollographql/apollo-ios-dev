#!/usr/bin/env bash
#
# Publishes the outcome of one Claude triage run.
#
#   * High-confidence verified bug fix  -> pushes Claude's branch, opens a ready PR.
#   * High-confidence reply             -> posted on the upstream issue under a bot identity
#                                          via post-upstream-reply.sh; never a person.
#   * Everything else                   -> a Slack message to the maintainers with the
#                                          summary, questions, and draft reply. No PR, no
#                                          issue, nothing written to git.
#
# Dedup is a small state file (issue -> last triaged-at) maintained by
# triage-state.sh; every outcome stamps it.
#
# Usage: publish-result.sh <result.json>
#
# Environment:
#   GH_TOKEN               token for dev-repo pushes, PRs, and the state branch
#   UPSTREAM_TOKEN         optional bot app token with issues:write on UPSTREAM_REPO
#   UPSTREAM_DISPATCH_TOKEN
#                          token with write access to UPSTREAM_REPO, used only to fire the
#                          post-triage-reply relay; the comment is authored by that repo's
#                          github-actions[bot]. With neither set, posting is disabled and the
#                          draft goes to Slack instead.
#   UPSTREAM_REPO          default apollographql/apollo-ios
#   DEV_REPO               default apollographql/apollo-ios-dev
#   STATE_BRANCH           default claude-triage-state
#   TRIAGE_LABEL           default claude-triage (applied to fix PRs)
#   ASSIGNEE               GitHub login requested as reviewer on fix PRs
#   AUTO_COMMENT           default true; "false" disables posting even when configured
#   TRIAGED_AT             ISO-8601 time the triage run read the issue (default: now)
#   TRIGGER_REASON         new | reporter-followup | manual (informational)
#   RUN_URL                link to the workflow run
#   ISSUE_NUMBER           upstream issue number (required)
#   SLACK_BOT_TOKEN, SLACK_CHANNEL_ID
#                          see scripts/claude-notify/slack-notify.sh; posted in strict
#                          mode, so a failed Slack post fails the job

set -Eeuo pipefail

result_file="${1:?usage: publish-result.sh <result.json>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-apollographql/apollo-ios}"
DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
TRIAGE_LABEL="${TRIAGE_LABEL:-claude-triage}"
AUTO_COMMENT="${AUTO_COMMENT:-true}"
UPSTREAM_TOKEN="${UPSTREAM_TOKEN:-}"
UPSTREAM_DISPATCH_TOKEN="${UPSTREAM_DISPATCH_TOKEN:-}"
TRIAGED_AT="${TRIAGED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
RUN_URL="${RUN_URL:-}"
n="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
[[ "$n" =~ ^[0-9]+$ ]] || { echo "ISSUE_NUMBER must be an integer" >&2; exit 2; }
tmp="${RUNNER_TEMP:-/tmp}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issue_url="https://github.com/${UPSTREAM_REPO}/issues/${n}"
branch="claude/triage/apollo-ios-${n}"
push_url="https://x-access-token:${GH_TOKEN}@github.com/${DEV_REPO}.git"
nl=$'\n'

# Slack is the only record for most outcomes, so a rejected or unconfigured post
# must fail the job rather than vanish.
slack_notify() {
  SLACK_STRICT=1 "$here/../claude-notify/slack-notify.sh" "$1"
}

on_error() {
  local line="$1"
  [[ -e "$tmp/.publish-error-reported" ]] && return 0
  touch "$tmp/.publish-error-reported"
  echo "publish-result.sh failed at line ${line}" >&2
  slack_notify ":rotating_light: Apollo iOS triage publish failed for ${issue_url} (script line ${line}). Run: ${RUN_URL}" || true
}
trap 'on_error $LINENO' ERR

stamp_state() {
  "$here/triage-state.sh" stamp "$n" "$TRIAGED_AT"
}

# Model-authored text shown in the dev repo: remove planted stamps, defuse @mentions.
zwsp="$(printf '\xe2\x80\x8b')"
sanitize_internal() {
  sed -e '/<!-- *claude-triage/d' -e "s/@\([A-Za-z0-9]\)/@${zwsp}\1/g"
}

remote_branch_exists() {
  git ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1
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
  stamp_state
  slack_notify "$(printf ':warning: *Apollo iOS triage produced no result* for %s\nRun: %s\nRe-run `Claude Issue Triage` with `issue_number=%s` and `force=true` after checking the log.' \
    "$issue_url" "$RUN_URL" "$n")"
  echo "confidence=" >>"${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

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
  stamp_state
  echo "Reporter follow-up needs no action; state re-stamped." >&2
  { echo "confidence=$confidence"; echo "has_fix=false"; echo "posted_comment_url="; } >>"${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

posted_comment_url=""
post_unconfirmed=false
if [[ -n "$response_draft" && "$confidence" == "high" && "$category" != "feature" && "$category" != "unclear" ]]; then
  if [[ "$AUTO_COMMENT" == "true" && ( -n "$UPSTREAM_TOKEN" || -n "$UPSTREAM_DISPATCH_TOKEN" ) ]]; then
    printf '%s' "$response_draft" | sed '/<!-- *claude-triage/d' >"$tmp/reply-body.md"
    rc=0
    UPSTREAM_TOKEN="$UPSTREAM_TOKEN" UPSTREAM_DISPATCH_TOKEN="$UPSTREAM_DISPATCH_TOKEN" \
      "$here/post-upstream-reply.sh" "$n" "$tmp/reply-body.md" >"$tmp/post-reply.out" 2>"$tmp/post-reply.log" || rc=$?
    posted_comment_url="$(cat "$tmp/post-reply.out")"
    cat "$tmp/post-reply.log" >&2
    if [[ $rc -eq 0 && -n "$posted_comment_url" ]]; then
      echo "Posted upstream comment: $posted_comment_url" >&2
      # The comment is the first irreversible action; record it before anything
      # else can fail so a later error cannot cause a repeat post next run.
      stamp_state
    else
      posted_comment_url=""
      [[ $rc -eq 2 ]] && post_unconfirmed=true
      echo "Upstream reply not confirmed (exit $rc); routing draft to Slack." >&2
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

# Shared Slack body: everything a maintainer needs without leaving Slack.
details="$(printf '*%s* (apollo-ios#%s) — %s / %s confidence\n%s\n\n%s' "$title" "$n" "$category" "$confidence" "$issue_url" "$summary")"
[[ -n "$confidence_reason" ]] && details+="${nl}_${confidence_reason}_"
[[ -n "$affected" ]] && details+="${nl}Affected: \`${affected}\`"
[[ -n "$related" ]] && details+="${nl}${nl}*Related:*${nl}${related}"
[[ -n "$questions" ]] && details+="${nl}${nl}*Questions for you:*${nl}${questions}"
if [[ -s "$tmp/uncommitted-status.txt" ]]; then
  details+="${nl}${nl}_Uncommitted changes from the run were discarded; the diff is in the run artifact._"
fi

pr_url=""
if [[ "$has_fix" == true ]]; then
  pr_title="$(str '.fix.pr_title' "" | head -c 100 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  [[ -z "$pr_title" ]] && pr_title="Fix: ${title}"
  pr_title="${pr_title} (apollo-ios#${n})"
  {
    str '.fix.pr_body' "" | sanitize_internal
    printf '\n\n**Verification:** %s\n' "$fix_verification"
    printf '\nRelated to %s (upstream issues do not auto-close from this repo; close it after release).\n' "$issue_url"
    [[ -n "$posted_comment_url" ]] && printf '\nReply posted upstream: %s\n' "$posted_comment_url"
    printf '\n---\n\n<details><summary>Automated triage details</summary>\n\n%s\n\n_Workflow run: %s_\n\n</details>\n' \
      "$(printf '**Category:** %s  \n**Confidence:** %s  \n**Trigger:** %s\n\n%s\n' "$category" "$confidence" "$trigger" "$summary")" "$RUN_URL"
  } >"$tmp/pr-body.md"
  git push -q "$push_url" "${fix_branch}:refs/heads/${fix_branch}"
  pr_url="$(gh pr create --repo "$DEV_REPO" --base main --head "$fix_branch" --title "$pr_title" --body-file "$tmp/pr-body.md")"
  pr_number="${pr_url##*/}"
  gh api -X POST "repos/${DEV_REPO}/issues/${pr_number}/labels" -f "labels[]=${TRIAGE_LABEL}" >/dev/null || echo "Could not label PR ${pr_number}" >&2
  [[ -n "${ASSIGNEE:-}" ]] && { gh api -X POST "repos/${DEV_REPO}/pulls/${pr_number}/requested_reviewers" -f "reviewers[]=${ASSIGNEE}" >/dev/null || echo "Could not request reviewer ${ASSIGNEE}" >&2; }
  echo "Opened fix PR: $pr_url" >&2
fi

stamp_state

if [[ "$has_fix" == true ]]; then
  reply_line=""
  [[ -n "$posted_comment_url" ]] && reply_line="${nl}Reply posted: ${posted_comment_url}"
  [[ "$post_unconfirmed" == true ]] && reply_line="${nl}:warning: A reply was dispatched to the upstream relay but not confirmed; check the issue before posting manually."
  slack_notify "$(printf ':white_check_mark: *Apollo iOS triage opened a fix PR*\n%s\nPR: %s%s\nRun: %s' "$details" "$pr_url" "$reply_line" "$RUN_URL")"
elif [[ -n "$posted_comment_url" ]]; then
  slack_notify "$(printf ':speech_balloon: *Apollo iOS triage replied to a reporter*\n%s\nReply: %s\nRun: %s' "$details" "$posted_comment_url" "$RUN_URL")"
else
  draft_block=""
  if [[ -n "$response_draft" ]]; then
    if [[ "$post_unconfirmed" == true ]]; then
      draft_block="${nl}${nl}:warning: *A reply was dispatched to the upstream relay but not confirmed. Check the issue before posting this manually:*${nl}${response_draft}"
    else
      draft_block="${nl}${nl}*Draft reply (not posted; paste it on the issue if you agree):*${nl}${response_draft}"
    fi
  fi
  slack_notify "$(printf ':mag: *Apollo iOS triage needs your input*\n%s%s\n\nTo re-run after acting: `gh workflow run claude-issue-triage.yml -f issue_number=%s -f force=true`\nRun: %s' \
    "$details" "$draft_block" "$n" "$RUN_URL")"
fi

{
  echo "pr_url=$pr_url"
  echo "confidence=$confidence"
  echo "has_fix=$has_fix"
  echo "posted_comment_url=$posted_comment_url"
} >>"${GITHUB_OUTPUT:-/dev/null}"
