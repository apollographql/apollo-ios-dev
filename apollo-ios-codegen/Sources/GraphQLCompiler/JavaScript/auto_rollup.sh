#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
output_file="$SCRIPT_DIR/../ApolloCodegenFrontendBundle.swift"
$( cd "$SCRIPT_DIR" && rollup -c )
minJS=$(cat "$SCRIPT_DIR/dist/ApolloCodegenFrontend.bundle.js")
printf "%s%s%s" "let ApolloCodegenFrontendBundle: String = #\"" "$minJS" "\"#" > $output_file
exit 0
