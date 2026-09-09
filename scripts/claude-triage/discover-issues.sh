#!/usr/bin/env bash
#
# Finds apollographql/apollo-ios issues that need a triage run and prints them
# as a JSON array of {"issue": N, "reason": "new" | "reporter-followup" | "manual"}.
#
# Two triggers:
#   new                new issue with no tracking PR yet
#   reporter-followup  the issue's author commented after our last triage
#                      (only the reporter counts; bots and other people do not)
#
# The dev repo's tracking PRs (label `claude-triage`, `apollo-ios#<N>` in the
# title) are the record. publish-result.sh stamps each one with
# `<!-- claude-triage issue=N triaged-at=<ISO-8601> -->`; the newest stamp per
# issue is the last-triaged time.
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
#   TRIAGE_LABEL             default claude-triage
#   LOOKBACK_DAYS            default 3 (issues created or updated within this window)
#   MAX_PER_RUN              default 3

set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-apollographql/apollo-ios}"
DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
TRIAGE_LABEL="${TRIAGE_LABEL:-claude-triage}"
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

# {"<issue>": "<last triaged-at>", ...}
tracking_records() {
  gh pr list --repo "$DEV_REPO" --label "$TRIAGE_LABEL" --state all \
    --limit 1000 --json title,body \
    | jq -c '[ .[]
        | (.title | capture("apollo-ios#(?<n>[0-9]+)") | .n) as $n
        | select($n != null)
        | { n: $n,
            at: (((.body // "") | capture("triaged-at=(?<t>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z)") | .t) // "1970-01-01T00:00:00Z") } ]
      | group_by(.n) | map({ key: .[0].n, value: (map(.at) | max) }) | from_entries'
}

records="$(tracking_records)"

if [[ -n "$issue" ]]; then
  if [[ "$force" == true ]] || ! jq -e --arg n "$issue" '.[$n] != null' <<<"$records" >/dev/null; then
    jq -n -c --argjson n "$issue" '[{issue: $n, reason: "manual"}]'
  else
    echo "Issue #$issue already has a tracking PR; use --force to re-triage." >&2
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

jq -n -c --argjson new "$new_issues" --argjson fu "$followups" --argjson max "$MAX_PER_RUN" \
  '($new + $fu) | unique_by(.issue) | .[:$max]'
