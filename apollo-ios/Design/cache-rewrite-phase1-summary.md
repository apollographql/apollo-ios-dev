# Cache Rewrite — Phase 1 Summary

**Audience:** Engineering management.
**Companion document:** [cache-rewrite-phase1-plan.md](./cache-rewrite-phase1-plan.md) — engineering design and implementation detail.
**Source RFC:** [rfc-caching-rewrite.md](./rfc-caching-rewrite.md).

## TL;DR

Apollo iOS 3.0 will replace the SQLite normalized-cache layer with a row-per-field schema and introduce per-field Time-to-Live via a new `@cacheControl` directive. This is the first phase of the cache rewrite outlined in the RFC. Phase 1 ships only the foundation (SQLite restructure + TTL); other RFC features (cascading delete, eviction, cache chaining) are deferred to Phase 2. The work is led by a single engineer.

**Bottom-line ask:** authorize a single-engineer effort of approximately **6 to 7 months calendar time** to deliver Apollo iOS 3.0-beta with foundations and TTL.

## What ships in Phase 1

- New SQLite schema: `WITHOUT ROWID` table with composite primary key `(cache_key, field_name)` and per-type value columns. Recommended structure validated by Zach's earlier benchmark.
- A new `@cacheControl(maxAge:)` directive in the GraphQL schema and operation language. Per-field TTL with documented precedence rules (schema type → schema field → operation type → operation field).
- Per-field expiry checking on cache reads. Selection-set scoped: if any field a query needs has expired, the query refetches from the network; unrelated fields on the same record are unaffected.
- Optional auto-refresh on watchers, opt-in via a new initialization flag.
- Drop-and-rebuild migration on first launch under 3.0 (the cache is not a source of truth; rebuilding from network is acceptable).

## What is not in Phase 1 (deferred to Phase 2)

- `@onDelete` directive and cascading record deletion.
- `NormalizedCacheConfiguration` with size limits and LRU eviction.
- `ChainedNormalizedCache` (in-memory + SQLite chained writes).
- Object/field watchers and faceted searching (RFC explicitly calls these out as further-future).

Phase 2 is unestimated and outside the scope of this plan.

## Timeline

| Phase | Focus | Engineer-weeks | Calendar weeks |
|---|---|---|---|
| **0** | Design lock + two de-risking spikes (SQLite, codegen) | 2 | 2 |
| **1A** | SQLite schema rewrite + field-aware `Record` (**3.0-alpha** ships from this milestone) | 4 | 6–7 |
| **1B** | `@cacheControl` codegen end-to-end | 4 | 5–6 |
| **1C** | TTL evaluation + read-mode split | 3 | 4 |
| **1D** | Opt-in watcher refresh + hardening + **3.0-beta** | 4 | 4–5 |
| **Total effort** | | ~17 | |
| **Calendar (with reviews and interruptions)** | | | **21–24 (≈ 5–6 months)** |
| **Calendar with 25% contingency** | | | **27–30 (≈ 6–7 months)** |

The 25% contingency is the number to plan against. This subsystem has deep coupling between the runtime, the codegen frontend, and roughly 8,400 lines of cache-related test code; estimates without contingency consistently underrun in projects of this shape.

**Two release tags ship from the plan.** A 3.0-alpha lands at the end of Phase 1A — storage refactor only, no behavior change for end users. This validates the riskiest piece of the project (new SQLite schema, drop-and-rebuild migration, public `Record` type change) in production-like conditions before TTL behavior is layered on top. A 3.0-beta lands at the end of Phase 1D with the full `@cacheControl` feature.

## Top risks

1. **Test surface.** ~8,400 lines of cache tests must be re-evaluated. Some semantics genuinely change under the new model (a previously-cached query may now miss because it includes a `maxAge=0` field). Budgeted into Phase 1B and 1C; expect surprises.
2. **Codegen-runtime coupling.** Generated code from 3.0 will not run against 2.x runtime, and vice versa. Clear upgrade guidance and tooling needed.
3. **Single-engineer concentration risk.** This is a deep subsystem with no second engineer cross-checking. Recommend assigning a consistent reviewer across all phases to mitigate bus factor.
4. **Watcher × TTL semantics.** Watchers do not auto-refresh on time-based expiry by default; users opt in via a new flag. The default behavior is a deliberate choice (avoid surprise network calls from unrelated cache writes) and is documented in the migration guide. Some users may expect the opposite default.
5. **Migration UX.** The drop-and-rebuild on first 3.0 launch means a network round trip on day one of upgrade. Acceptable, but worth a dedicated test on a real customer profile before locking it in.

## Decisions already locked

These were settled in design discussion before this document was written. The companion engineering doc explains each in detail.

1. **Major version bump (3.0)** — breaking changes acceptable.
2. **Field-aware Record type** — `Record.fields` becomes `[CacheKey: CachedField]` with `value + writtenAt`. The `record[key]` subscript stays backward-compatible.
3. **Drop-and-rebuild migration** — no in-place migration of cached data.
4. **Selection-set-scoped per-field TTL** — any expired field in the current selection causes a whole-query refetch; fields outside the selection are not checked.
5. **Tri-state `maxAge` semantics** — no directive (cache forever) / `maxAge: 0` (force-refetch on consumer-initiated reads) / `maxAge: N` (expire after N seconds). `@cacheControl` with no `maxAge` argument is a codegen error.

## What I need

- **Approval to proceed** with Phase 0 (2-week design lock + codegen-frontend spike). Phase 0 produces the design doc that authorizes Phases 1A–1D.
- **Confirmation of the major-version bump** as the release vehicle. Phase 1 is a breaking change to generated code, the SQLite schema, and the public `Record` type. Shipping it on 2.x is not feasible.
- **Reviewer assignment** for the duration of the project. The work runs through the codegen frontend, runtime, and SQLite layer; a single consistent reviewer reduces context-switching cost and bus factor.

The engineering doc has the full implementation plan, decision rationale, risk register, and Phase 0 entry criteria.
