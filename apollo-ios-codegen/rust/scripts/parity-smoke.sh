#!/bin/bash
# parity-smoke.sh <swift-apollo-ios-cli> <rust-apollo-ios-cli>
#
# Runs both CLIs on the repository's AnimalKingdom fixture from identical copies of the inputs
# and diffs the generated trees byte for byte. Exits non-zero when any generated file differs.
# This is the smallest slice of the full parity harness used to verify the Rust port.
set -euo pipefail
SWIFT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
RUST=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)   # repository root (apollo-ios-dev)
FIXTURE=Sources/AnimalKingdomAPI/animalkingdom-graphql
WORK=${PARITY_WORK:-$(mktemp -d)}

for impl in swift rust; do
  mkdir -p "$WORK/$impl/$(dirname "$FIXTURE")"
  cp -R "$ROOT/$FIXTURE" "$WORK/$impl/$FIXTURE"
  cat > "$WORK/$impl/apollo-codegen-config.json" <<JSON
{
  "schemaNamespace": "AnimalKingdomAPI",
  "input": {
    "schemaSearchPaths": ["$FIXTURE/AnimalSchema.graphqls"],
    "operationSearchPaths": ["$FIXTURE/**/*.graphql"]
  },
  "output": {
    "schemaTypes": { "path": "Generated/AnimalKingdomAPI", "moduleType": { "swiftPackage": {} } },
    "operations": { "inSchemaModule": {} },
    "testMocks": { "swiftPackage": { "targetName": "AnimalKingdomAPITestMocks" } }
  },
  "options": {
    "schemaDocumentation": "include",
    "selectionSetInitializers": { "operations": true, "namedFragments": true, "localCacheMutations": true }
  }
}
JSON
done

(cd "$WORK/swift" && "$SWIFT" generate --path apollo-codegen-config.json > generate.log 2>&1) || { cat "$WORK/swift/generate.log"; echo "Swift CLI failed"; exit 1; }
(cd "$WORK/rust"  && "$RUST"  generate --path apollo-codegen-config.json > generate.log 2>&1) || { cat "$WORK/rust/generate.log";  echo "Rust CLI failed";  exit 1; }

count=$(find "$WORK/rust/Generated" -type f | wc -l | tr -d ' ')
if diff -r "$WORK/swift/Generated" "$WORK/rust/Generated"; then
  echo "parity-smoke: OK ($count generated files identical; work dir $WORK)"
else
  echo "parity-smoke: FAILED (see diff above; work dir $WORK)"; exit 1
fi
