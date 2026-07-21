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

## Historical incident: macos-26 runner segfault in `git subtree split` (July 2026)

**How it happened:** Two independent changes intersected.

1. **git 2.54.0 removed the multi-subtree walk optimization.** Upstream commit [`1f70684b51`](https://github.com/git/git/commit/1f70684b51) (Feb 2026) deliberately removed `should_ignore_subtree_split_commit` — the logic that skipped *other* subtrees' split/squash commits during a split — because it could incorrectly exclude commits and alter split hashes (an API contract violation). The consequence for multi-subtree repos like this one: each split now crawls essentially the **entire repo history** as "extra" commits, every run, and that crawl grows with every merged PR. Measured on a July 2026 run (git 2.55, ~5,500 commits on main): apollo-ios walked ~300 commits, codegen ~3,500, pagination ~3,900. On git ≤2.53 (including Apple/Xcode git 2.50) the same pagination split walks ~130 commits with zero extras. This crawl is deep bash recursion in the `git-subtree` script — one stack frame chain per uncached ancestry run.
2. **GitHub rolled `macos-latest` over to `macos-26-arm64`** (June 2026). Same Bash 3.2.57 and git 2.55.0 as macos-15, but the recompiled system bash and/or default stack rlimit on the new image tolerates less recursion depth. The ~1,900-frame-deep crawl that (barely) fit on macos-15 segfaulted on macos-26:

```
/opt/homebrew/opt/git/libexec/git-core/git-subtree: line 925: 12196 Done    eval "$grl"
     12197 Segmentation fault: 11  | while read rev parents; do
    process_split_commit "$rev" "$parents";
done
```

During the label rollover, runs landed on either image at random, so failures looked flaky — two PRs failed while one in between succeeded (it happened to get a macos-15 runner).

**Impact:** None to repair. `Push Subtrees` is gated on `if: success()`, so failed runs pushed nothing and no rejoin metadata reached `main`. The missed subtree commits were carried upstream automatically by the next successful run (splits walk full history).

**Fix (PR #1047):** Three layers.

1. Moved the workflow's jobs to `runs-on: ubuntu-latest` (nothing in them is macOS-specific). Do not move these jobs back to macOS runners.
2. Added `ulimit -s unlimited` before the split (Linux permits it) — a deep walk can now cost time, never a segfault.
3. Vendored `git-subtree.sh` from git v2.53.0 at `scripts/vendor/git-subtree-2.53.0.sh` — the last version with the multi-subtree optimization — and pointed the `subtree-split-push` action at it. Splits are back to ~12s each with a walk that stays flat as history grows. Verified before adoption: it reproduces the exact upstream head SHAs for all three subtrees. The action asserts after every split that the split commit's tree equals `HEAD:<subtree>`, so the optimization's known edge cases (which require merge topologies this repo doesn't produce) would fail loudly before any push. See `scripts/vendor/README.md` for full provenance and rationale.

**Rejected alternative:** [`splitsh-lite`](https://github.com/splitsh/lite) — unmaintained (archived git2go binding pinned to libgit2 1.5) and empirically NOT hash-compatible with this repo's squash-based history (produced a different apollo-ios split SHA). Do not revisit it.

**⚠️ Local vs CI git divergence:** different git versions implement `subtree split` differently (the optimization was present ≤2.53, removed in 2.54). Both algorithms have so far agreed on this repo's history, but for any local recovery split intended to be pushed upstream, use the vendored script (`scripts/vendor/git-subtree-2.53.0.sh`, with `GIT_EXEC_PATH="$(git --exec-path)"` exported and on `PATH`) — that is exactly what CI runs, so its hashes are the canonical ones.

## Historical incident: missing committer email in split (July 2026)

**Symptoms:** Every subtree split step failed at the same point:

```
Author identity unknown

*** Please tell me who you are.
...
fatal: unable to auto-detect email address (got 'runner@runnervm3jd5f.(none)')
```

**How it happened:** `git subtree split --squash --rejoin` writes commits (the squash commit and the rejoin), which need a committer identity. The `configure-git` action only ever set `user.name`, never `user.email`. Historically git filled the email in by auto-detecting `runner@<hostname>` — but a newer `ubuntu-latest` runner image resolves the hostname to `(none)`, and git refuses an auto-detected `...(none)` address rather than committing with it. No `user.email` was configured to fall back on, so the split aborted before producing a SHA. `Push Subtrees` is gated on `if: success()`, so nothing was pushed and no rejoin metadata reached `main`.

**Fix:** Added an explicit `user.email` (input `email`, default `gh-action-runner@users.noreply.github.com`) to `.github/actions/configure-git`. All five workflows that use `configure-git` inherit the fix. Do not rely on git's hostname auto-detection in CI — always set `user.email` explicitly.

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
