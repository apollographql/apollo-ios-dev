#!/bin/bash
set -eo pipefail

xcodebuild test -scheme SPMInXcodeProject -destination platform=macOS -quiet | xcbeautify --is-ci
