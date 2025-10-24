#!/bin/bash
set -eo pipefail

xcodebuild archive -configuration Release -project "CodegenXCFramework.xcodeproj" -scheme "CodegenXCFramework" -destination 'generic/platform=iOS Simulator' -archivePath "./build/iphonesimulator.xcarchive" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES | xcbeautify --is-ci
xcodebuild archive -configuration Release -project "CodegenXCFramework.xcodeproj" -scheme "CodegenXCFramework" -destination 'generic/platform=iOS' -archivePath "./build/iphoneos.xcarchive" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES | xcbeautify --is-ci
xcodebuild -create-xcframework -output ./build/CodegenXCFramework.xcframework -framework ./build/iphonesimulator.xcarchive/Products/Library/Frameworks/CodegenXCFramework.framework -framework ./build/iphoneos.xcarchive/Products/Library/Frameworks/CodegenXCFramework.framework | xcbeautify --is-ci
