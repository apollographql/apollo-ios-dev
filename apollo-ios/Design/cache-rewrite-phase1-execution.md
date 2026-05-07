# Cache Rewrite — Phase 1 AI Execution Plan

**Audience:** Claude Code agent executing the Phase 1 work; the human reviewer.
**Companion documents:**
- [cache-rewrite-phase1-summary.md](./cache-rewrite-phase1-summary.md) — manager-facing summary.
- [cache-rewrite-phase1-plan.md](./cache-rewrite-phase1-plan.md) — engineering design (the **authoritative** spec for what is being built).
- [cache-rewrite-phase1-perf.md](./cache-rewrite-phase1-perf.md) — performance measurement plan.

This document describes **how** the Phase 1 work is executed by an AI agent, broken into small reviewable PRs stacked on each other. The engineering plan describes what to build; this plan describes the workflow for shipping it.

## 1. Preamble

This is the operating manual for an AI agent (Claude Code) executing the Phase 1 cache rewrite. Every Claude Code session that touches this project must consult this document before doing implementation work. It exists so that:

- Any session can resume work where the last one left off without re-deriving context from the conversation.
- The human reviewer has predictable, small, reviewable artifacts to evaluate.
- Scope drift, accidental scope expansion, and silent design deviation are minimized.

**The engineering plan is authoritative for design decisions.** This document is authoritative for *workflow*. If a conflict arises (e.g., a PR's scope can't fit the workflow rules in this document), escalate to the reviewer; do not silently widen scope.

## 2. Operating principles

