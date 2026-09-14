#!/usr/bin/env bash
#
# Prints the open fork pull requests that are waiting on a human decision about
# whether the automated Claude review may run on them. Consumed by
# notify-fork-review.sh (catch-up mode), which surfaces them in Slack.
#
# "Waiting on a decision" means all of:
#   * open and not a draft
#   * from a fork (cross-repository head), so ci-tests.yml's same-repo review
#     path never touches it
#   * author is not one of the known bots
#   * carries neither the approve label (TRIGGER_LABEL, default "safe to review")
#     nor the decline label (DECLINE_LABEL, default "fork-review-declined")
#
# A PR leaves this list the moment either label is applied, so an approved or
# declined PR is never re-surfaced.
#
# Output: a JSON array, newest PR first, of
#   { "number": N, "title": "...", "author": "...", "url": "...", "headSha": "..." }
#
# Usage: list-pending-fork-prs.sh
# Environment:
#   GH_TOKEN        token with pull-requests:read on REPO
#   REPO            default GITHUB_REPOSITORY
#   TRIGGER_LABEL   default "safe to review"
#   DECLINE_LABEL   default "fork-review-declined"
#   LIMIT           default 200 (most recent open PRs scanned)

set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY required}}"
TRIGGER_LABEL="${TRIGGER_LABEL:-safe to review}"
DECLINE_LABEL="${DECLINE_LABEL:-fork-review-declined}"
LIMIT="${LIMIT:-200}"

gh pr list --repo "$REPO" --state open --limit "$LIMIT" \
  --json number,title,author,url,isDraft,isCrossRepository,headRefOid,labels \
  | jq -c --arg approve "$TRIGGER_LABEL" --arg decline "$DECLINE_LABEL" '
      [ .[]
        | select(.isCrossRepository == true)
        | select(.isDraft == false)
        | select((.author.is_bot // false) == false)
        | ([ .labels[].name ]) as $names
        | select(($names | index($approve)) == null)
        | select(($names | index($decline)) == null)
        | { number: .number,
            title:  (.title // ""),
            author: (.author.login // "unknown"),
            url:    .url,
            headSha: .headRefOid } ]
      | sort_by(-.number)'
