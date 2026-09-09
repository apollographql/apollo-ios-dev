#!/usr/bin/env bash
#
# Keeps a single status comment on a PR up to date when the Claude review does
# not run because CI failed. The comment is found by a hidden marker and edited
# in place so it never accumulates.
#
# Usage: note-review-status.sh <pr-number> <status> <sha>
# Environment: GH_TOKEN, REPO (default GITHUB_REPOSITORY)

set -euo pipefail
pr="${1:?pr number}"; status="${2:?status}"; sha="${3:?sha}"
REPO="${REPO:-${GITHUB_REPOSITORY:?}}"
marker="<!-- claude-review-status -->"

case "$status" in
  ci-failed) text="CI failed or was cancelled on \`${sha:0:9}\`, so the automated review did not run. It runs again automatically when CI passes on a new push." ;;
  *)         text="The automated review did not run on \`${sha:0:9}\` (\`${status}\`)." ;;
esac
body="$(printf '%s\n%s' "$marker" "$text")"

existing="$(gh api "repos/${REPO}/issues/${pr}/comments?per_page=100" --paginate \
  --jq --arg m "$marker" '.[] | select(.body | startswith($m)) | .id' | head -1)"
if [[ -n "$existing" ]]; then
  gh api -X PATCH "repos/${REPO}/issues/comments/${existing}" -f body="$body" >/dev/null
else
  gh api -X POST "repos/${REPO}/issues/${pr}/comments" -f body="$body" >/dev/null
fi
echo "Review status noted: $status"
