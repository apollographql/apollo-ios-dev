# CI Subtree Push Troubleshooting

## Core invariant: apollo-ios-dev is the only writer

The three subtree upstream repos (`apollo-ios`, `apollo-ios-codegen`, `apollo-ios-pagination`) **must only receive content via the `PR Subtree Push` workflow in this repo.** Nobody pushes to them directly, no Renovate/Dependabot opens PRs against them, no manual commits land on their `main` branches.

The workflow's design relies on this invariant. If it's broken (someone pushes directly to upstream), the next workflow run's `git push` to upstream will fail loudly with a non-fast-forward error — that's the intended signal that the invariant was violated. Investigate before bypassing.

## How the subtree push workflow works

On every PR merge, `.github/workflows/pr-subtree-push.yml` runs the `subtree-split-push` action for each of the three subtrees. The workflow has three gated phases:

1. **Split all three subtrees** (`if: always()` — all three are attempted regardless) — each runs `git subtree split --squash --rejoin`, writing rejoin metadata into local history and outputting the split SHA. The action also fetches upstream for diagnostic visibility but **does not pull** — see "Why no pull?" below.
2. **Push Subtrees** (`if: success()`) — only runs if all three splits succeeded. Pushes each split SHA directly to the upstream subtree repo as a fast-forward.
3. **Push Updated History** (`if: success()`) — only runs if all pushes succeeded. Pushes the dev repo history (including rejoin metadata) back to `apollo-ios-dev/main`.

If any step fails, the runner exits without ever pushing the broken rejoin metadata to `main`.

### Why no pull?

The action used to run `git subtree pull --squash` before `split`. That step existed to defensively bring upstream commits into dev — but in our setup, upstream never has commits dev doesn't, so the pull was always either a no-op or a problem. The May 2026 incident (below) showed it was a self-perpetuating failure source. Removed in PR #990 (or whatever).

## Historical incident: stale-upstream pull conflict (May 2026)

Fixed in PR #989; root cause prevention in PR #990 (approx — match by date).

**How it happened:** When the action did `git subtree pull --squash` before split, the pull's 3-way merge could conflict on noisy files like `package-lock.json` even when the dev and upstream content were structurally compatible. PR #982 (Renovate update to `rollup: 4.60.4`) triggered such a conflict during its post-merge workflow. The conflict failed the split step → `Push Subtrees` was gated off by `if: success()` → upstream never got the 4.60.4 update.

**Why subsequent PRs cascaded:** Every PR after #982 also ran `git subtree pull --squash` against the now-stale upstream (still at rollup 4.60.3), hit the same conflict, and failed the same way. Each failure further widened the dev/upstream gap.

**Symptoms:**
```
Auto-merging apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/package-lock.json
CONFLICT (content): Merge conflict in apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/package-lock.json
Auto-merging apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/package.json
CONFLICT (content): Merge conflict in apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/package.json
Automatic merge failed; fix conflicts and then commit the result.
```

**Recovery (one-time, used by PR #989):**

1. Locally reproduce the workflow's pull on a branch off `main`:
   ```bash
   git fetch https://github.com/apollographql/<affected-subtree>.git main
   git subtree pull -P <affected-subtree> --squash \
     -m "pull: <affected-subtree> - manual resolve to unstick subtree push CI" \
     https://github.com/apollographql/<affected-subtree>.git main
   ```
2. Resolve the conflict by accepting `--ours` for the conflicted files. Verify with `git diff origin/main` — should be empty (dev is correct, upstream is stale).
3. Commit the merge, push the branch, open a PR. **Important: this PR must be merged with a merge commit, NOT squashed** — squashing flattens the two-parent structure that git-subtree relies on.
4. On merge, the next workflow run's pull becomes a no-op (base matches upstream, no conflict) and push catches upstream up.

After PR #990 (this fix), the pull is gone so this specific failure mode cannot recur.

## Historical incident: broken rejoin metadata (PR #924, pre-2026)

**How it happened:** In an older workflow, split and push were coupled in a single action step. `git subtree split --squash --rejoin` wrote rejoin metadata into local history (referencing the new split SHA) _before_ the push to the upstream subtree remote. If the push then timed out, the split SHA was lost with the ephemeral CI runner. `Push Updated History` (which had `if: always()`) would still commit the broken metadata to `main`.

**Why subsequent CI runs failed:** CI's git strictly validates `git-subtree-split:` hashes. When it encounters the broken hash, it tries to fetch it from the upstream remote, the remote returns `not our ref`, and it hard-fails. Every future PR that touched the affected subtree would fail.

**Symptoms:**
```
fatal: remote error: upload-pack: not our ref <sha>
fatal: could not rev-parse split hash <sha> from commit <sha>
```

**Recovery (if it ever recurs):**

The local Xcode-bundled git-subtree is more lenient than CI's — when it can't resolve a cached split hash, it silently skips it and reconstructs the split from scratch by walking all history. Slower but succeeds.

1. Identify the broken rejoin commit:
   ```bash
   git log --oneline --grep="git-subtree-dir: <affected-subtree>" | head -5
   # Look for a "split: <subtree>" commit — check if its git-subtree-split SHA exists on the upstream remote
   ```
2. Reset HEAD to the broken rejoin commit so the local script operates from that point in history:
   ```bash
   git reset --hard <sha-of-broken-rejoin-commit>
   ```
3. Run the push script locally (takes several minutes — it's reconstructing from scratch):
   ```bash
   ./scripts/push-forked-branch.sh -p <subtree> -r https://github.com/apollographql/<subtree>.git -b main
   ```
4. Restore main to remote HEAD:
   ```bash
   git fetch origin
   git reset --hard origin/main
   ```
5. Re-run the failing `PR Subtree Push` job from the GitHub Actions UI. It will now succeed because the missing split SHA exists on the upstream remote.

## Which subtrees may need fixing

Check the CI logs for the failing run. The three split steps use `if: always()` so all three are attempted — look for errors in each subtree's step output to identify which ones are affected.
