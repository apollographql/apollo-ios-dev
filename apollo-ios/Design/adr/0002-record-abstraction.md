# ADR 0002 — Record abstraction: field-aware via `CachedField`

- **Status:** Accepted
- **Date:** 2026-05-07
- **Phase 1 PR:** PR-002 (cache rewrite execution plan §8)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §3.2](../cache-rewrite-phase1-plan.md)

## Context

The Phase 1 cache rewrite introduces per-field metadata that did not exist in 2.x:

- **`writtenAt` (epoch seconds).** Required for TTL evaluation. The cache miss path under `@cacheControl(maxAge:)` consults `writtenAt + maxAge < now`; this requires that every cached field carry its individual write timestamp.
- **Other metadata in the foreseeable Phase 2 future.** Phase 2 adds LRU eviction (needs `lastAccessedAt` per field), `@onDelete` cascading (needs to know which fields are reference-typed and what they point at), and faceted searching (wants typed value columns at the storage layer reflected in the in-memory shape).

The current 2.x `Record` is a thin wrapper around a key plus an untyped field dictionary:

```swift
public struct Record: Sendable, Hashable {
  public let key: CacheKey
  public typealias Value = any Hashable & Sendable
  public typealias Fields = [CacheKey: Value]
  public private(set) var fields: Fields

  public subscript(key: CacheKey) -> Value? {
    get { fields[key] }
    set { fields[key] = newValue }
  }
}
```

There is no place on a `Record` for per-field metadata. The TTL feature, the SQLite layer (row-per-field with per-row `written_at`), and the executor that reads cached values all need to agree on where this metadata lives. This ADR captures that decision.

The decision is independent of, and prior to, the SQLite schema decision (engineering plan §7) — the in-memory model must support per-field metadata regardless of how it is persisted on disk. However, the choice does have implications for round-trip cost between the in-memory model and the SQLite layer, and those implications are part of the comparison below.

## Decision

`Record.fields` changes type from `[CacheKey: Value]` to `[CacheKey: CachedField]`. A new `CachedField` value type carries the field's value alongside its `writtenAt` epoch timestamp. The existing `record[key]` subscript is preserved with backward-compatible semantics — it returns `Value?` by unwrapping `.value` from the underlying `CachedField`. A new `cachedField(for:)` accessor is added for callers that need the metadata.

```swift
public struct CachedField: Sendable, Hashable {
  public let value: Value          // any Hashable & Sendable
  public let writtenAt: Int64      // epoch seconds
  // Future Phase 2: lastAccessedAt for LRU; parent refs for @onDelete; etc.
}

public struct Record: Sendable, Hashable {
  public let key: CacheKey
  public typealias Value = any Hashable & Sendable
  public typealias Fields = [CacheKey: CachedField]
  public private(set) var fields: Fields

  // Backward-compatible read of the value alone.
  public subscript(key: CacheKey) -> Value? { fields[key]?.value }

  // New API for metadata-aware access.
  public func cachedField(for key: CacheKey) -> CachedField? { fields[key] }
}
```

## Alternatives considered

### A. Keep `Record` value-only; store TTL state in a parallel side-channel

Leave `Record.fields` as `[CacheKey: Value]`. Maintain a separate `[CacheKey: [CacheKey: Int64]]` (or similar) on the cache itself, mapping `(recordKey, fieldName) → writtenAt`. The executor consults this side dictionary at TTL check time.

- *Rejected because:* Two parallel data structures must be kept in sync at every cache write. Every code path that constructs or merges a `Record` must also remember to update the timestamp dict. Forgetting to update the dict in even one path is a silent bug — TTL evaluation just returns wrong answers for fields written through that path. Additionally, the side-channel approach does not extend cleanly to Phase 2 metadata: each new piece of per-field state (`lastAccessedAt` for LRU, parent refs for `@onDelete`) becomes another parallel structure with the same drift risk. Over the lifetime of the cache subsystem this approach accumulates bug surface much faster than Option B.

### B. `Record.fields` carries `CachedField` (chosen)

The selected option, described above. Each field's metadata travels with its value as a single struct.

- *Selected because:*
  1. **Single source of truth per field.** The value and its metadata are inseparable. Every code path that touches a field gets — and writes — both at once. There is no "did I remember to update the parallel dict?" failure mode.
  2. **One-to-one with the SQLite row layout.** The new schema (engineering plan §7) is row-per-field with per-row `written_at`. Decoding a row produces a `CachedField` directly; encoding a `CachedField` produces a row. No reshape is required at the storage boundary.
  3. **Backward-compatible at the most-used surface.** The `record[key]` subscript returns `Value?` exactly as it does in 2.x. The executor in [CacheDataExecutionSource.swift](../../Sources/Apollo/Execution/ExecutionSources/CacheDataExecutionSource.swift) — which uses only the subscript — needs no changes. The breaking surface is restricted to direct iteration of `record.fields`.
  4. **Phase 2 feature growth has a home.** `lastAccessedAt`, `parentReferences`, typed-value optimizations, etc., become fields on `CachedField`. Each is added once; the rest of the system inherits the new metadata transparently.

