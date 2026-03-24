# CI Subtree Push Troubleshooting

## How the subtree push workflow works

On every PR merge, `.github/workflows/pr-subtree-push.yml` runs the `subtree-split-push` action for each of the three subtrees (`apollo-ios`, `apollo-ios-codegen`, `apollo-ios-pagination`). The action splits each subtree and captures the resulting SHA as a step output. The workflow then has two gated steps:

1. **Split all three subtrees** (`if: always()` — all three are attempted regardless) — each runs `git subtree pull --squash` then `git subtree split --squash --rejoin`, writing rejoin metadata into local history and outputting the split SHA.
2. **Push Subtrees** (`if: success()`) — only runs if all three splits succeeded. Pushes each split SHA directly to the upstream subtree repo.
3. **Push Updated History** (`if: success()`) — only runs if all pushes succeeded. Pushes the dev repo history (including rejoin metadata) back to `apollo-ios-dev/main`.

If any step fails, the runner exits without ever pushing the broken rejoin metadata to `main`.

## The broken metadata bug (historical)

This was fixed in PR #924, but understanding it helps diagnose any future regressions.

**How it happened:** In the old workflow, split and push were coupled in a single action step. `git subtree split --squash --rejoin` wrote rejoin metadata into local history (referencing the new split SHA) _before_ the push to the upstream subtree remote. If the push then timed out, the split SHA was lost with the ephemeral CI runner. `Push Updated History` (which had `if: always()`) would still commit the broken metadata to `main`.

**Why subsequent CI runs failed:** CI uses git 2.53.0, which strictly validates `git-subtree-split:` hashes. When it encounters the broken hash, it tries to fetch it from the upstream remote, the remote returns `not our ref`, and it hard-fails. Every future PR that touched the affected subtree would fail.

**Symptoms:**
```
fatal: remote error: upload-pack: not our ref <sha>
fatal: could not rev-parse split hash <sha> from commit <sha>
```

## How to fix broken metadata (if it ever recurs)

The fix exploits the fact that the local Xcode-bundled git-subtree is more lenient than CI's git 2.53.0 — when it can't resolve a cached split hash, it silently skips it and reconstructs the split from scratch by walking all history. This is slower but succeeds.

**Step 1: Identify the broken commit**

Find the rejoin commit that references the missing split hash:
```bash
git log --oneline --grep="git-subtree-dir: <affected-subtree>" | head -5
# Look for a "split: <subtree>" commit — check if its git-subtree-split SHA exists on the upstream remote
```

**Step 2: Reset HEAD to the broken rejoin commit**

```bash
git reset --hard <sha-of-broken-rejoin-commit>
# Example: git reset --hard 8d85ccbb6
```

This is necessary so the local script operates from that point in history and the older git-subtree can fall back to full reconstruction.

**Step 3: Run the push script locally**

```bash
./scripts/push-forked-branch.sh -p <subtree> -r https://github.com/apollographql/<subtree>.git -b main
```

This will take significantly longer than normal (several minutes) because git-subtree is reconstructing the split from scratch rather than using a cached starting point. That's expected.

**Step 4: Restore main to remote HEAD**

After the script completes, the upstream subtree repo now has the correct commits. Reset main back to match remote:
```bash
git fetch origin
git reset --hard origin/main
```

**Step 5: Re-run the failing CI job**

Trigger a re-run of the failing `PR Subtree Push` job from the GitHub Actions UI. It will now succeed because the missing split SHA now exists on the upstream subtree remote.

## Which subtrees may need fixing

Check the CI logs for the failing run. The three split steps use `if: always()` so all three are attempted — look for the `not our ref` error in each subtree's step output to identify which ones are affected.
