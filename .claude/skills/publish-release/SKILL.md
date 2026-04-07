---
name: publish-release
description: >-
  Use when the user asks to "publish a release", "create a release", "cut a release",
  "prepare a release", "do a patch release", or "set up a release". Covers the full
  Apollo iOS release workflow including GitHub Actions, CHANGELOG updates, PR management,
  and draft release publishing across apollo-ios and apollo-ios-codegen repos.
---

# Publish Release

Execute the full Apollo iOS release workflow. This is a multi-step process involving
GitHub Actions, CHANGELOG editing, and draft release publishing across multiple repos.

## Prerequisites

- `gh` CLI authenticated with permissions to the apollographql org
- The working directory is the `apollo-ios-dev` repository
- Changes to be released are already merged into the target branch

## Phase 1: Determine Release Parameters

Gather the target branch and version number:

1. Ask the user which branch to release from (e.g., `v1`, `main`) if not specified.
2. Determine the current version by checking recent release tags or commit history:
   ```
   git log origin/<branch> --oneline --grep="Release" | head -5
   ```
3. Calculate the next version. For a patch release, increment the patch number.
   If the release type is ambiguous (patch vs minor vs major), ask the user.
4. Confirm the target branch and version with the user before proceeding.

## Phase 2: Trigger "Create Release PR" Workflow

Run the GitHub Action that prepares the release branch:

```
gh workflow run "Create Release PR" --ref <branch> -f versionNumber=<version>
```

Monitor until complete:

```
gh run list --workflow="Create Release PR" --limit 1
gh run watch <run-id> --exit-status
```

Once complete, find the PR it created:

```
gh pr list --base <branch> --head release/<version> --json number,title,url
```

## Phase 3: Update CHANGELOG

This phase requires user verification before pushing.

1. Fetch and checkout the release branch:
   ```
   git fetch origin release/<version>
   git checkout release/<version>
   ```

2. Read `apollo-ios/CHANGELOG.md`. The workflow will have inserted an empty
   `## v<version>` section at the top.

3. Add changelog entries under the new version section. Use the existing format:
   - Group entries under `### New`, `### Improvement`, or `### Fixed` as appropriate
   - Each entry: `- **Short title ([#issue](url)):** Description. See PR [#pr](url).`
   - Include contributor attribution where applicable

4. Gather entries from the commits since the last release:
   ```
   git log origin/<branch> --oneline --no-merges <previous-tag>..origin/<branch>
   ```

5. **STOP — Open the CHANGELOG in Xcode for user review:**
   ```
   open -a Xcode apollo-ios/CHANGELOG.md
   ```
   Then use `AskUserQuestion` to ask if the user is ready to commit and push.
   Do not push until the user confirms.

6. After approval, commit and push:
   ```
   git add apollo-ios/CHANGELOG.md
   git commit -m "Update CHANGELOG.md for v<version>"
   git push
   ```

## Phase 4: Merge the Release PR

1. Merge the release PR:
   ```
   gh pr merge <pr-number> --merge --admin
   ```

2. Wait for the subtree push workflow to complete. This pushes changes to the
   upstream apollo-ios, apollo-ios-codegen, and apollo-ios-pagination repos:
   ```
   gh run list --workflow="pr-subtree-push.yml" --limit 1
   gh run watch <run-id> --exit-status
   ```
   The subtree push must succeed before proceeding — the publish workflow checks
   out the upstream repos and needs the latest code.

## Phase 5: Trigger "Publish Release" Workflow

1. Run the publish workflow:
   ```
   gh workflow run "Publish Release" --ref <branch>
   ```

2. Monitor until complete:
   ```
   gh run list --workflow="Publish Release" --limit 1
   gh run watch <run-id> --exit-status
   ```

3. The publish workflow performs these steps:
   - Tags all three repos (apollo-ios-dev, apollo-ios, apollo-ios-codegen)
   - Extracts release notes from CHANGELOG.md
   - Creates draft releases on apollo-ios and apollo-ios-codegen
   - Dispatches XCFramework build to apollo-ios-xcframework repo
   - Pushes CocoaPods (v1 branch only)

4. If the XCFramework dispatch fails (known issue on v1 — missing `localRef` param),
   manually dispatch:
   ```
   gh workflow run release-new-version.yml \
     -f localRef=<branch> \
     -f remoteRef=<version> \
     --repo apollographql/apollo-ios-xcframework
   ```
   Monitor until complete.

5. Report the status of each step to the user.

## Phase 6: Review and Publish Draft Releases

1. Fetch and display the draft release contents:
   ```
   gh release view <version> --repo apollographql/apollo-ios
   gh release view <version> --repo apollographql/apollo-ios-codegen
   ```

2. **STOP — Open the draft release pages in the browser for user review.** Extract
   the URLs from `gh release view` output and open them:
   ```
   open "<apollo-ios draft release URL>"
   open "<apollo-ios-codegen draft release URL>"
   ```
   Then use `AskUserQuestion` to ask if the user is ready to publish. The user may
   want to edit the release notes directly on GitHub before publishing.

3. After user approval, publish both releases. **Important:** For releases on the
   `v1` branch, use `--latest=false` so they are not marked as the latest release
   (the `main` branch carries the current major version):
   ```
   # For main branch:
   gh release edit <version> --draft=false --repo apollographql/apollo-ios
   gh release edit <version> --draft=false --repo apollographql/apollo-ios-codegen

   # For v1 branch:
   gh release edit <version> --draft=false --latest=false --repo apollographql/apollo-ios
   gh release edit <version> --draft=false --latest=false --repo apollographql/apollo-ios-codegen
   ```

4. Confirm publication and provide links to the published releases.

## Git Quirks

Xcode runs `git status` in the background, creating transient `index.lock` files.
Use retry loops for git operations:

```
while ! git <command> 2>/dev/null; do rm -f .git/index.lock; done
```

## Workflow Files Reference

- Create Release PR: `.github/workflows/create-release-pr.yml`
- Publish Release: `.github/workflows/publish-release.yml`
- Subtree Push: `.github/workflows/pr-subtree-push.yml`
- Version script: `apollo-ios/scripts/get-version.sh`
- CHANGELOG: `apollo-ios/CHANGELOG.md`
