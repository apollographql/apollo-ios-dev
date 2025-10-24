#!/bin/bash
set -eo pipefail

swift test -Xswiftc -warnings-as-errors