### C. Lazy field loading via cache-handle proxy

`Record` becomes an opaque handle holding a back-reference to the underlying cache. Field reads go through the handle, which resolves to the cache row on demand. Each field's metadata is consulted at the storage layer at read time.

- *Rejected because:* This is a substantially more invasive change to the executor's contract. The current execution model assumes a `Record` is a fully-materialized snapshot; introducing lazy-loading semantics breaks that invariant in ways that would force changes throughout `CacheDataExecutionSource`, `GraphQLExecutor`, the result accumulators, and likely the transaction model in `ApolloStore.ReadTransaction`. The performance argument is also weak: the new SQLite schema's exact-key lookup is 0.08 ms for the entire record (per Zach's benchmark), so eager materialization is not a measurable cost. Lazy loading might be reconsidered in Phase 2+ as a memory-pressure optimization for very large records, but is not warranted for Phase 1.

## Consequences

### Positive

- **Executor unchanged.** The `record[key]` subscript continues to return `Value?`, so [CacheDataExecutionSource.swift](../../Sources/Apollo/Execution/ExecutionSources/CacheDataExecutionSource.swift) and the rest of the cache read path require no modification beyond the new TTL check itself (added in Phase 1C).
- **Storage layer round-trips are type-direct.** SQLite rows decode to `CachedField` values; encoding the reverse direction. No intermediate reshape, no adapter layer.
- **Phase 2 metadata has a clean home.** Each new piece of per-field state is added to `CachedField` exactly once. LRU eviction, cascading deletes, and faceted-search typed columns each pay only their own implementation cost — not an additional integration cost in twenty call sites.
- **Failure mode for adding metadata is loud, not silent.** A new `CachedField` field is either set everywhere (compiler-enforced when made non-optional) or visibly nil at sites that need to update. The side-channel alternative's silent-drop failure mode is eliminated.

### Negative

- **`Record.fields` declared type changes.** Code that iterates `record.fields` directly — to build a list of all field names, to inspect every value, etc. — must update from `[CacheKey: Value]` to `[CacheKey: CachedField]`. This is a public-API break for custom `NormalizedCache` implementations and for any user code that introspects records.
- **Bounded internal call-site update.** Approximately 10 sites in the runtime construct or read `Record.fields` directly (the result normalizer, the SQLite serialization layer, the in-memory cache, a few tests). Approximately 4 sites in the test suite read `record.fields` directly. All update mechanically; the change is not subtle.
- **Migration note required for custom-cache implementors.** Authors of custom `NormalizedCache` implementations (the public protocol contract) must update any direct-`fields` access. The migration guide will include a one-paragraph note. If a non-trivial population of custom-cache users surfaces during the 3.0-beta cycle, a one-cycle deprecation accessor (`var fieldsLegacy: [CacheKey: Value] { fields.mapValues(\.value) }`) is offered as a fallback per engineering plan §12 open question 5.
- **`CachedField` adds one indirection level.** A read of `record.fields["foo"]` produces a `CachedField?` rather than `Value?`. Code that wants the value still has to write `.value` on the result. This is a minor ergonomic cost and is mitigated by the subscript shortcut for the common case.

### Neutral

- **Equality and hashing semantics.** `Record`'s `Hashable` and `Equatable` conformances now hash and compare `CachedField` rather than `Value`. Two records with the same key and same field values but different `writtenAt` timestamps will compare as unequal. This is the correct semantics for cache invalidation purposes (a re-write at a later time produces a "different" record from the perspective of write-detection logic), but it is a change from 2.x and will be documented in the migration guide.

## References

- [Engineering plan §3.2](../cache-rewrite-phase1-plan.md) — *Record becomes field-aware*
- [Engineering plan §7](../cache-rewrite-phase1-plan.md) — SQLite schema (the row-per-field layout that this in-memory model mirrors)
- [Engineering plan §12 open question 5](../cache-rewrite-phase1-plan.md) — *Public-API freeze on Record* (the contingent `fieldsLegacy` accessor)
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — context for why a public-API break in `Record.fields` is acceptable in 3.0
- [Record.swift](../../Sources/Apollo/Caching/Record.swift) — current 2.x implementation
- [CacheDataExecutionSource.swift](../../Sources/Apollo/Execution/ExecutionSources/CacheDataExecutionSource.swift) — primary executor consumer of the subscript (unchanged by this ADR)
