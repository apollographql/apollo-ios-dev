#!/usr/bin/env bash
#
# Finds apollographql/apollo-ios issues that need a triage run and prints them
# as a JSON array of {"issue": N, "reason": "new" | "reporter-followup" | "manual"}.
#
# Two triggers:
#   new                new issue not yet in the state file
#   reporter-followup  the issue's author commented after our last triage
#                      (only the reporter counts; bots and other people do not)
#
# The record is triaged.json on the dev repo's state branch (see
# triage-state.sh): issue number -> last triaged-at, written by publish-result.sh.
#
# Usage:
#   discover-issues.sh                      # poll
#   discover-issues.sh --issue <N>          # exactly this issue (skipped if already triaged)
#   discover-issues.sh --issue <N> --force  # this issue, even if triaged
#
# Environment:
#   GH_TOKEN                 token with read access to both repos
#   UPSTREAM_REPO            default apollographql/apollo-ios
#   DEV_REPO                 default apollographql/apollo-ios-dev
#   STATE_BRANCH             default claude-triage-state
#   LOOKBACK_DAYS            default 3 (issues created or updated within this window)
#   MAX_PER_RUN              default 3

set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-apollographql/apollo-ios}"
DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
LOOKBACK_DAYS="${LOOKBACK_DAYS:-3}"
MAX_PER_RUN="${MAX_PER_RUN:-3}"

issue=""
force=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      issue="${2:-}"
      if ! [[ "$issue" =~ ^[0-9]+$ ]]; then
        echo "--issue requires a bare issue number, got '${issue}'" >&2
        exit 2
      fi
      shift 2 ;;
    --force) force=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# {"<issue>": "<last triaged-at>", ...} from the state branch; future stamps are clamped to now.
tracking_records() {
  local now here
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "$here/triage-state.sh" read | jq -c --arg now "$now" 'with_entries(.value |= (if . > $now then $now else . end))'
}

records="$(tracking_records)"

if [[ -n "$issue" ]]; then
  if [[ "$force" == true ]] || ! jq -e --arg n "$issue" '.[$n] != null' <<<"$records" >/dev/null; then
    jq -n -c --argjson n "$issue" '[{issue: $n, reason: "manual"}]'
  else
    echo "Issue #$issue was already triaged; use --force to re-triage." >&2
    echo '[]'
  fi
  exit 0
fi

if [[ "$(uname)" == "Darwin" ]]; then
  since="$(date -u -v-"${LOOKBACK_DAYS}"d +%Y-%m-%d)"
else
  since="$(date -u -d "${LOOKBACK_DAYS} days ago" +%Y-%m-%d)"
fi

new_issues="$(gh issue list --repo "$UPSTREAM_REPO" --state open --limit 100 \
  --search "created:>=${since} sort:created-asc" \
  --json number,author \
  | jq -c --argjson rec "$records" \
      '[ .[] | select(.author.is_bot | not) | select($rec[(.number|tostring)] == null)
         | {issue: .number, reason: "new"} ]')"

followups="$(gh issue list --repo "$UPSTREAM_REPO" --state open --limit 100 \
  --search "updated:>=${since} sort:updated-asc" \
  --json number,author,comments \
  | jq -c --argjson rec "$records" \
      '[ .[]
         | select(.author.is_bot | not)
         | . as $i
         | ($rec[(.number|tostring)]) as $last
         | select($last != null)
         | select([ .comments[]
                    | select(.author.login == $i.author.login)
                    | select(.author.login | endswith("[bot]") | not)
                    | select(.createdAt > $last) ] | length > 0)
         | {issue: .number, reason: "reporter-followup"} ]')"

# Follow-ups first (someone is waiting), then new issues oldest first; dedup keeps first occurrence.
jq -n -c --argjson new "$new_issues" --argjson fu "$followups" --argjson max "$MAX_PER_RUN" \
  '($fu + $new) | reduce .[] as $x ([]; if any(.[]; .issue == $x.issue) then . else . + [$x] end) | .[:$max]'
