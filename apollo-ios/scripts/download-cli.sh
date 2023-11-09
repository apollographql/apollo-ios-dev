#!/bin/bash

# This script is intended for use only with the "InstallCLI" SPM plugin provided by Apollo iOS

directory=$(dirname "$0")
projectDir="$1"

if [ -z "$projectDir" ];
then
  echo "Missing project directory path." >&2
  exit 1
fi

echo "Directory - $directory"
APOLLO_VERSION=$($directory/get-version.sh)
echo "Apollo Version - $APOLLO_VERSION"
DOWNLOAD_URL="https://www.github.com/apollographql/apollo-ios/releases/download/$APOLLO_VERSION/apollo-ios-cli.tar.gz"
echo "Download URL - $DOWNLOAD_URL"
FILE_PATH="$projectDir/apollo-ios-cli.tar.gz"
echo "File Path - $FILE_PATH"
curl -L "$DOWNLOAD_URL" -s -o "$FILE_PATH"
tar -xvf "$FILE_PATH"
rm -f "$FILE_PATH"
