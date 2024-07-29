#!/bin/bash
set -e

echo "Testing PackageOne.."
cd PackageOne
swift test -Xswiftc -warnings-as-errors

echo "Testing PackageTwo.."
cd ../PackageTwo
swift test -Xswiftc -warnings-as-errors
