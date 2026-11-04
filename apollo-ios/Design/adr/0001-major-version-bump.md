# ADR 0001 — Apollo iOS 3.0: Major version bump for the cache rewrite

- **Status:** Accepted
- **Date:** 2026-05-07
- **Phase 1 PR:** PR-001 (cache rewrite execution plan §8)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §3.1](../cache-rewrite-phase1-plan.md)

## Context

Phase 1 of the cache rewrite introduces multiple breaking changes that must ship coordinated in a single release. They are not independent of each other and cannot be delivered piecemeal under semantic versioning rules:

1. **SQLite schema change.** The on-disk records table moves from a single `(_id, key, record TEXT)` JSON-blob layout to a row-per-field layout: `WITHOUT ROWID` table with composite primary key `(cache_key, field_name)` and per-type value columns. Existing 2.x cache databases on disk are not readable by the new schema; on first launch the cache is dropped and rebuilt from the network. This is a behavior change visible to end users (one extra network round trip on upgrade day) even if it is not a compile-time API change.
2. **Public `Record` API change.** `Record.fields` changes type from `[CacheKey: any Hashable & Sendable]` to `[CacheKey: CachedField]`, where `CachedField` carries the field value plus its `writtenAt` epoch timestamp. The `record[key]` subscript stays backward-compatible (returns the unwrapped value), so the executor and most consumers do not change. However, any code that iterates `record.fields` directly — including custom `NormalizedCache` implementations in user codebases — must update.
3. **Generated code shape change.** The codegen frontend (`apollo-ios-codegen`) gains `@cacheControl(maxAge:)` directive support. Generated `Selection.Field` declarations may carry a new `cacheControl:` parameter. Generated code from the 3.0 codegen will not compile against the 2.x runtime (the `Selection.Field` initializer it expects to call does not exist in 2.x). This is a hard-coupled break between codegen and runtime.
4. **TTL evaluation behavior.** Cache reads under 3.0 may return cache miss for fields whose `@cacheControl` TTL has elapsed; under 2.x, no such miss path exists. While only schemas that adopt the new directive observe this behavior change, the change in semantics is real and warrants a major version. The watcher × TTL interaction (a new opt-in `automaticallyRefreshOnExpiry` flag, and the strict-vs-permissive read mode split for watcher re-reads on `didChangeKeys`) is part of this same TTL feature surface and is covered separately by ADR 0004; it does not constitute an independent breaking change because the permissive read path bypasses only TTL-induced misses, while genuine missing-value misses still throw and still trigger `cacheReadFailed` → network refetch — preserving the existing 2.x revalidation behavior for any consumer who has not adopted `@cacheControl` directives.

Each of these changes is locked into the design (see decisions 3.1–3.5 in the engineering plan). The question for this ADR is the **release vehicle**: a major version bump on Apollo iOS, a feature-flagged dual-stack on 2.x, or a long deprecation cycle across multiple 2.x minors.

## Decision

**Apollo iOS 3.0 ships the Phase 1 cache rewrite as a coordinated breaking release.** A single major version bump delivers all four breaking changes in lockstep. There is no feature flag, no parallel codepath, and no dual-stack. Two pre-release tags are cut from the long-lived plan branch en route — 3.0-alpha at the end of Phase 1A (storage refactor only, no observable behavior change for end users) and 3.0-beta at the end of Phase 1D (full feature). The 3.0 final tag is cut from `main` after the long-lived plan branch merges and the public beta cycle completes.

Apollo iOS 2.x enters maintenance mode upon 3.0's general availability. Critical fixes will continue on 2.x for a defined period; new features land only on 3.0.

## Alternatives considered

### A. Feature flag on 2.x

Add the new SQLite schema, `@cacheControl` directive, and TTL evaluation to 2.x behind a runtime feature flag. Customers opt in by enabling the flag; the legacy code path remains the default.

- *Rejected because:* The breaking surface is too broad to dual-maintain. Five distinct subsystems (SQLite, the public `Record` type, codegen frontend, runtime executor, watcher) would each need a dual-mode implementation. The codegen change is not feature-flaggable in any meaningful sense — generated code either emits the new metadata or it does not, and a single 2.x codegen cannot do both. Test surface roughly doubles. Maintenance burden compounds with every subsequent change to 2.x. The cumulative engineering cost exceeds the cost of the major bump itself, and the user-visible benefit (avoiding a major version label) is small.

### B. Staged minor releases with deprecation cycles

Spread the breaking changes across a sequence of 2.x minors, each deprecating one piece of API and offering a migration path before the next minor removes it. The ultimate 3.0 release would then be a no-op cleanup release that simply drops the deprecations.

