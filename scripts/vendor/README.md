# Vendored tools

## git-subtree-2.53.0.sh

A pristine, unmodified copy of `contrib/subtree/git-subtree.sh` from git
**v2.53.0** (GPLv2, © 2009 Avery Pennarun and git contributors).

Verify provenance:

```bash
curl -s https://raw.githubusercontent.com/git/git/v2.53.0/contrib/subtree/git-subtree.sh | shasum -a 256
# b7d22f2ab1f30174cb4d5b1b183b062f84f57a88b994ed36a29063d900f37e49
```

### Why it is vendored

git 2.54.0 removed the `should_ignore_subtree_split_commit` optimization from
`git subtree split` ([git/git@`1f70684b51`](https://github.com/git/git/commit/1f70684b51))
because it can miscompute split hashes in exotic merge topologies. The cost of
that removal for multi-subtree repos like this one: every split crawls the
entire repo history via deep bash recursion — O(total history) per subtree per
run, growing forever, and deep enough to segfault bash on some runners (see
`claude/ci-subtree-troubleshooting.md`, July 2026 incident).

v2.53.0 is the last release with the optimization, including its two rounds of
fixes (`83f9dad7d6`, `28a7e27cff`). It is the algorithm that produced this
repo's upstream subtree history for years. Verified July 2026: it reproduces
the exact upstream head SHAs for all three subtrees in ~12s per split (vs.
minutes and unbounded growth for git ≥2.54).

### Safety net

The miscompute risk that motivated upstream's removal only manifests in merge
topologies this repo doesn't produce (main is linear squash merges), and the
`subtree-split-push` action guards against it anyway: after every split it
asserts the split commit's tree is identical to the subtree directory's tree
in HEAD, and a bad split would additionally fail as a non-fast-forward push.
Wrong output fails loudly before anything is published.

### How it is used

`.github/actions/subtree-split-push/action.yml` invokes this script directly
(instead of `git subtree`). It requires `GIT_EXEC_PATH` to be set and on
`PATH` so it can source `git-sh-setup`:

```bash
export GIT_EXEC_PATH="$(git --exec-path)"
export PATH="$GIT_EXEC_PATH:$PATH"
bash scripts/vendor/git-subtree-2.53.0.sh split --prefix=<subtree> --squash --rejoin -m "<msg>"
```

Do NOT "helpfully" update this file to a newer git version — losing the
optimization is the whole point of pinning it. If it ever misbehaves, the
fallback is stock `git subtree split` (slow but correct).
