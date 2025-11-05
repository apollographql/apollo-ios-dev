#!/bin/bash

set -o pipefail  # Fail if any command in a pipeline fails

# Clean up previous build artifacts
rm -rf ./build

xcodebuild archive -configuration Release -project "CodegenXCFramework.xcodeproj" -scheme "CodegenXCFramework" -destination 'generic/platform=macOS' -archivePath "./build/macOS.xcarchive" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=NO | xcbeautify --is-ci

xcodebuild -create-xcframework -allow-internal-distribution -output ./build/CodegenXCFramework.xcframework -framework ./build/macOS.xcarchive/Products/Library/Frameworks/CodegenXCFramework.framework | xcbeautify --is-ci
