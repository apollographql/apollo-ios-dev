#!/usr/bin/env bash
#
# Finds apollographql/apollo-ios issues that have not yet been triaged and
# prints them as a JSON array of issue numbers.
#
# Dedup is based on tracking pull requests in apollographql/apollo-ios-dev: an
# upstream issue is considered triaged when a dev-repo PR labeled
# `claude-triage` has `apollo-ios#<N>` in its title.
#
# Usage:
#   discover-issues.sh                      # poll: recent untriaged issues
#   discover-issues.sh --issue <N>          # exactly this issue (still deduped)
#   discover-issues.sh --issue <N> --force  # this issue, even if triaged
#
# Environment:
#   GH_TOKEN                 token with read access to both repos
#   UPSTREAM_REPO            default apollographql/apollo-ios
#   DEV_REPO                 default apollographql/apollo-ios-dev
#   TRIAGE_LABEL             default claude-triage
#   LOOKBACK_DAYS            default 3
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

triaged_numbers() {
  gh pr list --repo "$DEV_REPO" --label "$TRIAGE_LABEL" --state all \
    --limit 1000 --json title \
    --jq '[.[].title | capture("apollo-ios#(?<n>[0-9]+)") | .n | tonumber]'
}

if [[ -n "$issue" ]]; then
  if [[ "$force" == true ]]; then
    printf '[%s]\n' "$issue"
    exit 0
  fi
  if triaged_numbers | jq -e --argjson n "$issue" 'index($n) != null' >/dev/null; then
    echo "Issue #$issue already has a tracking PR; use --force to re-triage." >&2
    echo '[]'
  else
    printf '[%s]\n' "$issue"
  fi
  exit 0
fi

if [[ "$(uname)" == "Darwin" ]]; then
  since="$(date -u -v-"${LOOKBACK_DAYS}"d +%Y-%m-%d)"
else
  since="$(date -u -d "${LOOKBACK_DAYS} days ago" +%Y-%m-%d)"
fi

candidates="$(gh issue list --repo "$UPSTREAM_REPO" --state open --limit 100 \
  --search "created:>=${since} sort:created-asc" \
  --json number,author \
  --jq '[.[] | select(.author.is_bot | not) | .number]')"

triaged="$(triaged_numbers)"

jq -n -c \
  --argjson candidates "$candidates" \
  --argjson triaged "$triaged" \
  --argjson max "$MAX_PER_RUN" \
  '$candidates | map(select(. as $n | $triaged | index($n) | not)) | .[:$max]'
