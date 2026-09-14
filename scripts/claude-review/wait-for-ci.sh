#!/usr/bin/env bash
#
# Blocks until every "CI Tests" check on a PR's head commit has finished, then
# reports whether they all passed. Used by claude-fork-pr-review.yml, where the
# review runs in a separate workflow and so cannot express the dependency with
# `needs:` the way ci-tests.yml does.
#
# Only the base repo's "CI Tests" workflow gates the review. Everything else on
# the rollup is deliberately ignored: the CLA status, deploy previews, the
# CircleCI security scans, the AI style review, check-pr-metadata, and this
# review workflow's own check say nothing about whether the code compiles, and a
# fork PR can leave any of them failing or pending. Selecting "CI Tests"
# positively (its check runs carry workflowName "CI Tests"; bare status contexts
# carry none) also excludes this workflow's own review check without naming it.
#
# Usage: wait-for-ci.sh <pr-number> <head-sha>
# Environment: GH_TOKEN, REPO (default GITHUB_REPOSITORY),
#              WAIT_TIMEOUT_SECONDS (default 1800), WAIT_INTERVAL_SECONDS (default 30)
# Exit codes (the caller maps these to distinct PR statuses):
#   0  every CI Tests check passed
#   1  a CI Tests check failed
#   2  the head SHA moved during the wait (this run is superseded)
#   3  timed out, or CI Tests never registered a check on the head

set -euo pipefail
pr="${1:?pr number}"; sha="${2:?head sha}"
REPO="${REPO:-${GITHUB_REPOSITORY:?}}"
timeout_seconds="${WAIT_TIMEOUT_SECONDS:-1800}"
interval="${WAIT_INTERVAL_SECONDS:-30}"
ci_workflow="CI Tests"

deadline=$(( SECONDS + timeout_seconds ))

while true; do
  rollup="$(gh pr view "$pr" --repo "$REPO" --json headRefOid,statusCheckRollup)"

  # A push during the wait makes this run's verdict meaningless; the new head
  # gets its own run.
  head_now="$(jq -r '.headRefOid' <<<"$rollup")"
  if [[ "$head_now" != "$sha" ]]; then
    echo "Head moved ${sha:0:9} -> ${head_now:0:9} while waiting; abandoning this run."
    exit 2
  fi

  # Only CI Tests check runs. A COMPLETED run with a null conclusion is treated
  # as still pending (so it never counts as a pass or a spurious failure).
  checks="$(jq -c --arg wf "$ci_workflow" '
    [ (.statusCheckRollup // [])[]
      | select((.workflowName // "") == $wf)
      | { name:  (.name // .context),
          state: (if .status == "COMPLETED" then (.conclusion // "PENDING") else .status end) } ]' <<<"$rollup")"

  total="$(jq -r 'length' <<<"$checks")"
  pending="$(jq -r '[ .[] | select(.state | IN("QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED")) ] | length' <<<"$checks")"
  failed="$(jq -r '[ .[] | select(.state | IN("SUCCESS","SKIPPED","NEUTRAL","QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED") | not) ] | length' <<<"$checks")"

  if (( failed > 0 )); then
    echo "CI Tests failed on ${sha:0:9}:"
    jq -r '.[] | select(.state | IN("SUCCESS","SKIPPED","NEUTRAL","QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED","EXPECTED") | not) | "  \(.name): \(.state)"' <<<"$checks"
    exit 1
  fi

  # Success requires at least one CI Tests check to exist: an empty set means CI
  # has not registered yet (label applied early, or a first-time contributor's
  # run still awaiting approval), not that a commit nothing validated has passed.
  if (( total > 0 && pending == 0 )); then
    echo "All ${total} CI Tests check(s) passed on ${sha:0:9}."
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    if (( total == 0 )); then
      echo "Timed out after ${timeout_seconds}s: no CI Tests checks ever registered on ${sha:0:9}."
    else
      echo "Timed out after ${timeout_seconds}s with ${pending} CI Tests check(s) still running."
    fi
    exit 3
  fi

  if (( total == 0 )); then
    echo "No CI Tests checks registered yet on ${sha:0:9}; polling again in ${interval}s."
  else
    echo "${pending} CI Tests check(s) still running; polling again in ${interval}s."
  fi
  sleep "$interval"
done