1. **One PR at a time per active task.** Maximum **2 stacked unmerged PRs** in flight at once. If the reviewer falls behind, queue work — do not pile on more open PRs.
2. **Target diff size: ~300–500 LoC of meaningful change.** Generated code, snapshot data, and trivial test boilerplate don't count toward this. PRs over 600 meaningful LoC must be split unless explicitly approved by the reviewer.
3. **Each PR is self-contained.** It builds, all tests pass, and it is mergeable in isolation against its base branch (which may be `main` or a prior PR's branch in the stack).
4. **No scope creep.** A PR does exactly what its title and acceptance criteria say. Anything else — even an obvious cleanup or fix — is escalated as a follow-up task; do not silently include it.
5. **All functional changes must be fully unit-tested.** Every behavior added, modified, or moved by a PR has corresponding test coverage in the same PR. Pure refactors with no behavior change still require test runs to confirm no regression. Documentation-only and ADR-only PRs are exempt. "Fully unit-tested" means: every new branch in production code has at least one test exercising it; every documented edge case from the design plan has a test; every new public API has at least one test exercising its happy path and at least one error/boundary case.
6. **The engineering plan is authoritative.** This execution doc is workflow only.
7. **Memory and the design docs are the source of truth across sessions, not the conversation transcript.** A new session starts by reading the docs and the open-PR list, not by summarizing prior chat.

## 3. Branch and PR conventions

### Branch naming

- **Long-lived plan branch:** `cache-rewrite/phase-1-plan` — holds the four Phase 1 design docs (summary, plan, execution, perf). **Not merged into `main` until every PR in the stack has been merged into it.** Treated as a long-running feature branch; serves as the base for the entire Phase 1 stack.
- **Implementation PRs:** `cache-rewrite/phase-1<letter>-<NN>-<short-slug>`, where `<letter>` is the phase (`a`, `b`, `c`, `d`) and `<NN>` is the two-digit PR sequence within that phase.
  - Examples: `cache-rewrite/phase-1a-01-cached-field-type`, `cache-rewrite/phase-1b-03-bridge-max-age`, `cache-rewrite/phase-1c-07-ttl-tests`.
- **ADR PRs (Phase 0):** `cache-rewrite/phase-0-adr-<slug>`. Example: `cache-rewrite/phase-0-adr-record-abstraction`.
- **Spike branches (Phase 0):** `cache-rewrite/phase-0-spike-<slug>`. These are **not merged**; they are kept alive for reference and findings are captured in an ADR.

### PR base

- **PR-001 (the first PR in the stack) bases on `cache-rewrite/phase-1-plan`**, not `main`. Every PR in the stack ultimately resolves to a merge into `cache-rewrite/phase-1-plan` (directly, or transitively through prior stacked PRs).
- Subsequent PRs base on the previous PR's branch (stacked).
- The PR description's *Stacks on* field names the base branch explicitly.
- When the prior PR in the stack merges into `cache-rewrite/phase-1-plan`, the next PR is rebased onto the new tip of `cache-rewrite/phase-1-plan` (which now contains the merged predecessor) and its `--base` is updated.
- **Plan revisions propagate.** If `cache-rewrite/phase-1-plan` is updated directly (a commit landing on it that revises any of the three design docs), every open stacked PR is rebased onto the new tip in stack order at the start of the next session.
- **`cache-rewrite/phase-1-plan` itself is only merged into `main` once all 31 implementation PRs are merged into it** — see §10 done conditions.

### Commit message convention

Follow the repo's existing conventional-commits style observed in `git log` (e.g., `chore(deps): …`, `docs: …`, `feat: …`, `fix: …`, `feature: …`). Commit messages end with the `Co-Authored-By` line per `CLAUDE.md`. Use HEREDOC for multi-line messages.

### PR description template

Every implementation PR uses this template verbatim:

```markdown
## Goal
<One sentence: what this PR does.>

## Design doc reference
- [cache-rewrite-phase1-plan.md](apollo-ios/Design/cache-rewrite-phase1-plan.md) §<section>: <pull quote or paraphrase>

## Position in execution plan
PR-<NNN> of the cache rewrite Phase 1 stack. See [cache-rewrite-phase1-execution.md](apollo-ios/Design/cache-rewrite-phase1-execution.md) §8.

## Stacks on
- `<base branch name>` (or `main` for the first PR after the planning merge)

## Followups in this stack
- PR-<NNN+1>: <title>
- PR-<NNN+2>: <title>

## Files changed
<Bulleted list, grouped by directory.>

## Tests added
<Bulleted list of new test cases / files. State explicitly which behaviors are covered.>

## Acceptance criteria
- [ ] <Concrete, checkable item>
- [ ] <Another>
...

## Verification
- `tuist generate` succeeds: <yes/no>
- Build green: <yes/no — which scheme(s)>
- Tests pass: <yes/no — which test plan(s)>
- `XcodeListNavigatorIssues severity:"error"` returns zero: <yes/no>
- New warnings introduced: <none / list>

## Notes for reviewer
<Anything non-obvious. Empty if nothing.>
```

## 4. Per-PR workflow

For each PR, the agent runs the following loop:

### 4.1 Bootstrap

1. Read `MEMORY.md` and the cache-rewrite project memory file.
2. Read this execution plan and locate the next un-started PR in §8.
3. Read the engineering plan section that PR implements.
4. Read the prior merged PR's description (and its predecessors as needed) to understand current cumulative state.
5. Run `git status`, `git branch -vv`, and `gh pr list --author @me --state open` to confirm stack state.

### 4.2 Plan

1. Use `TodoWrite` to break the PR into sub-tasks (typically 3–6 items).
2. If the planned change diverges from §8's scope or LoC estimate, **stop and escalate** before writing code.

### 4.3 Implement

1. Create the PR's branch off the correct base (per §3).
2. Implement sub-tasks one at a time, marking each complete in `TodoWrite` as it lands.
3. Add tests **alongside the production code change**, not in a separate commit.
4. Use Xcode MCP tools (`BuildProject`, `RunSomeTests`, `XcodeListNavigatorIssues`) for build/test verification — not raw `xcodebuild`.
5. For codegen-affecting changes (Phase 1B+), regenerate test API code and commit the regeneration in the same PR.

### 4.4 Verify

Quality gates per §5 must all be green before opening the PR. If any gate fails:
- Diagnose; if root cause is in the PR's scope, fix.
- If root cause is outside scope (pre-existing flake, unrelated bug), **stop and escalate**.

### 4.5 Open PR

1. Push the branch.
2. Open PR via `gh pr create` using the §3 template.
3. Update `TodoWrite` to mark the PR opened; mark the PR's task `completed` only after merge.
4. Move on to the next PR if and only if the in-flight stack count is below the §2 maximum.

### 4.6 Address review feedback

1. Read each comment carefully; ask clarifying questions if intent is ambiguous.
2. Make changes, push as new commits (do not force-push during active review unless the reviewer requests a rebase).
3. Respond inline to each comment indicating what changed.
4. Re-run quality gates.
5. Mark conversations resolved only after the reviewer has acknowledged or after the requested change is unambiguously complete.

### 4.7 On merge

1. Pull the merged change into local `main` (or the merged base).
2. Rebase the next stacked PR onto the new base; resolve any conflicts.
3. Re-verify the next PR's quality gates after rebase.
4. Continue with the next PR.

## 5. Quality gates

Every PR must pass all of the following before opening or before requesting re-review:

| Gate | Tool | Notes |
|---|---|---|
| Workspace generates | `tuist generate` | If it fails, escalate — environment problem, not code |
| Build succeeds | Xcode MCP `BuildProject` for affected schemes | Apollo, ApolloSQLite, ApolloCodegenLib at minimum |
| Tests pass | Xcode MCP `RunSomeTests` against the relevant test plan | Per the table in `CLAUDE.md` mapping schemes → test plans |
| No errors in navigator | Xcode MCP `XcodeListNavigatorIssues` `severity:"error"` returns zero | Used because `RunSomeTests` has a known schema bug; per `CLAUDE.md` |
| New behaviors fully tested | Manual review of the diff + `RunSomeTests` confirming new tests run | See §2 principle 5 |
| No new warnings | Compare diff to baseline | If unavoidable, document in PR description |
| Codegen regenerated | `./scripts/run-codegen.sh` for codegen-affecting PRs | Phase 1B+ |
| Commit message conforms | Manual check against `git log --oneline -10 origin/main` | Conventional-commit prefix |

## 6. Escalation triggers

The agent **stops and asks the reviewer** under any of the following conditions. Do not work around them silently.

1. A PR's planned diff exceeds 600 meaningful LoC (after subtracting generated/snapshot data).
2. A PR requires changes outside its declared scope — touching files the §8 entry doesn't list — to compile or pass tests.
3. A test fails for a reason that suggests a gap in the engineering design plan (e.g., the design implies behavior X but the existing test asserts behavior Y, and they're incompatible).
4. The build fails with an error not recognizable after one diagnostic pass; consult `axiom-ios-build` skill if available, then escalate if still unclear.
5. The agent is about to make a public-API change not explicitly described in the engineering design plan.
6. The agent notices an unrelated bug, dead code, or cleanup opportunity. **Propose as a follow-up task; do not fix in the current PR.**
7. Three or more existing tests in the same area must be modified to pass under the new behavior. Test-rewrite scope is real risk; reviewer should confirm the modifications are correct, not bandaids.
8. A spike (Phase 0) discovers that an assumption in the engineering plan is wrong.
9. Stack rebase conflicts cannot be resolved mechanically — the conflict represents a semantic clash between in-flight PRs.
10. Anything else ambiguous. Asking is cheap; silent drift is expensive.

## 7. Review cadence and re-stack policy

### Cadence expectations

- The agent does not block on review beyond the §2 stacked-PR limit. If 2 PRs are open and unmerged, the agent waits.
- The agent does not work ahead of the reviewer's pace by more than 2 PRs.
- If review feedback is requested on an earlier PR while a later PR is open, the earlier PR is addressed first.

### Re-stack policy

The base for the entire stack is the long-lived `cache-rewrite/phase-1-plan` branch. The stack rebases whenever its tip advances:

- **When PR-N merges into `cache-rewrite/phase-1-plan`,** PR-(N+1) is rebased onto the new tip and its `--base` is updated to `cache-rewrite/phase-1-plan`. If conflicts are mechanical, resolve and force-push (this is acceptable for stacked PRs that have not yet received reviewer comments). If the rebased PR has reviewer comments, **do not force-push** without confirming with the reviewer.
- **When the plan branch itself is updated** (a commit landing directly on `cache-rewrite/phase-1-plan` to revise one of the three design docs), every open stacked PR is rebased onto the new tip in stack order at the start of the next session.
- **When `main` moves forward,** the plan branch is rebased onto `main` (since the plan branch is the long-lived feature base, it tracks `main`), and that rebase propagates up through every open stacked PR.
- Stack health check at session start: any open PR more than 7 days old, or with merge conflicts, is flagged to the reviewer for triage.

## 8. The PR list

**Convention.** Each entry below has a unique `PR-NNN` identifier. The identifier persists even if the order changes, so review threads can refer to a stable ID.

**Status legend.** ⬜ not started · 🟦 in progress · 🟨 PR open · 🟩 merged.

### Phase 0 — Design lock, ADRs, and performance baseline (5 PRs + 2 spike branches)

| ID | Title | Status | Base | Est. LoC | Tests required |
|---|---|---|---|---|---|
| PR-001 | docs(cache): ADR — major version bump rationale | ⬜ | `cache-rewrite/phase-1-plan` | ~150 | None (docs) |
| PR-002 | docs(cache): ADR — Record abstraction (field-aware via `CachedField`) | ⬜ | PR-001 | ~250 | None (docs) |
| PR-003 | docs(cache): ADR — TTL semantics (tri-state, selection-set scoped, read-mode split) | ⬜ | PR-002 | ~300 | None (docs) |
| PR-004 | docs(cache): ADR — Watcher × TTL (opt-in auto-refresh, permissive propagating reads) | ⬜ | PR-003 | ~250 | None (docs) |
| PR-004a | chore(cache): capture 2.x performance baseline dataset | ⬜ | PR-004 | ~600 | Unit: harness scenarios run cleanly against 2.x; baseline JSON produced and committed |

Phase 0 also produces two spike branches that are **not merged**:
- `cache-rewrite/phase-0-spike-sqlite-bench` — micro-benchmark of the new schema on iPhone 16 Pro hardware, validates the §7.4 performance gates from the engineering plan.
- `cache-rewrite/phase-0-spike-cachecontrol-jsdirective` — JS-side prototype of the `@cacheControl` directive transform; confirms the precedence algorithm and interface inheritance work.

Findings from each spike are captured in their respective Phase 0 ADRs (PR-003 references the SQLite spike; the cachecontrol-jsdirective spike findings become a `cache-rewrite/phase-0-adr-cachecontrol-spike` PR if material surprises surface — otherwise findings live as a comment thread on the existing ADR).

### Phase 1A — SQLite schema rewrite + field-aware `Record` (10 PRs)

Goal: ship 3.0-alpha at end of this phase. No behavior change for end users. Published performance dataset accompanies the alpha tag.

| ID | Title | Status | Base | Est. LoC | Tests required |
|---|---|---|---|---|---|
| PR-005 | feat(cache): introduce `CachedField` type (no consumers yet) | ⬜ | PR-004a | ~80 | Unit: `CachedField` Hashable/Sendable/Equatable; round-trip with sample values |
| PR-006 | refactor(cache): change `Record.fields` type to `[CacheKey: CachedField]` | ⬜ | PR-005 | ~400 | Update existing Record/RecordSet tests; verify `record[key]` subscript still returns `Value?` for all existing call sites |
| PR-007 | feat(sqlite): add `schema_metadata` table and version detection | ⬜ | PR-006 | ~150 | Unit: schema-version read/write, missing-row defaults to 0, version stamping on init |
| PR-008 | feat(sqlite): new schema DDL — records table with composite PK + typed columns | ⬜ | PR-007 | ~200 | Unit: table creation idempotent, `WITHOUT ROWID` preserved, schema_metadata version=3 stamped |
| PR-009 | feat(sqlite): implement insert/select/update/delete on new table (feature-flagged) | ⬜ | PR-008 | ~600 | Unit: each operation against new schema; round-trip Record↔rows; transactional behavior on failure; performance smoke test |
| PR-010 | feat(sqlite): switch `SQLiteNormalizedCache` to new schema; drop-and-rebuild migration | ⬜ | PR-009 | ~400 | Unit: migration on detected old schema; integration: existing cache tests pass on new schema; CachePersistenceTests updated |
| PR-011 | test(cache): SQLite performance-gate harness on iPhone 16 Pro | ⬜ | PR-010 | ~200 | Performance test asserting all §7.4 gates within 25% margin |
| PR-011a | feat(cache): comprehensive performance measurement harness (Tier 1 + Tier 2) | ⬜ | PR-011 | ~700 | Unit: each Tier 1 and Tier 2 scenario runs cleanly; JSON exporter produces well-formed output; harness is re-runnable across versions |
| PR-011b | chore(cache): alpha-vs-2.x comparison reporter + published dataset | ⬜ | PR-011a | ~400 | Unit: reporter generates `cache-rewrite-phase1-perf-dataset.json` and `cache-rewrite-phase1-perf-report.md` from harness JSON inputs; verdict thresholds applied per perf plan §5.1 |
| PR-012 | chore: tag 3.0-alpha; release notes; changelog | ⬜ | PR-011b | ~100 | Smoke test: clean install + first launch reads/writes a record. **Tag is gated on:** SQLite performance gates green AND no `regressed` verdict in the published dataset (or all such regressions explicitly accepted by the reviewer with documented rationale). |

### Phase 1B — `@cacheControl` codegen end-to-end (7 PRs)

Goal: codegen emits `cacheControl` metadata on `Selection.Field`. Runtime stores but does not yet enforce TTL — landed in Phase 1C.

| ID | Title | Status | Base | Est. LoC | Tests required |
|---|---|---|---|---|---|
| PR-013 | feat(codegen): add `@cacheControl` and `@cacheControlField` directive definitions to JS frontend | ⬜ | PR-012 | ~120 | JS unit: directive registration, schema extension AST roundtrip |
| PR-014 | feat(codegen): `cacheControlDirective.ts` precedence resolution algorithm + JS unit tests | ⬜ | PR-013 | ~700 | JS unit: all 9 cache-control-samples scenarios; interface inheritance with conflict; `inheritMaxAge` opt-in; bare `@cacheControl` rejected |
| PR-015 | feat(codegen): bridge resolved `cacheControlMaxAge` through `CompilationResult` | ⬜ | PR-014 | ~180 | Unit: bridge round-trip; nil for absent directive; explicit 0 distinguished from nil at the bridge if §12 question 2 says so |
| PR-016 | feat(api): add `Selection.CacheControlDirective` runtime type | ⬜ | PR-015 | ~100 | Unit: type Hashable/Sendable; convenience initializers |
| PR-017 | feat(ir): `IR.Field` exposes `cacheControlMaxAge` | ⬜ | PR-016 | ~120 | Unit: IR field reflects compilation-result value across precedence cases |
| PR-018 | feat(codegen): `SelectionSetTemplate` emits `cacheControl:` parameter when non-nil | ⬜ | PR-017 | ~250 | Snapshot tests: generated code with/without directive; minimal output for nil case |
| PR-019 | test(codegen): regenerate `TestCodeGenConfigurations`; snapshot tests for all 9 sample scenarios | ⬜ | PR-018 | ~600 | Snapshot tests; existing CodegenTests pass against regenerated APIs |

### Phase 1C — TTL evaluation and read-mode split (7 PRs)

Goal: `cacheControl` metadata is now consulted at read time; the `written_at` column populated since Phase 1A becomes load-bearing; watcher behavior splits into strict/permissive read modes.

| ID | Title | Status | Base | Est. LoC | Tests required |
|---|---|---|---|---|---|
| PR-020 | feat(cache): `TimeProvider` protocol + `SystemTimeProvider`; threaded into `ApolloStore` | ⬜ | PR-019 | ~150 | Unit: protocol conformance; mockable `TimeProvider` for tests |
| PR-021 | feat(cache): `TTLEnforcement` enum + `ApolloStore.load(_:ttlEnforcement:)` overload | ⬜ | PR-020 | ~150 | Unit: enum cases; load with both modes returns correct results when no TTL applies |
| PR-022 | feat(cache): TTL check in `CacheDataExecutionSource.resolveField` gated by enforcement | ⬜ | PR-021 | ~250 | Unit: strict path throws `missingValue` on expired field; permissive path returns value; `maxAge=0` always missing on strict; nil never missing |
| PR-023 | feat(cache): `GraphQLResultNormalizer` injects `writtenAt` on cache writes | ⬜ | PR-022 | ~180 | Unit: normalized records carry `writtenAt`; `TimeProvider` injection works |
| PR-024 | feat(cache): `GraphQLDependencyTracker` computes `earliestExpiry`; `GraphQLResponse.earliestExpiry` exposed | ⬜ | PR-023 | ~250 | Unit: nil when no field has finite TTL; correct minimum across mixed-TTL queries; excludes `maxAge=0` from the calc |
| PR-025 | feat(cache): watcher uses `.permissive` on `didChangeKeys` re-read | ⬜ | PR-024 | ~150 | Unit: watcher delivers cached value through TTL boundary on unrelated write; no automatic network refetch from time-based expiry |
| PR-026 | test(cache): `TTLTests.swift` covering all 9 sample scenarios + boundary cases | ⬜ | PR-025 | ~700 | Integration tests for every `cache-control-samples.md` scenario; boundary cases for `maxAge=0`, scalar inheritance, operation overrides, interface propagation, strict vs permissive |

### Phase 1D — Opt-in watcher refresh, hardening, beta (5 PRs)

Goal: ship 3.0-beta. Full feature visible to consumers.

| ID | Title | Status | Base | Est. LoC | Tests required |
|---|---|---|---|---|---|
| PR-027 | feat(cache): `GraphQLQueryWatcher.automaticallyRefreshOnExpiry` flag + timer scheduling | ⬜ | PR-026 | ~400 | Unit: timer fires at earliest finite expiry; reschedules on result; cancels on watcher cancel; excludes `maxAge=0` from scheduling; uses `.cacheFirst` on fire |
| PR-028 | feat(cache): `InMemoryNormalizedCache` parity for TTL | ⬜ | PR-027 | ~120 | Unit: in-memory writes carry `writtenAt`; in-memory reads honor `TTLEnforcement` |
| PR-029 | docs(cache): migration guide in `Documentation.docc` for 3.0 | ⬜ | PR-028 | ~500 | None (docs); manual proofread by reviewer |
| PR-030 | feat(samples): demonstrate `@cacheControl` usage in `TestCodeGenConfigurations` | ⬜ | PR-029 | ~250 | Codegen regression: existing test code generation continues to succeed with new samples |
| PR-031 | chore: tag 3.0-beta; final changelog; release announcement draft | ⬜ | PR-030 | ~150 | Internal beta cycle (1 week); zero P0/P1 issues open |

### Total

- **34 PRs** across 4 phases (Phase 0: 5; Phase 1A: 10; Phase 1B: 7; Phase 1C: 7; Phase 1D: 5).
- **~8,950 meaningful LoC** of change at midpoint estimates.
- The estimates are guidance, not contracts. Splitting a PR is preferred to overrunning the §2 cap.

## 9. Session bootstrap

Every Claude Code session that resumes this work follows these steps before doing anything else:

1. Read `~/.claude/projects/-Users-amdev-repos-apollo-ios-dev/memory/MEMORY.md`.
2. Read `~/.claude/projects/-Users-amdev-repos-apollo-ios-dev/memory/project_cache_rewrite.md`.
3. Read this execution plan; locate the next un-started PR in §8.
4. Read the engineering plan section that PR implements.
5. `git status` and `git branch -vv` to see local state.
6. `gh pr list --author @me --state open` to see in-flight PRs.
7. If there are open PRs, check their review status (`gh pr view <number>`) and address review feedback before starting new work.
8. If the stack is up-to-date, pull `main` and rebase the bottom of the stack if needed.

If any step reveals state that doesn't match the expected workflow (rogue branches, force-pushed history, half-merged PRs), **stop and escalate**.

## 10. Done conditions

All "merged" references below mean **merged into `cache-rewrite/phase-1-plan`**, not into `main`. The plan branch itself is merged into `main` only after Phase 1 is fully complete (see "Phase 1 done" below).

### Per-phase done

- **Phase 0 done:** PR-001 through PR-004a merged into `cache-rewrite/phase-1-plan`; both spike branches' findings captured in ADRs; 2.x baseline performance dataset checked in.
- **Phase 1A done:** PR-005 through PR-012 merged; 3.0-alpha tag pushed from `cache-rewrite/phase-1-plan`; SQLite performance gates green in CI; published comparison dataset (`cache-rewrite-phase1-perf-dataset.json`) shows no `regressed` verdict for any Tier 1 or Tier 2 scenario, or all such regressions explicitly accepted with documented rationale.
- **Phase 1B done:** PR-013 through PR-019 merged; codegen produces `cacheControl:` on `Selection.Field`; all `TestCodeGenConfigurations` regenerated and pass.
- **Phase 1C done:** PR-020 through PR-026 merged; TTL is enforced on strict reads; watcher uses permissive reads; `TTLTests.swift` covers every documented scenario.
- **Phase 1D done:** PR-027 through PR-031 merged; opt-in watcher refresh works; `InMemoryNormalizedCache` has TTL parity; migration guide live; 3.0-beta tag pushed from `cache-rewrite/phase-1-plan`; 1-week internal beta complete with zero P0/P1 issues.

### Phase 1 done

All 31 PRs merged into `cache-rewrite/phase-1-plan`. Migration guide validated by at least one external user. Engineering-plan §10 risks reviewed and either retired or escalated to Phase 2 planning. **Then, and only then,** `cache-rewrite/phase-1-plan` is merged into `main`. The 3.0-beta tag is republished from `main` if needed; the 3.0 final tag is cut from `main` when the public beta cycle completes.

## 11. Living document

This is a living document. As the work proceeds, the §8 PR list may evolve:
- A PR may split into two if scope is larger than estimated → renumber from the split point or use sub-IDs (`PR-009a`, `PR-009b`).
- A PR may be dropped if discovery shows it's unnecessary → mark `~~PR-NNN~~ — DROPPED, see <reason>`.
- Order may shift in response to learnings → update the table; do not delete entries.

All such changes are made in their own `docs(cache): update execution plan` PRs, not silently.
