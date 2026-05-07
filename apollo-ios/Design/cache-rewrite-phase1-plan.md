# Cache Rewrite — Phase 1 Engineering Design

**Audience:** Engineering — implementer, reviewer, future maintainers.
**Companion document:** [cache-rewrite-phase1-summary.md](./cache-rewrite-phase1-summary.md) — manager-facing summary.
**Source RFC:** [rfc-caching-rewrite.md](./rfc-caching-rewrite.md).
**Reference benchmark:** "SQLite Performance Benchmarks" (Confluence, ClientDev space, page 1585152147).
**Sample resolution rules:** [Samples/cache-control-samples.md](./Samples/cache-control-samples.md).

## 1. Background and motivation

The RFC proposes a major-version cache rewrite for Apollo iOS. Phase 1 — the subject of this document — is foundations and TTL only. Specifically:

- Restructure the SQLite schema from a JSON-blob layout to a row-per-field layout.
- Add a `@cacheControl(maxAge:)` directive end-to-end through the GraphQL compiler, IR, codegen, and runtime.
- Implement per-field TTL evaluation on cache reads.
- Provide an opt-in auto-refresh path for `GraphQLQueryWatcher`.

The RFC explicitly defers cascading deletion (`@onDelete`), size-limited LRU eviction, `ChainedNormalizedCache`, and watcher/search features to a later phase. This document scopes only Phase 1.

## 2. Current-state audit

Before the work begins, the codebase already contains more of the required infrastructure than the RFC implies. The following table captures what is in place and what must be built.

