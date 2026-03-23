# CI Subtree Push Troubleshooting

## How the subtree push workflow works

On every PR merge, `.github/workflows/pr-subtree-push.yml` runs the `subtree-split-push` action for each of the three subtrees (`apollo-ios`, `apollo-ios-codegen`, `apollo-ios-pagination`). The action does three things in a single step:

1. `git subtree pull --squash` — syncs the upstream subtree remote into the local history
2. `git subtree split --squash --rejoin` — creates a synthetic split commit (containing only the subtree's content) and writes rejoin metadata back into the local history
3. `git subtree push` — pushes the split commit to the upstream subtree repo

After all three subtrees are processed, the `Push Updated History` step (which has `if: always()`) pushes the updated dev repo history (including any rejoin metadata commits) back to `apollo-ios-dev/main`.

## The broken metadata bug

**How it happens:** If step 3 (`git subtree push`) times out or fails, the synthetic split commit (e.g., `daa8849dd`) was only ever created on the ephemeral CI runner. It never made it to the upstream subtree remote. However, step 2 already wrote rejoin metadata commits into local history that reference that missing SHA. When `Push Updated History` then succeeds (because it's `if: always()`), those broken metadata commits get pushed to `apollo-ios-dev/main`.

**Why subsequent CI runs fail:** CI uses git 2.53.0, which strictly validates `git-subtree-split:` hashes. When it encounters the broken hash, it tries to fetch it from the upstream remote, the remote returns `not our ref`, and it hard-fails. Every future PR that touches the affected subtree will fail until this is fixed.

**Symptoms:**
```
fatal: remote error: upload-pack: not our ref <sha>
fatal: could not rev-parse split hash <sha> from commit <sha>
```

## How to fix it

The fix exploits the fact that the local Xcode-bundled git-subtree is more lenient than CI's git 2.53.0 — when it can't resolve a cached split hash, it silently skips it and reconstructs the split from scratch by walking all history. This is slower but succeeds.

**Step 1: Identify the broken commit**

Find the rejoin commit that references the missing split hash:
```bash
git log --oneline --grep="git-subtree-split" --grep="<affected-subtree>" --all-match | head -5
```

Or search directly:
```bash
git log --oneline --all | head -20
# Look for a "split: <subtree>" commit with no corresponding push on the upstream remote
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

**Step 4: Restore main to remote HEAD and force push**

After the script completes, the upstream subtree repo now has the correct commits. Reset main back to match remote:
```bash
git fetch origin
git reset --hard origin/main
```

**Step 5: Re-run the failing CI job**

Trigger a re-run of the failing `PR Subtree Push` job from the GitHub Actions UI. It will now succeed because the missing split SHA now exists on the upstream subtree remote.

## Which subtrees may need fixing

If a CI run failed, check the logs to see which subtrees failed. The `apollo-ios` and `apollo-ios-pagination` steps also use `if: always()` so they run even if a prior step failed. Check each subtree's step in the logs for the same `not our ref` error.

## Root cause and long-term fix

The underlying bug is in `.github/actions/subtree-split-push/action.yml`: `--rejoin` writes metadata to local history before the push is confirmed. If the push fails, `Push Updated History` (which has `if: always()`) still commits the broken metadata to `main`.

A proper fix would either:
- Change `Push Updated History` to only run if all subtree steps succeeded (remove `if: always()`)
- Or split the action into two steps: push first, then write rejoin metadata only on success
