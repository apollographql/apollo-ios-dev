#!/usr/bin/env bash
#
# Dedup state for issue triage: a JSON object {"<issue>": "<last triaged-at>"}
# kept as triaged.json on an orphan branch of the dev repo, read and written
# through the GitHub contents API so no checkout is needed. Holds only issue
# numbers and timestamps; never drafts.
#
# Usage:
#   triage-state.sh read                 # prints the JSON object ({} when absent)
#   triage-state.sh stamp <issue> <iso>  # merges one entry, creating the branch if needed
#
# Environment: GH_TOKEN, DEV_REPO (default apollographql/apollo-ios-dev),
#              STATE_BRANCH (default claude-triage-state)

set -euo pipefail

DEV_REPO="${DEV_REPO:-apollographql/apollo-ios-dev}"
STATE_BRANCH="${STATE_BRANCH:-claude-triage-state}"
STATE_PATH="triaged.json"

fetch_state() {
  # Prints "<sha>\t<json>"; sha is "-" when the file or branch does not exist
  # (a placeholder, because read drops a leading empty tab-separated field).
  local resp
  if resp="$(gh api "repos/${DEV_REPO}/contents/${STATE_PATH}?ref=${STATE_BRANCH}" 2>/dev/null)"; then
    printf '%s\t%s\n' "$(jq -r '.sha' <<<"$resp")" "$(jq -r '.content' <<<"$resp" | base64 -d | jq -c '.')"
  else
    printf -- '-\t{}\n'
  fi
}

branch_exists() {
  gh api "repos/${DEV_REPO}/git/ref/heads/${STATE_BRANCH}" >/dev/null 2>&1
}

create_branch_with() {
  local json="$1" blob tree commit
  blob="$(gh api -X POST "repos/${DEV_REPO}/git/blobs" -f content="$json" -f encoding=utf-8 --jq '.sha')"
  tree="$(gh api -X POST "repos/${DEV_REPO}/git/trees" \
    -f "tree[][path]=${STATE_PATH}" -f "tree[][mode]=100644" -f "tree[][type]=blob" -f "tree[][sha]=${blob}" --jq '.sha')"
  commit="$(gh api -X POST "repos/${DEV_REPO}/git/commits" -f message="Initialize triage state" -f tree="$tree" --jq '.sha')"
  gh api -X POST "repos/${DEV_REPO}/git/refs" -f ref="refs/heads/${STATE_BRANCH}" -f sha="$commit" >/dev/null
}

case "${1:-}" in
  read)
    fetch_state | cut -f2
    ;;
  stamp)
    issue="${2:?issue number}"; ts="${3:?timestamp}"
    [[ "$issue" =~ ^[0-9]+$ ]] || { echo "issue must be an integer" >&2; exit 2; }
    for attempt in 1 2 3 4 5; do
      IFS=$'\t' read -r sha current < <(fetch_state)
      [[ "$sha" == "-" ]] && sha=""
      updated="$(jq -c --arg n "$issue" --arg t "$ts" '.[$n] = (if .[$n] == null or .[$n] < $t then $t else .[$n] end)' <<<"$current")"
      if [[ -z "$sha" ]]; then
        if branch_exists; then
          gh api -X PUT "repos/${DEV_REPO}/contents/${STATE_PATH}" -f message="Triage state: apollo-ios#${issue}" \
            -f content="$(printf '%s\n' "$updated" | base64)" -f branch="$STATE_BRANCH" >/dev/null && exit 0
        else
          create_branch_with "$(printf '%s\n' "$updated")" && exit 0
        fi
      else
        gh api -X PUT "repos/${DEV_REPO}/contents/${STATE_PATH}" -f message="Triage state: apollo-ios#${issue}" \
          -f content="$(printf '%s\n' "$updated" | base64)" -f sha="$sha" -f branch="$STATE_BRANCH" >/dev/null && exit 0
      fi
      echo "State write conflict (attempt $attempt); retrying." >&2
      sleep $((attempt * 2))
    done
    echo "Could not write triage state after retries." >&2
    exit 1
    ;;
  *)
    echo "usage: triage-state.sh read | stamp <issue> <iso>" >&2; exit 2 ;;
esac