- *Rejected because:* The cache shape changes are not independently deliverable. The new SQLite schema, the `CachedField` type, and per-field `writtenAt` are all required for TTL evaluation; you cannot ship the SQLite work without the `Record` change without producing an incoherent middle state. Likewise, `@cacheControl` codegen and runtime TTL enforcement are coupled — generating metadata that the runtime ignores is a confusing intermediate state to ship. Staging would force artificial separation that produces unreviewable, unshippable middle releases. The deprecation-cycle approach works for narrow API renames; it does not work for coordinated subsystem replacement.

### C. Parallel cache module on 2.x (e.g., `ApolloCache2`)

Introduce a new module (`ApolloCache2` or similar) carrying the new cache types alongside the existing `ApolloSQLite` and `ApolloCaching`. Customers migrate by importing the new module and switching their `ApolloClient` configuration.

- *Rejected because:* This is a feature flag with extra ceremony. Same dual-stack maintenance burden as Option A, additional surface area for the public module split, and a permanent forked codebase even after migration is complete. It also does not address the codegen-to-runtime coupling — the codegen would still need to choose which module's types to emit references against, which is functionally a feature flag.

### D. Defer parts of Phase 1 (storage now, TTL later)

Ship the SQLite/`Record` storage refactor as Apollo iOS 3.0, then ship the `@cacheControl` directive and TTL evaluation as a 3.1 or 4.0 release.

- *Rejected because:* This *is* the plan internally — Phase 1A produces a 3.0-alpha that is the storage refactor in isolation, and Phase 1D produces 3.0-beta with the full feature. Splitting them into separate major (or minor) releases would force two migration cycles on customers within months of each other, when the design plan already validates that the same customers can absorb the full Phase 1 scope as a single 3.0. The internal phasing achieves the de-risking benefit without the externally-visible cost of two breaking releases.

### E. Hold all of it until Phase 2 is also designed

Combine Phase 1 and Phase 2 (cascading deletes, eviction, `ChainedNormalizedCache`) into a single 3.0 release.

- *Rejected because:* Phase 2 is unestimated and depends on Phase 1 landing first. Holding 3.0 hostage to Phase 2 design extends the Phase 1 timeline unboundedly. The opt-in TTL feature delivers value to customers who want it; Phase 2 features deliver additional value but are not prerequisites for the Phase 1 features to be useful.

## Consequences

### Positive

- **Atomic migration story.** Customers upgrade once, regenerate code once, write one round of migration changes, and land on a coherent 3.0 surface.
- **Engineering simplicity.** No feature flags to maintain, no dual codepaths to test, no codegen mode-switching. The 3.0 codebase is the only codebase under active development.
- **Clear semver signal.** Apollo iOS 3.0 communicates "breaking changes; consult migration guide" through a channel customers already understand.
- **Internal phasing intact.** The 3.0-alpha milestone (after Phase 1A) still de-risks the SQLite/`Record` work in production-like conditions before TTL behavior is committed; the alpha is shippable and observable without committing customers to the directive feature.

### Negative

- **2.x maintenance burden during the transition.** Until 3.0 reaches general availability, critical fixes may need to be backported. Mitigation: define a 2.x maintenance-window policy in the migration guide (e.g., 6 months of critical fixes after 3.0 GA).
- **Day-one network load on upgrade.** The drop-and-rebuild cache migration causes one extra round of network fetches for cached queries on first 3.0 launch. Acceptable per ADR 0003 (TTL semantics) and engineering plan §3.3, but explicitly called out in the migration guide.
- **Coordinated PR planning required.** The 31-PR Phase 1 stack must land coherently on the long-lived plan branch before any of it reaches `main`. Mitigation: the execution plan §3 documents the long-lived plan-branch workflow; the `cache-rewrite/phase-1-plan` branch holds all PRs until the stack is complete.
- **Existing 2.x users with custom `NormalizedCache` implementations must update on upgrade.** The `Record.fields` type change is the most likely public-API break encountered. Mitigation: a deprecation-period accessor (`var fieldsLegacy: [CacheKey: Value]` on 3.x for one minor cycle) is offered as a fallback if a non-trivial population of custom-cache users surfaces during the beta cycle. See engineering plan §12 open question 5.

## References

- [Engineering plan §3.1](../cache-rewrite-phase1-plan.md) — *Major version bump (3.0)*
- [Engineering plan §3.2](../cache-rewrite-phase1-plan.md) — `Record` becomes field-aware (covered separately in ADR 0002)
- [RFC: cache rewrite](../rfc-caching-rewrite.md) — original RFC on the `design/rfc-caching` branch
- [Execution plan §8](../cache-rewrite-phase1-execution.md) — PR-001 entry
- [Apollo iOS 2.0 release](https://github.com/apollographql/apollo-ios-dev/pull/780) — most recent prior major version, for reference on the migration-guide template and maintenance-window precedent
