#!/bin/bash

directory=$(dirname "$0")
apolloDirectory="$directory/../apollo-ios"
codegenDirectory="$directory/../apollo-ios-codegen"

# Validate input version number

source "$apolloDirectory/scripts/version-constants.sh"
source "$codegenDirectory/scripts/version-constants.sh"

NEW_VERSION="$1"

 if [[ ! $NEW_VERSION =~ ^[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2} ]]; then
     echo "You must specify a version in the format x.x.x"
     exit 1
 fi

# Set Apollo version constant

CURRENT_APOLLO_VERSION=$($apolloDirectory/scripts/get-version.sh)
MATCH_TEXT='ApolloVersion: String = "'
SEARCH_TEXT="$MATCH_TEXT$CURRENT_APOLLO_VERSION"
REPLACE_TEXT="$MATCH_TEXT$NEW_VERSION"
sed -i '' -e "s/$SEARCH_TEXT/$REPLACE_TEXT/" $apolloDirectory/$APOLLO_CONSTANTS_FILE

# Set CLI version constant

CURRENT_CODEGEN_VERSION=$($codegenDirectory/scripts/get-version.sh)
MATCH_TEXT='CLIVersion: String = "'
SEARCH_TEXT="$MATCH_TEXT$CURRENT_CODEGEN_VERSION"
REPLACE_TEXT="$MATCH_TEXT$NEW_VERSION"
sed -i '' -e "s/$SEARCH_TEXT/$REPLACE_TEXT/" $codegenDirectory/$CLI_CONSTANTS_FILE

# Set Codegen version constant

MATCH_TEXT='CodegenVersion: String = "'
SEARCH_TEXT="$MATCH_TEXT$CURRENT_CODEGEN_VERSION"
REPLACE_TEXT="$MATCH_TEXT$NEW_VERSION"
sed -i '' -e "s/$SEARCH_TEXT/$REPLACE_TEXT/" $codegenDirectory/$CODEGEN_CONSTANTS_FILE

# Feedback
echo "Committing change from version $CURRENT_VERSION to $NEW_VERSION"
git add -A && git commit -m "Updated version numbers"
