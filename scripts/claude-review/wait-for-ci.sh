#!/usr/bin/env bash
#
# Waits for every other check run on a pull request's head commit to finish and
# reports whether they all passed. Used so the Claude review starts only once CI
# is green.
#
# Usage: wait-for-ci.sh <pr-number>
#
# Environment:
#   GH_TOKEN          token with checks:read on the repo
#   REPO              owner/name (default: GITHUB_REPOSITORY)
#   SELF_CHECK_NAME   check run name of the calling job, ignored while waiting
#   GRACE_SECONDS     time to allow other workflows to register their check runs (default 90)
#   TIMEOUT_SECONDS   give up after this long (default 2700)
#   POLL_SECONDS      poll interval (default 30)
#
# Prints exactly one of:
#   green       every other check completed with success, skipped, or neutral
#   no-checks   nothing else ran on this commit (for example a docs-only PR)
#   red         at least one check failed or timed out
#   inconclusive  a check ended cancelled, stale, or action_required
#   timeout     checks were still pending after TIMEOUT_SECONDS
#   error       GitHub could not be queried after retries
# Exit code is 0 for green and no-checks, 1 otherwise.

set -euo pipefail

pr="${1:?usage: wait-for-ci.sh <pr-number>}"
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY required}}"
SELF_CHECK_NAME="${SELF_CHECK_NAME:-}"
GRACE_SECONDS="${GRACE_SECONDS:-90}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-2700}"
POLL_SECONDS="${POLL_SECONDS:-30}"

# Each line: <name>\t<status>\t<conclusion> for the PR's current head, excluding this job.
# `gh pr checks` is scoped to the PR, so checks from other PRs sharing the SHA are ignored.
other_checks() {
  local attempt out
  for attempt in 1 2 3 4; do
    if out="$(gh pr checks "$pr" --repo "$REPO" --json name,state,bucket \
        --jq '.[] | "\(.name)\t\(.state)\t\(.bucket)"' 2>/dev/null)"; then
      awk -F'\t' -v self="$SELF_CHECK_NAME" '$1 != self' <<<"$out"
      return 0
    fi
    sleep $((attempt * 15))
  done
  return 1
}

sleep "$GRACE_SECONDS"
start=$(date +%s)
while true; do
  if ! checks="$(other_checks)"; then
    echo "Could not read checks after retries." >&2
    echo "error"; exit 1
  fi
  # bucket: pass | fail | pending | skipping | cancel
  pending="$(awk -F'\t' '$3 == "pending"' <<<"$checks")"
  if [[ -z "$pending" ]]; then
    if [[ -z "$checks" ]]; then
      echo "No other checks on this commit." >&2
      echo "no-checks"; exit 0
    fi
    failed="$(awk -F'\t' '$3 == "fail"' <<<"$checks")"
    if [[ -n "$failed" ]]; then
      echo "Checks not passing:" >&2; echo "$failed" >&2
      echo "red"; exit 1
    fi
    other="$(awk -F'\t' '$3 != "pass" && $3 != "skipping"' <<<"$checks")"
    if [[ -n "$other" ]]; then
      echo "Checks ended without a verdict:" >&2; echo "$other" >&2
      echo "inconclusive"; exit 1
    fi
    echo "All $(grep -c . <<<"$checks") other checks passed." >&2
    echo "green"; exit 0
  fi
  if (( $(date +%s) - start > TIMEOUT_SECONDS )); then
    echo "Timed out waiting for:" >&2; echo "$pending" >&2
    echo "timeout"; exit 1
  fi
  echo "Waiting on $(grep -c . <<<"$pending") check(s)..." >&2
  sleep "$POLL_SECONDS"
done
