#!/usr/bin/env bash
#
# Waits for every other check run on a commit to finish and reports whether
# they all passed. Used so the Claude review starts only once CI is green.
#
# Usage: wait-for-ci.sh <sha>
#
# Environment:
#   GH_TOKEN          token with checks:read on the repo
#   REPO              owner/name (default: GITHUB_REPOSITORY)
#   SELF_CHECK_NAME   check run name of the calling job, ignored while waiting
#   GRACE_SECONDS     time to allow other workflows to create their check runs (default 90)
#   TIMEOUT_SECONDS   give up after this long (default 2700)
#   POLL_SECONDS      poll interval (default 30)
#
# Prints one of: green, red, timeout. Exit code is 0 for green, 1 otherwise.

set -euo pipefail

sha="${1:?usage: wait-for-ci.sh <sha>}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY required}}"
SELF_CHECK_NAME="${SELF_CHECK_NAME:-}"
GRACE_SECONDS="${GRACE_SECONDS:-90}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-2700}"
POLL_SECONDS="${POLL_SECONDS:-30}"

# Each line: <name>\t<status>\t<conclusion>, excluding this job's own check run.
other_checks() {
  gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" --paginate \
    --jq '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion // "")"' \
    | awk -F'\t' -v self="$SELF_CHECK_NAME" '$1 != self'
}

sleep "$GRACE_SECONDS"
start=$(date +%s)
while true; do
  checks="$(other_checks)"
  pending="$(awk -F'\t' '$2 != "completed"' <<<"$checks")"
  if [[ -z "$pending" ]]; then
    failed="$(awk -F'\t' '$3 != "success" && $3 != "skipped" && $3 != "neutral"' <<<"$checks" || true)"
    if [[ -n "$failed" ]]; then
      echo "Checks not passing:" >&2
      echo "$failed" >&2
      echo "red"
      exit 1
    fi
    echo "All $(grep -c . <<<"$checks" || echo 0) other checks passed." >&2
    echo "green"
    exit 0
  fi
  if (( $(date +%s) - start > TIMEOUT_SECONDS )); then
    echo "Timed out waiting for:" >&2
    echo "$pending" >&2
    echo "timeout"
    exit 1
  fi
  echo "Waiting on $(grep -c . <<<"$pending") check(s)..." >&2
  sleep "$POLL_SECONDS"
done