| Item | State | File / location |
|---|---|---|
| SQLite.swift dependency removed | **Done** (apollo-ios#635, April 2025) | [ApolloSQLiteDatabase.swift](../Sources/ApolloSQLite/ApolloSQLiteDatabase.swift) — direct `SQLite3` C API |
| Apollo iOS 2.0 baseline | Just merged ([apollographql/apollo-ios-dev#780](https://github.com/apollographql/apollo-ios-dev/pull/780)) | Field policies, request chain, Swift 6 already in `main` |
| Field-grained in-memory cache model | Already exists | [Record.swift](../Sources/Apollo/Caching/Record.swift) — `(key, [field: value])`. Only the SQLite serialization is JSON-blob; the in-memory APIs are field-level |
| Schema directive plumbing | Mature pattern | [apolloCodegenSchemaExtension.ts](../../apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/src/utilities/apolloCodegenSchemaExtension.ts) defines `@typePolicy`, `@fieldPolicy`. New directives follow the same path |
| Field-level metadata in generated code | Already exists | [SelectionSetTemplate.swift:352](../../apollo-ios-codegen/Sources/ApolloCodegenLib/Templates/SelectionSetTemplate.swift) emits `fieldPolicy: .init(...)`. Pattern carries directly to `cacheControl:` |
| Directive interface inheritance with conflict detection | Already implemented | [typePolicyDirective.ts](../../apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/src/utilities/typePolicyDirective.ts:68-89) walks `getInterfaces()` and merges; we model `@cacheControl` inheritance on the same algorithm |
| Single `CacheInterceptor` protocol with default implementation | Well-bounded | [CacheInterceptor.swift](../Sources/Apollo/RequestChain/Interceptors/CacheInterceptor.swift) |
| `@cacheControl` directive support | **Does not exist** | Verified by grep across `apollo-ios/Sources/` and `apollo-ios-codegen/Sources/` |
| `@onDelete` directive support | **Does not exist** | Phase 2 |
| Per-field write timestamp | **Does not exist** | `Record` has no `writtenAt` |
| Cache-eviction logic | **Does not exist** | Phase 2 |
| Cache test coverage | Substantial | ~8,400 lines under `Tests/ApolloTests/Cache/` (FieldPolicyTests 1,563; ReadWriteFromStoreTests 2,563; WatchQueryTests 2,079) |

### Implications for the plan

1. **The "remove SQLite.swift" step from the RFC is already shipped.** Phase 1 starts directly on the row-per-field schema work.
2. **The directive plumbing is well-trodden.** Adding `@cacheControl` is a known-shape task, not invention.
3. **The in-memory `Record` shape doesn't need to change for storage reasons** — only the SQLite serialization layer is JSON-blob. We are changing `Record` anyway because of TTL bookkeeping (decision 2 below), but the change is independent of the SQLite work.
4. **The test surface is substantial.** A meaningful share of Phase 1 calendar time is test rewrites, not new code.

## 3. Locked architectural decisions

Each decision is final unless explicitly reopened in Phase 0.

### 3.1 Major version bump (3.0)

The schema change to generated code, the new SQLite schema, and the change to `Record.fields` are all breaking. Phase 1 ships as Apollo iOS 3.0. Feature-flagging on 2.x was rejected — the surface area of the change is too broad to dual-maintain.

### 3.2 `Record` becomes field-aware

```swift
public struct CachedField: Sendable, Hashable {
  public let value: Value          // any Hashable & Sendable
  public let writtenAt: Int64      // epoch seconds
  // Future: lastAccessedAt for LRU; parent refs for @onDelete; etc.
}

public struct Record: Sendable, Hashable {
  public let key: CacheKey
  public typealias Fields = [CacheKey: CachedField]
  public private(set) var fields: Fields

  // Backward-compatible read of the value alone.
  public subscript(key: CacheKey) -> Value? { fields[key]?.value }

  // New API to access the metadata.
  public func cachedField(for key: CacheKey) -> CachedField? { fields[key] }
}
```

**Rationale.** Considered three options:
- Option A: keep `Record` as `(key, [field: value])` and store TTL state in a parallel side-channel dictionary on the cache.
- Option B: change `Record.fields` to `[field: CachedField]`, so each field carries its own metadata.
- Option C: lazy-loaded fields with cache-handle proxies.

Selected B because:
1. The major-version bump is the right time to absorb the breaking change.
2. Option A's parallel side-channel ages badly: every place that writes a `Record` must also remember to update the timestamp dict, which is a silent-drop bug surface.
3. Option B maps 1:1 to the row-per-field SQLite layout — round-trip is type-direct.
4. `CachedField` is the natural home for future Phase 2 metadata (LRU access timestamps, `@onDelete` parent references, faceted-search typed values).

The `record[key]` subscript stays backward-compatible (returns `Value?`), so the executor in [CacheDataExecutionSource.swift](../Sources/Apollo/Execution/ExecutionSources/CacheDataExecutionSource.swift) needs no change. The breaking surface is `Record.fields`'s declared type and any code that constructs a `Record` directly — about ~10 call sites in the runtime and ~4 in tests.

Custom `NormalizedCache` implementors (the public protocol contract) take a one-paragraph migration note.

### 3.3 Drop-and-rebuild migration

On first launch under 3.0, the SQLite cache file is detected as old-schema (or the schema check fails) and the cache is dropped and recreated in the new schema. No in-place data migration.

**Rationale.** The cache is not a source of truth — its contents are reproducible from the network. Building a row-by-row migration tool would carry significant test surface for a one-time event. A clean rebuild is robust, predictable, and trivially correct.

**User impact.** Day-one of upgrade requires a network fetch for previously-cached data. Acceptable; explicitly called out in the migration guide.

### 3.4 Selection-set-scoped per-field TTL

When a query is executed against the cache, TTL is checked **only** for fields the query selects. If any selected field has expired (`writtenAt + maxAge < now`), the entire query is treated as a cache miss and refetched.

Fields that exist on the same `Record` but are not in the current query's selection set are **not** evaluated. Their staleness is irrelevant to this read.

**Rationale.** Different queries select different subsets of an object's fields. A high-precision query may need only the always-fresh fields; a casual query may need only fields that change rarely. Treating the whole record as expired-or-not is too coarse and would force unnecessary refetches.

**Implementation.** TTL evaluation lives in the read path inside `CacheDataExecutionSource.resolveField`. When `cacheControl.maxAge > 0` and `writtenAt + maxAge < now`, the resolver throws `JSONDecodingError.missingValue`. The existing missing-value propagation in [GraphQLExecutor.swift](../Sources/Apollo/Execution/GraphQLExecutor.swift) and [ApolloStore.load](../Sources/Apollo/Caching/ApolloStore.swift:142) turns this into a cache miss naturally — no new error type, no new control flow.

### 3.5 Tri-state `maxAge` semantics

| Schema | Resolved generated code | Runtime behavior |
|---|---|---|
| (no directive applied) | `cacheControl:` parameter omitted | No TTL check; cache indefinitely |
| `@cacheControl(maxAge: 0)` | `cacheControl: .init(maxAge: 0)` | Always treated as cache miss on consumer-initiated reads (per-field force-refetch) |
| `@cacheControl(maxAge: N)` where `N > 0` | `cacheControl: .init(maxAge: N)` | Check `writtenAt + N < now` |
| `@cacheControl` (no `maxAge` arg) | **Codegen error** | — |

`Selection.Field.cacheControl` is `CacheControlDirective? = nil`. Generated files for fields with no directive omit the parameter entirely (smaller files; common case is cheaper).

**Rationale.**
- The Apollo cache spec ([specs.apollo.dev/cache/v0.2](https://specs.apollo.dev/cache/v0.2/)) is silent on the meaning of `maxAge: 0` or the no-directive default. Apollo iOS gets to define this.
- Treating "no directive" as "uncacheable" would silently disable the cache for every customer who upgrades without annotating their schema. Unacceptable migration.
- Making `maxAge: 0` mean "always refetch on demand" gives schema authors per-field volatility control that nothing else provides. They mark `Stock.currentPrice` as volatile once and every query touching it refetches; queries that don't include it cache normally. Cheaper than per-query `cachePolicy: .networkOnly`.
- Requiring an explicit `maxAge:` argument when the directive is written eliminates the footgun of someone writing bare `@cacheControl` and getting unintended behavior.

**Migration-guide note.** Users who want "always refetch this entire query" should use `cachePolicy: .networkOnly` on the operation. `@cacheControl(maxAge: 0)` is for per-field volatility, not per-query cache-busting.

## 4. TTL semantics specification

### 4.1 Resolution algorithm (codegen-time)

For each scalar field reachable from a query, the codegen frontend resolves `maxAge` using the following precedence (most-specific wins):

1. `@cacheControl` on the field in the operation
2. `@cacheControl` on the field in the schema
3. `@cacheControl` on the parent type in the operation (if applicable; not standard GraphQL but supported via inline directives in some setups — Phase 0 to confirm)
4. `@cacheControl` on the parent type in the schema
5. Inherited from interfaces the parent type implements (with conflict detection between interfaces — same algorithm as `@typePolicy` already uses)
6. None — the field has no `maxAge` resolved.

For composite (object) types, the rule differs:
- Composite types do **not** automatically inherit from their parent. A composite field's `maxAge` is determined from its own schema/operation directives.
- The directive `@cacheControl(inheritMaxAge: true)` opts a composite type or field into parent inheritance explicitly.

For scalars, inheritance is automatic from the parent object's `maxAge` unless overridden.

All scenarios in [Samples/cache-control-samples.md](./Samples/cache-control-samples.md) must produce the documented resolved values when run through the codegen frontend.

### 4.2 Read-path enforcement (runtime)

```swift
// Pseudocode inside CacheDataExecutionSource.resolveField
guard let cachedField = record.cachedField(for: cacheKeyForField) else {
  throw JSONDecodingError.missingValue(reason: .absent)
}

if let maxAge = field.cacheControl?.maxAge {
  let isExpired = (maxAge == 0) || (cachedField.writtenAt + Int64(maxAge) < now)
  if isExpired {
    if ttlEnforcement == .strict {
      throw JSONDecodingError.missingValue(
        reason: .expired(writtenAt: Date(timeIntervalSince1970: TimeInterval(cachedField.writtenAt)),
                         maxAge: maxAge)
      )
    }
    // Permissive: continue with the value, but mark the read so the assembled
    // response's source becomes .cache(containsStaleFields: true).
    executionContext.markCacheContainsStaleFields()
  }
}

return cachedField.value
```

The `ttlEnforcement` parameter is propagated from the call site. See section 5 for the read-mode split. The `MissingValueReason` enum and the `Source.cache(containsStaleFields:)` design are specified in ADR 0005.

### 4.3 Write-path timestamp injection

`SelectionSetDataResultNormalizer` and `RawJSONResultNormalizer` (both in [GraphQLResultNormalizer.swift](../Sources/Apollo/Execution/ResultAccumulators/GraphQLResultNormalizer.swift)) inject `Date.now` (as epoch seconds) into each `CachedField` they produce when normalizing a network response into a `RecordSet`.

A protocol-injected clock allows tests to control time:

```swift
protocol TimeProvider: Sendable {
  var nowEpochSeconds: Int64 { get }
}
struct SystemTimeProvider: TimeProvider {
  var nowEpochSeconds: Int64 { Int64(Date().timeIntervalSince1970) }
}
```

The provider is held by `ApolloStore` and threaded into the normalizer construction.

## 5. Read-mode split

Two read modes exist on `ApolloStore.load`:

| Mode | TTL behavior | Used by |
|---|---|---|
| `.strict` (default) | TTL enforced; expired fields throw `missingValue`; query becomes a cache miss | `client.fetch(query:)`, `watcher.fetch(...)` (any explicit fetch by the consumer), watcher auto-refresh timer firing |
| `.permissive` | TTL ignored; deliver whatever the cache currently contains | Watcher re-read on `didChangeKeys` |

API:

```swift
public enum TTLEnforcement: Sendable { case strict, permissive }

public func load<Operation: GraphQLOperation>(
  _ operation: Operation,
  ttlEnforcement: TTLEnforcement = .strict
) async throws -> GraphQLResponse<Operation>?
```

**Rationale.** Distinguishes *initiating* reads (consumer asked for data; TTL is appropriate) from *propagating* reads (watcher is keeping its delivered result in sync with cache changes; TTL is irrelevant to the propagation). Without this split, a watcher whose query happens to share dependent keys with an unrelated mutation would refetch from the network every time that mutation fired, which is surprise behavior the consumer didn't ask for.

## 6. Watcher × TTL behavior

### 6.1 Default behavior (no opt-in)

- Watcher continues to subscribe to `ApolloStore.didChangeKeys` events and re-read on overlap (existing behavior).
- The re-read uses `ttlEnforcement: .permissive`.
- Time-based expiry has no effect on the watcher's delivered output. The watcher's last-delivered result remains visible until either:
  - A cache write to a dependent key triggers a re-read (which delivers the post-write value, regardless of TTL), or
  - The consumer explicitly calls `watcher.fetch(cachePolicy: .cacheFirst)` — that goes through the strict read path and refetches on TTL miss.

### 6.2 Opt-in auto-refresh

```swift
let watcher = await GraphQLQueryWatcher(
  client: client,
  query: query,
  automaticallyRefreshOnExpiry: false,    // new flag, default false
  resultHandler: { ... }
)
```

When `true`:

1. After every successful result delivery, the watcher computes the **earliest finite expiry** across all fields in `dependentKeys`. Fields with `maxAge: 0` are excluded from this calculation (they have no schedulable expiry).
2. The watcher schedules a one-shot `Task` that sleeps until the earliest expiry.
3. When the timer fires, the watcher calls `fetch(cachePolicy: .cacheFirst)`. The strict read path will hit the network if anything has expired; otherwise it redelivers the cached value. Either path produces a result, which triggers a reschedule.
4. Cache writes that arrive via `didChangeKeys` (the propagating-read path) cancel the existing timer and reschedule based on the post-merge timestamps.
5. Watcher cancellation cancels the timer.

### 6.3 `maxAge: 0` interaction

Resolved by combining the two preceding rules:
- Default watcher: permissive read on `didChangeKeys` ignores the always-stale field; no thrash.
- Opt-in watcher: `maxAge: 0` fields are excluded from timer scheduling; no thrash from the timer. The propagating-read path is permissive even in opt-in mode (the opt-in flag controls timers, not read mode), so unrelated writes don't trigger refetches either.

`maxAge: 0` fields refresh only when the consumer explicitly initiates a fetch (`watcher.fetch(...)` or a fresh `client.fetch(query:)`). This is the documented contract.

### 6.4 Required additions to `GraphQLResponse`

Two pieces of metadata, both computed during the cache read pass and surfaced on `GraphQLResponse`:

```swift
public struct GraphQLResponse<Operation: GraphQLOperation> {
  // existing fields preserved
  public let source: Source                  // shape changes; see below
  public let earliestExpiry: Date?           // nil if no field has finite TTL
}

// Source.cache gains an associated value to carry the staleness signal.
public enum Source: Sendable {
  case cache(containsStaleFields: Bool)
  case network
}
```

- `earliestExpiry: Date?` is the minimum of `writtenAt + maxAge` across fields with finite TTL. Used by the watcher's auto-refresh timer (§6.2). Excludes `maxAge: 0` fields (they have no schedulable expiry).
- `Source.cache(containsStaleFields:)` is set during cache reads in permissive mode: `true` if any selected field had a finite TTL or `maxAge: 0` and was returned despite being expired; `false` for fully-fresh cache hits. It is structurally inapplicable to network-sourced responses, hence the associated value lives on the `.cache` case rather than at the top level of `GraphQLResponse`. ADR 0005 is the design reference.

`GraphQLDependencyTracker` is extended to compute both in the same pass that produces `dependentKeys`.

## 7. SQLite schema

### 7.1 New schema (DDL)

```sql
CREATE TABLE IF NOT EXISTS records (
  cache_key            TEXT NOT NULL,
  field_name           TEXT NOT NULL,
  int_value            INTEGER,
  string_value         TEXT,
  float_value          REAL,
  bool_value           INTEGER,
  list_value           TEXT,         -- JSON-encoded list
  child_key_value      TEXT,         -- cache reference
  custom_scalar_value  TEXT,         -- JSON-encoded
  written_at           INTEGER NOT NULL,
  PRIMARY KEY (cache_key, field_name)
) WITHOUT ROWID;
```

A schema-version marker table records the schema generation:

```sql
CREATE TABLE IF NOT EXISTS schema_metadata (
  key TEXT PRIMARY KEY,
  value TEXT
);
-- on init: INSERT OR REPLACE INTO schema_metadata VALUES ('version', '3');
```

### 7.2 Operations

- `selectRecords(forKeys:)` — single `SELECT … WHERE cache_key IN (?, ?, …) ORDER BY cache_key, field_name`. Reassembles into `Record` instances by grouping by `cache_key` in Swift. Composite-PK clustering ensures rows for one record arrive contiguous in the result set.
- `addOrUpdate(records:)` — shreds each `Record.fields` into N row UPSERTs in one transaction. Each row carries its `written_at`.
- `deleteRecord(for:)` — `DELETE FROM records WHERE cache_key = ?`.
- `deleteRecords(matching:)` — unchanged semantics (`WHERE cache_key LIKE ? COLLATE NOCASE`).
- `clearDatabase` — unchanged.

### 7.3 Migration on first 3.0 launch

On `init`, after `createRecordsTableIfNeeded`:

1. Read `schema_metadata` for the version.
2. If version is missing or `< 3`, drop and recreate the records table; insert the new version.
3. If version is `3`, no migration needed.

The drop-and-rebuild is silent — no user-visible event other than the network fetches that follow on cache-miss reads.

### 7.4 Performance gates

The implementation must hit the following on iPhone 16 Pro hardware (drawn from Zach's benchmark):

| Operation | Target |
|---|---|
| Select by exact cache key | < 0.2 ms |
| Select by object type + selection set, with `ORDER BY` | < 50 ms |
| Update by composite key | < 1 ms |
| Sort by field (CTE join) | < 250 ms |
| Insert one record (single field) | < 1 ms |

These are 25% looser than the benchmark's measured numbers, allowing for production-environment variability while still detecting regression. They are pass/fail gates for SQLite operations only; the broader performance measurement and reporting work — covering in-memory cache I/O, `CachedField` serialization, GraphQL execution, and the alpha-vs-2.x comparison dataset — is specified in [cache-rewrite-phase1-perf.md](./cache-rewrite-phase1-perf.md). The 3.0-alpha tag (Phase 1A exit) is gated on both: SQLite gates green AND no regression verdict in the broader dataset.

## 8. Phased implementation

### Phase 0 — Design lock and de-risking spikes (2 weeks)

Inputs:
- This document, signed off.
- Codegen-frontend reviewer assigned.

Activities:
- Resolve any open questions surfaced during this document's review (see section 12).
- **Spike 1: SQLite schema + benchmark micro-run.** Prototype the new schema (per section 7) on a throwaway branch and run a small benchmark on real iPhone 16 Pro hardware against a few thousand synthetic records. Goal: confirm the section 7.4 performance gates are reproducible on the dev device before Phase 1A starts. ~3 days of effort. Pays off immediately in Phase 1A.
- **Spike 2: `@cacheControl` JS directive transform.** Prototype the JS-side directive transform end-to-end in a throwaway branch — single test schema, no codegen, just confirm the precedence algorithm and interface inheritance work as designed. ~3 days of effort. Goal is to surface any compiler-API surprises *before* Phase 1B begins (note: spike findings will sit in an ADR for ~7 weeks before being consumed; minor staleness risk, mitigated by keeping the spike branch alive for reference).
- Architecture decision records (ADRs) written for each of the 5 locked decisions, plus any newly-resolved Phase 0 items, plus findings from each spike.

Exit criteria:
- ADRs merged.
- Both spikes compile and validate their respective hypotheses on throwaway branches.
- Phase 1 work order approved.

### Phase 1A — SQLite schema rewrite + field-aware `Record` (4 engineer-weeks; 6–7 calendar weeks)

The storage refactor lands as a self-contained, no-feature milestone shippable as 3.0-alpha. Behavior for end users is unchanged from 2.x; the only public-API break is the declared type of `Record.fields`. The `written_at` column is added now and locked into the schema even though TTL evaluation does not yet consult it — adding the column later would force a second drop-and-rebuild migration on upgraders.

Storage:
- Rewrite [ApolloSQLiteDatabase.swift](../Sources/ApolloSQLite/ApolloSQLiteDatabase.swift) per section 7.
- Rewrite [SQLiteSerialization.swift](../Sources/ApolloSQLite/SQLiteSerialization.swift) to encode/decode per typed column instead of the JSON-blob `record` field.
- Rewrite [SQLiteNormalizedCache.swift](../Sources/ApolloSQLite/SQLiteNormalizedCache.swift) to shred `Record` into rows on write and reassemble on read.
- Schema-version detection and drop-and-rebuild migration on init.
- Performance-gate test harness running on iPhone 16 Pro and asserting the section 7.4 numbers; runs in CI from the start of this phase.

Field-aware `Record`:
- New `CachedField` type with `value` and `writtenAt` (section 3.2). `writtenAt` is populated by the result normalizer on every cache write; nothing yet reads it, but it is durable.
- `Record.fields` declared type changes to `[CacheKey: CachedField]`.
- The `record[key]` subscript stays as the public read primitive, returning `Value?` by unwrapping `.value`. The executor in [CacheDataExecutionSource.swift](../Sources/Apollo/Execution/ExecutionSources/CacheDataExecutionSource.swift) needs no change.
- Update the ~10 runtime call sites that construct `Record`s and the ~4 test sites that read `record.fields` directly.

Tests:
- Update [SQLiteCacheTests.swift](../../Tests/ApolloTests/Cache/SQLite/SQLiteCacheTests.swift) and [CachePersistenceTests.swift](../../Tests/ApolloTests/Cache/SQLite/CachePersistenceTests.swift) for the new schema.
- Update the ~4 sites in `Tests/ApolloTests/` that read `record.fields` directly.
- Existing `LoadQueryFromStoreTests.swift`, `ReadWriteFromStoreTests.swift`, `WatchQueryTests.swift`, and `FieldPolicyTests.swift` should require no changes (subscript-only access is preserved); confirm in CI.

Exit criteria:
- All cache tests in `Tests/ApolloTests/Cache/` pass on the new schema and `Record` shape.
- Performance gates met on iPhone 16 Pro within 25% of benchmark targets.
- Old-schema database files (from any 1.x or 2.x release) successfully migrate to the new schema on first launch.
- Generated code from existing test schemas continues to compile and run unchanged (no `@cacheControl` directive support yet; no behavioral change for end users).
- **3.0-alpha tag is releasable from this milestone.** Internal beta cycle on this alpha (concurrent with Phase 1B start) provides early production-like signal on the storage refactor before TTL behavior is layered on.

### Phase 1B — `@cacheControl` codegen end-to-end (4 engineer-weeks; 5–6 calendar weeks)

JS frontend ([apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/](../../apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/)):
- Add `directive_cacheControl` and `directive_cacheControlField` definitions to [apolloCodegenSchemaExtension.ts](../../apollo-ios-codegen/Sources/GraphQLCompiler/JavaScript/src/utilities/apolloCodegenSchemaExtension.ts).
- New `cacheControlDirective.ts` (parallel to `typePolicyDirective.ts`) implementing the precedence algorithm, scalar inheritance, composite `inheritMaxAge`, interface walk, and conflict detection. Build on findings from the Phase 0 Spike 2 ADR.
- Validation rules with clear error messages: `@cacheControl` without `maxAge` arg is rejected here.
- JS unit tests covering all 9 scenarios in `cache-control-samples.md`.

Swift bridge:
- `CompilationResult.Field` and `CompilationResult.Type` gain `cacheControlMaxAge: Int?` (nil for "no directive resolved" or for explicit `maxAge: 0`'s "no scheduling" — the runtime distinguishes; Phase 0 spike to confirm this representation).
- `IR.Field` exposes the resolved `cacheControlMaxAge`.
- [SelectionSetTemplate.swift](../../apollo-ios-codegen/Sources/ApolloCodegenLib/Templates/SelectionSetTemplate.swift) emits `cacheControl: .init(maxAge: N)` on `Selection.Field` for fields with non-nil resolved `maxAge`. Omits the parameter entirely otherwise.

Apollo runtime:
- New `Selection.CacheControlDirective` struct in [Selection.swift](../Sources/ApolloAPI/Selection.swift).
- `Selection.Field` gains `cacheControl: CacheControlDirective?` with a `nil` default and the appropriate convenience initializer overloads.
- The runtime stores the metadata on `Selection.Field` but does not yet enforce TTL — that lands in Phase 1C.

Test code regeneration:
- All 6 [TestCodeGenConfigurations](../../Tests/TestCodeGenConfigurations) regenerated and validated.
- New snapshot tests for each precedence scenario.

Exit criteria:
- All examples in [Samples/cache-control-samples.md](./Samples/cache-control-samples.md) produce the documented resolved values.
- All existing CodegenTests pass against regenerated test APIs.
- New snapshot tests for `@cacheControl` precedence pass.
- Generated code with `cacheControl` metadata is consumed by the existing 1A runtime without behavior change (metadata present, ignored). End-user behavior at the end of this phase remains identical to 3.0-alpha.

### Phase 1C — TTL evaluation and read-mode split (3 engineer-weeks; 4 calendar weeks)

- `TimeProvider` protocol and the system implementation; threaded into `ApolloStore`.
- TTL check inside `CacheDataExecutionSource.resolveField`, gated by the new `ttlEnforcement` parameter (section 4.2).
- `TTLEnforcement` enum and the `ApolloStore.load(_:ttlEnforcement:)` overload.
- `GraphQLResultNormalizer` injects `writtenAt` into each `CachedField` during write.
- `GraphQLDependencyTracker` extension to compute `earliestExpiry`.
- New `GraphQLResponse.earliestExpiry: Date?`.
- New `TTLTests.swift` covering all 9 sample scenarios as integration tests, plus boundary cases: `maxAge=0` reads, scalar inheritance, operation overrides, interface propagation, and the strict-vs-permissive distinction.

Exit criteria:
- New TTL tests pass.
- The `written_at` column populated since Phase 1A is now consulted on reads; round-trip is end-to-end exercised.
- Existing `LoadQueryFromStoreTests.swift`, `ReadWriteFromStoreTests.swift`, `WatchQueryTests.swift`, and `FieldPolicyTests.swift` all pass — most should require no changes; some watcher tests will require updates because the existing "happy accident" revalidation path is no longer possible (the propagating read is now permissive; section 5).

### Phase 1D — Opt-in watcher refresh, hardening, and beta (4 engineer-weeks; 4–5 calendar weeks)

- `GraphQLQueryWatcher` `automaticallyRefreshOnExpiry` flag and the timer-scheduling logic per section 6.2.
- `InMemoryNormalizedCache` parity for TTL — same `CachedField` shape, no schema migration needed.
- Migration guide published in [Documentation.docc](../Sources/Apollo/Documentation.docc) covering the 3.0 upgrade path and the watcher × TTL semantics paragraph from section 6.
- Sample updates in [TestCodeGenConfigurations](../../Tests/TestCodeGenConfigurations) demonstrating `@cacheControl` usage.
- 1-week internal beta with at least one end-to-end real-application test.
- Public 3.0-beta tag.

Exit criteria:
- Zero P0/P1 issues open after the 1-week internal beta.
- Migration guide validated by at least one external user.
- Public 3.0-beta tagged and announced.

## 9. Timeline summary

| Phase | Focus | Engineer-weeks | Calendar weeks |
|---|---|---|---|
| 0 | Design lock + de-risking spikes + 2.x perf baseline capture | 3 | 3 |
| 1A | SQLite schema rewrite + field-aware `Record` + alpha perf dataset (3.0-alpha) | 5 | 7–8 |
| 1B | `@cacheControl` codegen end-to-end | 4 | 5–6 |
| 1C | TTL evaluation + read-mode split | 3 | 4 |
| 1D | Opt-in watcher refresh + hardening + 3.0-beta | 4 | 4–5 |
| **Total** | | **19** | **23–26 (≈ 5.5–6 months)** |
| **With 25% contingency** | | | **29–33 (≈ 6.5–7.5 months)** |

Plan against 6.5–7.5 months calendar. Two release tags ship from the plan: a 3.0-alpha at end of Phase 1A (storage refactor only, no behavioral change, accompanied by the performance comparison dataset per [cache-rewrite-phase1-perf.md](./cache-rewrite-phase1-perf.md)) and 3.0-beta at end of Phase 1D (full TTL feature).

## 10. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Test-rewrite scope under-estimated | High | Medium | Phase 1A (storage / `Record` shape) and Phase 1C (TTL behavior) deliberately budget time for test churn. Track test deltas weekly during those phases; escalate if rewrites exceed 30% of file lines. |
| Codegen-frontend surprise (precedence algorithm edge case, interface conflict logic) | Medium | High | Phase 0 Spike 2 prototypes the directive transform on a throwaway branch; surface surprises before Phase 1B starts. Spike branch kept alive across the ~7 weeks of Phase 1A for reference. |
| SQLite performance regression vs. benchmark | Low | High | Phase 0 Spike 1 validates gates on real iPhone 16 Pro hardware before Phase 1A. Performance-gate test harness runs in CI from start of Phase 1A; regression caught immediately. |
| Storage refactor breaks customer apps on upgrade | Medium | High | Storage refactor lands as 3.0-alpha at end of Phase 1A — independent of TTL behavior. Real-world signal on the riskiest piece arrives before the directive work is committed; rollback or fix scope is bounded to storage layer alone. |
| Watcher × TTL semantics confuse users | Medium | Medium | Clear migration-guide paragraph; flag the strict-vs-permissive distinction; document the opt-in flag prominently. |
| Generated-code/runtime mismatch on 2.x → 3.0 upgrade | Medium | High | Major version bump means clean break; `apollo-ios-cli` rejects 2.x configs against 3.0 runtime via build-time check. |
| Solo-engineer concentration risk | Medium | High | Consistent reviewer across all phases; ADRs document non-obvious decisions; design doc (this) lives next to RFC for handoff. |
| Drop-and-rebuild produces unexpected day-one network load on real customers | Low | Medium | Test on a representative customer profile during Phase 1D internal beta. |

## 11. Out of scope (Phase 2+)

The following are explicitly deferred, in roughly the order they are likely to be tackled:

1. `@onDelete` / `@onDeleteField` directive and cascading record deletion.
2. `NormalizedCacheConfiguration` with size limits.
3. LRU eviction (uses `CachedField.lastAccessedAt`, which Phase 2 adds).
4. `evictionFieldsIgnoreList` and `NormalizedCacheConfigurationDelegate`.
5. `ChainedNormalizedCache` (in-memory + SQLite write-through).
6. Watcher auto-refresh on application foreground / scene activation (an alternative to the timer-based opt-in; complementary, not a replacement).
7. Object-level and field-level watchers (RFC explicit deferral).
8. Faceted searching support (RFC explicit deferral).

Phase 2 is unestimated. A separate planning exercise will scope it after Phase 1 ships.

## 12. Open questions to resolve in Phase 0

1. **Operation-level type directives.** Section 4.1 lists "operation-level parent type" as a precedence layer. Standard GraphQL doesn't allow `@cacheControl` on an inline fragment's type spread directly, but some framings of the precedence rule imply it. Phase 0 to confirm whether the operation-level type layer is meaningfully different from the operation-level field layer or whether to drop it from the algorithm.
2. **Encoding of `cacheControlMaxAge` on `CompilationResult.Field`.** Spike will confirm whether `Int?` is sufficient or whether a richer enum is needed to distinguish "no directive resolved" from "explicit `maxAge: 0`" all the way through the bridge. (Codegen output is the same in both cases, but downstream tooling may want to know.)
3. **Default `Date` representation.** This document specifies epoch seconds (`Int64`) for `writtenAt` to match SQLite-friendly storage. Confirm no consumer expects sub-second precision; if so, switch to milliseconds.
4. **Watcher's behavior when `automaticallyRefreshOnExpiry` is set but no field in the query has a `maxAge`.** Likely: the timer is never scheduled, and the flag has no observable effect. Document this; Phase 0 to confirm we don't want to assert/warn.
5. **Public-API freeze on `Record`.** Section 3.2 changes `Record.fields`. Confirm with the codegen team and any known custom-cache implementors that the migration path (subscript-only access continues to work; `.fields` direct reads must update) is acceptable. If a deprecation period is needed, add a temporary `var fieldsLegacy: [CacheKey: Value]` accessor for one minor cycle on 3.x.
6. **Exact `TTLEnforcement` API placement.** Whether to expose it on `ApolloStore.load` directly, on a new `ReadTransaction` configuration, or via a closure parameter. This is purely an API ergonomics decision.

These are not blockers for starting Phase 0; they are the explicit agenda for the design lock.

## 13. References

- [rfc-caching-rewrite.md](./rfc-caching-rewrite.md) — original RFC.
- [Samples/cache-control-samples.md](./Samples/cache-control-samples.md) — `@cacheControl` resolution scenarios.
- [Samples/on-delete-samples.md](./Samples/on-delete-samples.md) — Phase 2 directive scenarios (not in Phase 1 scope).
- "SQLite Performance Benchmarks" — Confluence ClientDev page 1585152147.
- Apollo cache spec — [specs.apollo.dev/cache/v0.2](https://specs.apollo.dev/cache/v0.2/).
- [cache-rewrite-phase1-summary.md](./cache-rewrite-phase1-summary.md) — manager-facing summary.
