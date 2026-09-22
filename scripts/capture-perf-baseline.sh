#!/usr/bin/env bash
#
# Captures the 2.x cache-rewrite performance baseline by running the
# ApolloPerformanceTests/Apollo-CacheBenchmarksTestPlan against a destination
# and assembling the BENCHMARK_RESULT_JSONL lines into the dataset format
# defined in apollo-ios/Design/cache-rewrite-phase1-perf.md §5.1.
#
# Usage:
#   scripts/capture-perf-baseline.sh                         # macOS run (dev iteration)
#   scripts/capture-perf-baseline.sh -d "platform=iOS,name=My iPhone" \
#                                    -l "iPhone 16 Pro (physical)" \
#                                    -o Tests/ApolloPerformanceTests/CacheBenchmarks/baseline-2.x.json
#
# The script does not commit; it writes the JSON to -o and exits.
set -euo pipefail

DESTINATION="platform=macOS"
DEVICE_LABEL="macOS"
OUTPUT_PATH=""
VERSION_LABEL="2.x"

while getopts "d:l:o:v:" opt; do
  case "$opt" in
    d) DESTINATION="$OPTARG" ;;
    l) DEVICE_LABEL="$OPTARG" ;;
    o) OUTPUT_PATH="$OPTARG" ;;
    v) VERSION_LABEL="$OPTARG" ;;
    *) echo "usage: $0 [-d destination] [-l device-label] [-o output-path] [-v version]" >&2; exit 2 ;;
  esac
done

if [[ -z "$OUTPUT_PATH" ]]; then
  echo "error: -o output-path is required" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

GIT_SHA="$(git rev-parse HEAD)"
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RAW_LOG="$(mktemp -t apollo-perf-baseline-XXXXXX.log)"
trap 'rm -f "$RAW_LOG"' EXIT

echo "==> Running cache benchmarks against $DEVICE_LABEL ($DESTINATION)..."
echo "    Output: $OUTPUT_PATH"
echo "    Raw log: $RAW_LOG"

xcodebuild test \
  -workspace ApolloDev.xcworkspace \
  -scheme ApolloPerformanceTests \
  -testPlan Apollo-CacheBenchmarksTestPlan \
  -destination "$DESTINATION" \
  | tee "$RAW_LOG"

# Extract every benchmark JSONL line emitted by the harness.
RESULTS_JSON="$(grep -E '^BENCHMARK_RESULT_JSONL:' "$RAW_LOG" \
  | sed 's/^BENCHMARK_RESULT_JSONL: //' \
  | jq -s '.')"

if [[ -z "$RESULTS_JSON" || "$RESULTS_JSON" == "[]" ]]; then
  echo "error: no benchmark results captured from test output" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
jq --null-input \
   --arg version "$VERSION_LABEL" \
   --arg captured_at "$CAPTURED_AT" \
   --arg git_sha "$GIT_SHA" \
   --arg device "$DEVICE_LABEL" \
   --argjson results "$RESULTS_JSON" \
   '{version: $version, captured_at: $captured_at, git_sha: $git_sha, device: $device, results: $results}' \
   > "$OUTPUT_PATH"

echo "==> Wrote $(jq '.results | length' "$OUTPUT_PATH") result rows to $OUTPUT_PATH"
