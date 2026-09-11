#!/usr/bin/env bash
#
# Blocks until every check on a PR's head commit has finished, then reports
# whether they all passed. Used by claude-fork-pr-review.yml, where the review
# runs in a separate workflow and so cannot express the dependency with
# `needs:` the way ci-tests.yml does.
#
# Checks belonging to this workflow are excluded from the wait; including them
# would deadlock, since one of them is the caller.
#
# Usage: wait-for-ci.sh <pr-number> <head-sha>
# Environment: GH_TOKEN, REPO (default GITHUB_REPOSITORY),
#              WAIT_TIMEOUT_SECONDS (default 1800), WAIT_INTERVAL_SECONDS (default 30)
# Exit: 0 when all checks succeeded, 1 when any failed or the wait timed out.

set -euo pipefail
pr="${1:?pr number}"; sha="${2:?head sha}"
REPO="${REPO:-${GITHUB_REPOSITORY:?}}"
timeout_seconds="${WAIT_TIMEOUT_SECONDS:-1800}"
interval="${WAIT_INTERVAL_SECONDS:-30}"
self_workflow="Claude PR Review (fork)"

deadline=$(( SECONDS + timeout_seconds ))

while true; do
  rollup="$(gh pr view "$pr" --repo "$REPO" --json headRefOid,statusCheckRollup)"

  # A push during the wait makes this run's verdict meaningless; the new head
  # gets its own run.
  head_now="$(jq -r '.headRefOid' <<<"$rollup")"
  if [[ "$head_now" != "$sha" ]]; then
    echo "Head moved ${sha:0:9} -> ${head_now:0:9} while waiting; abandoning this run."
    exit 1
  fi

  checks="$(jq -c --arg self "$self_workflow" '
    [ .statusCheckRollup[]
      | select((.workflowName // "") != $self)
      | { name:   (.name // .context),
          state:  (if .__typename == "StatusContext"
                   then .state
                   else (if .status == "COMPLETED" then .conclusion else .status end)
                   end) } ]' <<<"$rollup")"

  pending="$(jq -r '[ .[] | select(.state | IN("QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED")) ] | length' <<<"$checks")"
  failed="$(jq -r '[ .[] | select(.state | IN("SUCCESS","SKIPPED","NEUTRAL","QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED") | not) ] | length' <<<"$checks")"

  if (( failed > 0 )); then
    echo "CI failed on ${sha:0:9}:"
    jq -r '.[] | select(.state | IN("SUCCESS","SKIPPED","NEUTRAL","QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED") | not) | "  \(.name): \(.state)"' <<<"$checks"
    exit 1
  fi

  if (( pending == 0 )); then
    echo "All checks passed on ${sha:0:9}."
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    echo "Timed out after ${timeout_seconds}s with ${pending} check(s) still running:"
    jq -r '.[] | select(.state | IN("QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED")) | "  \(.name): \(.state)"' <<<"$checks"
    exit 1
  fi

  echo "${pending} check(s) still running; polling again in ${interval}s."
  sleep "$interval"
done
