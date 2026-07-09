#!/bin/bash

Help()
{
  echo "This script allows you to push changes for a specific package to the provided remote and branch."
  echo
  echo "Syntax: push-forked-branch.sh [-p|r|b|h]"
  echo "options:"
  echo "p - The name of the package you are pushing to (ex: apollo-ios)"
  echo "r - The remote name or URL of your forked repo for the given package."
  echo "b - The name of the branch you want to push to on your remote."
  echo "h - Print this help message."
  echo
}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
package=""
remote=""
branch=""

while getopts p:r:b:h option; do
  case $option in
    p) package=$OPTARG;;
    r) remote=$OPTARG;;
    b) branch=$OPTARG;;
    h) Help
      exit;;
    \?) echo "Error: Invalid option"
      exit;;
  esac
done

if [ -z "$package" ];
then
  echo "Missing package name (-p)." >&2
  exit 1
fi

if [ -z "$remote" ];
then
  echo "Missing remote (-r)." >&2
  exit 1
fi

if [ -z "$branch" ];
then
  echo "Missing branch name (-b)." >&2
  exit 1
fi

git fetch $remote

# Split with the vendored git-subtree (v2.53.0) instead of the system
# `git subtree` so local splits produce the same hashes as CI regardless of
# the locally installed git version. See scripts/vendor/README.md.
export GIT_EXEC_PATH="$(git --exec-path)"
export PATH="$GIT_EXEC_PATH:$PATH"
splitSha=$(bash "$SCRIPT_DIR/vendor/git-subtree-2.53.0.sh" split --prefix=$package) || exit $?
if [ -z "$splitSha" ]; then
  echo "Split produced no SHA for $package; refusing to push." >&2
  exit 1
fi
git push $remote "$splitSha:refs/heads/$branch"
