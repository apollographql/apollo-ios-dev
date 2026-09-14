#!/usr/bin/env bash
#
# Keeps a single status comment on a PR up to date when the Claude review does
# not run because CI failed. The comment is found by a hidden marker and edited
# in place so it never accumulates.
#
# Usage: note-review-status.sh <pr-number> <status> <sha>
# Environment: GH_TOKEN, REPO (default GITHUB_REPOSITORY),
#              RERUN_HINT (sentence appended to the ci-failed / timed-out notes;
#              defaults to the same-repo "runs again on a new push" wording, which
#              the fork caller overrides since a push does not re-trigger there)

set -euo pipefail
pr="${1:?pr number}"; status="${2:?status}"; sha="${3:?sha}"
REPO="${REPO:-${GITHUB_REPOSITORY:?}}"
marker="<!-- claude-review-status -->"

# The fork path has no `synchronize` trigger, so a push does not re-run the review
# there; the caller passes the correct hint. Default suits the same-repo path.
rerun_hint="${RERUN_HINT:-It runs again automatically when CI passes on a new push.}"
case "$status" in
  ci-failed) text="CI failed or was cancelled on \`${sha:0:9}\`, so the automated review did not run. ${rerun_hint}" ;;
  timed-out) text="CI on \`${sha:0:9}\` did not finish within the review's wait window, so the automated review did not run. ${rerun_hint}" ;;
  *)         text="The automated review did not run on \`${sha:0:9}\` (\`${status}\`)." ;;
esac
body="$(printf '%s\n%s' "$marker" "$text")"

existing="$(gh api --paginate "repos/${REPO}/issues/${pr}/comments?per_page=100" \
  | jq -r --arg m "$marker" '.[] | select(.body | startswith($m)) | .id' | head -1)"
if [[ -n "$existing" ]]; then
  gh api -X PATCH "repos/${REPO}/issues/comments/${existing}" -f body="$body" >/dev/null
else
  gh api -X POST "repos/${REPO}/issues/${pr}/comments" -f body="$body" >/dev/null
fi
echo "Review status noted: $status"
