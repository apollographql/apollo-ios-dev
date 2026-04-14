---
name: merge-stack
description: >-
  Use when the user asks to "merge a stack", "merge stacked PRs", "merge PRs in order",
  or references a chain of PRs that depend on each other. Handles retargeting each PR
  to main and merging them sequentially, with admin bypass for review requirements.
---

# Merge Stacked PRs

Merge a chain of stacked PRs into `main` (or another base branch) sequentially.
Stacked PRs are PRs where each one targets the previous PR's branch as its base,
forming a dependency chain.

## Prerequisites

- `gh` CLI authenticated with permissions to the apollographql org
- The working directory is the `apollo-ios-dev` repository
- The user has identified the PR numbers or the base PR of the stack

## Phase 1: Identify the Stack

Determine the full stack order by querying PR base/head branches.

1. If the user provides specific PR numbers, fetch their details:
   ```
   gh pr list --repo apollographql/apollo-ios-dev --state open \
     --json number,title,baseRefName,headRefName,mergeStateStatus,mergeable
   ```

2. Trace the dependency chain by following `baseRefName` → `headRefName` links.
   The bottom of the stack is the PR whose `baseRefName` is the target branch
   (usually `main`). Each subsequent PR's `baseRefName` matches the previous
   PR's `headRefName`.

3. If the user only provides the bottom PR number, walk up the chain by finding
   open PRs whose `baseRefName` matches the current PR's `headRefName`:
   ```
   gh pr list --repo apollographql/apollo-ios-dev --state open \
     --json number,title,baseRefName,headRefName \
     --jq '.[] | select(.baseRefName == "<headRefName>")'
   ```
   Repeat until no more PRs are found.

4. Display the stack to the user for confirmation:
   ```
   Stack order (bottom to top):
   1. #935 - Refactor incremental response parsing tests (main <- unit-test-cleanup)
   2. #936 - Rewrite RequestChainNetworkTransport tests (unit-test-cleanup <- unit-test-cleanup-request-chain)
   3. #937 - Delete obsolete WebSocket test files (unit-test-cleanup-request-chain <- unit-test-cleanup-websocket-removal)
   4. #938 - Fix cache read failure for nested arrays (unit-test-cleanup-websocket-removal <- fix/nested-array-cache-resolution)
   ```

5. Ask the user to confirm before proceeding.

## Phase 2: Merge the Stack

Process each PR in order from bottom to top. The subtree push CI workflow has a
concurrency group that serializes runs, so there is no need to wait for the
subtree push to complete between merges.

For each PR in the stack:

### Step 1: Retarget to the target branch (skip for the first PR)

The first PR already targets `main`. For all subsequent PRs, retarget the base
from the previous PR's branch to the target branch.

**Important:** `gh pr edit --base` fails in this repo due to a GitHub Projects
(classic) deprecation error. Use the REST API instead:

```
gh api repos/apollographql/apollo-ios-dev/pulls/<number> \
  -X PATCH -f base="main" \
  --jq '{number, title, baseRefName: .base.ref, mergeable}'
```

### Step 2: Verify mergeability

After retargeting, GitHub needs a few seconds to compute mergeability. Wait
briefly, then check:

```
gh pr view <number> --repo apollographql/apollo-ios-dev \
  --json mergeStateStatus,mergeable
```

- `MERGEABLE` with `BLOCKED` = review requirement, can be bypassed with `--admin`
- `MERGEABLE` with `CLEAN` = ready to merge
- `CONFLICTING` = has merge conflicts, stop and notify the user

If `mergeable` is `UNKNOWN`, wait a few more seconds and retry (up to 3 attempts).

### Step 3: Merge

```
gh pr merge <number> --repo apollographql/apollo-ios-dev --merge --admin
```

The `--admin` flag bypasses branch protection (review requirements). Only use
this when the user has explicitly authorized it.

If the user has NOT authorized admin bypass, omit `--admin` and let them know
if a PR is blocked on review.

### Step 4: Verify and continue

Confirm the merge succeeded:

```
gh pr view <number> --repo apollographql/apollo-ios-dev --json state,mergedAt
```

Then immediately proceed to the next PR without waiting for the subtree push
workflow. The concurrency group ensures subtree pushes queue and run in order.

## Phase 3: Verify Subtree Pushes

After all PRs are merged, optionally check that the subtree push jobs all
succeeded:

```
gh run list --repo apollographql/apollo-ios-dev \
  --workflow "PR Subtree Push" --limit <stack-size> \
  --json status,conclusion,displayTitle
```

If any failed, notify the user. Subtree push failures are non-fatal — the next
successful run re-syncs metadata — but the user should be aware.

## Error Handling

- **Merge conflicts after retarget:** Stop and notify the user. They need to
  rebase the conflicting PR manually before continuing.
- **Merge fails:** Check the error message. Common causes:
  - CI checks haven't completed (wait and retry)
  - Branch protection rules beyond review (notify user)
- **`gh api` PATCH fails:** Verify the PR number is correct and the PR is still open.

## Handling Partial Stacks

If the user only wants to merge some PRs from a stack (e.g., "merge #935 and #936
but not the rest"), only process those PRs. The remaining PRs will still target
their original base branches and can be merged later.

## Git Quirks

Xcode runs `git status` in the background, creating transient `index.lock` files.
If git commands fail with `index.lock` errors, use retry loops:

```
while ! git <command> 2>/dev/null; do rm -f .git/index.lock; done
```

## Reference

- Subtree push workflow: `.github/workflows/pr-subtree-push.yml`
- The subtree push concurrency group (`subtree-push-<branch>`) serializes runs
  per base branch, so rapid sequential merges are safe
- The subtree push workflow appends commits to `main` (no force-push), so
  retargeted PRs remain mergeable without rebasing
