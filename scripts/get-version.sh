#!/bin/bash

directory=$(dirname "$0")
source "$directory/version-constants.sh"

constantsFile=$(cat $directory/../$CLI_CONSTANTS_FILE)
currentVersion=$(echo $constantsFile | sed 's/^.*CLIVersion: String = "\([^"]*\).*/\1/')
echo $currentVersion
