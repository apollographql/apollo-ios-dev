# ADR 0005 — Stale-tolerance API: `RequestConfiguration.ttlEnforcement`, `Source.cache(containsStaleFields:)`, `MissingValueReason`, and `.revalidateCache`

- **Status:** Accepted
- **Date:** 2026-05-07
- **Phase 1 PR:** PR-004b (cache rewrite execution plan §8)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §4.2, §6.4](../cache-rewrite-phase1-plan.md)

## Context

[ADR 0003](./0003-ttl-semantics.md) specifies the TTL runtime semantics: a tri-state `maxAge` (nil/0/N>0), selection-set-scoped enforcement, and a strict-vs-permissive read-mode split on `ApolloStore.load`. This is a complete description of the *cache layer*'s behavior. What is not yet specified is the *consumer-facing API surface* — how application code chooses between strict and permissive reads, how it observes that a cache read returned stale data, and how it expresses common patterns built on that machinery.

Three related concerns drive this ADR:

1. **How does a consumer choose strict vs permissive enforcement?** ADR 0003's `ttlEnforcement` parameter is on `ApolloStore.load`, which is below the public consumer fetch API. A surface higher up needs to expose the choice.
2. **How does a consumer observe that a cache response contained stale data?** Permissive reads return values silently in ADR 0003's first formulation; consumers need a signal in order to act on staleness (e.g., trigger a follow-up network fetch, log telemetry, indicate "refreshing" in the UI).
3. **How is the common stale-while-revalidate (SWR) pattern packaged?** Consumers who want "deliver stale immediately, refresh in the background" should not have to write the branching themselves; the library should provide an ergonomic primitive.

A fourth related question — diagnostic distinction between "field was absent" and "field expired" cache misses in strict mode — is small enough to fold into this ADR as well.

## Decision

Four coordinated additions to the public API:

### 2.1 `RequestConfiguration.ttlEnforcement: TTLEnforcement`

The existing [`RequestConfiguration`](../../Sources/Apollo/RequestConfiguration.swift) value type — already passed to `client.fetch(query:)` and friends — gains a `ttlEnforcement` field that propagates to the cache read mode.

```swift
public struct RequestConfiguration: Sendable {
  // ... existing fields preserved
  public var ttlEnforcement: TTLEnforcement = .strict
}
```

Default is `.strict`, matching the schema author's evident intent when they write `@cacheControl(maxAge: N)`. Consumers who want stale tolerance opt in by setting `.permissive` on the configuration they pass to `fetch`. The value flows through the request chain into `ApolloStore.load(_:ttlEnforcement:)`.

The watcher's `didChangeKeys` re-read uses `.permissive` directly (per [ADR 0004](./0004-watcher-ttl.md) §2.1) and ignores the consumer's `RequestConfiguration` for that internal read. The watcher's *opt-in auto-refresh* timer fires `fetch(cachePolicy: .cacheFirst)`, which uses the consumer's `RequestConfiguration` and therefore respects the `ttlEnforcement` setting on it.

### 2.2 `Source.cache(containsStaleFields:)` associated value

`GraphQLResponse.Source` changes from a flat enum to one with a `Bool` associated value on the `.cache` case:

```swift
public enum Source: Sendable {
  case cache(containsStaleFields: Bool)
  case network
}
```

The flag is set during the cache read pass: `true` if any field returned by the resolver in permissive mode was past its TTL (either `maxAge: 0` or `writtenAt + maxAge < now`); `false` for fresh cache hits. It is structurally inapplicable to network-sourced responses — there is no notion of "stale network response" because network responses establish freshness, not consume it.

Consumers branch on this in pattern matching:

```swift
switch response.source {
case .cache(containsStaleFields: true):  /* stale; consumer may revalidate */
case .cache(containsStaleFields: false): /* fresh cache hit */
case .network:                           /* by definition fresh */
}
```

Under `ttlEnforcement = .permissive`, the signal is what `.revalidateCache` (§2.4) consults internally to decide whether to fire the network fetch.

### 2.3 `JSONDecodingError.MissingValueReason`

The existing `JSONDecodingError.missingValue` case is extended to carry an optional reason for diagnostic distinction between absence and expiry. Both still trigger the same control-flow path (cache miss → network refetch in strict mode), but the reason lets logging, telemetry, and debug surfaces tell them apart.

```swift
public enum JSONDecodingError: Error {
  case missingValue(reason: MissingValueReason?)   // CHANGED — was case missingValue
  // ... existing cases preserved
  
  public enum MissingValueReason: Sendable {
    case absent                                          // field not present in cache record
    case expired(writtenAt: Date, maxAge: Int)           // failed TTL check in strict mode
  }
}
```

The associated value is optional, which preserves catch-site backward compatibility for code that only cares about "missing-or-not": `case .missingValue` continues to match every variant. Consumers wanting the distinction pattern-match on the reason. The change is breaking only in the sense that any code that constructs `.missingValue` directly must update — internal callers do, third-party callers should not have been constructing this case.

### 2.4 `.revalidateCache` cache policy

A new case on the existing `CachePolicy.Query.CacheAndNetwork` enum:

```swift
public enum CachePolicy.Query.CacheAndNetwork: Sendable, Hashable {
  case cacheAndNetwork        // existing — always fetches network in addition to cache
  case revalidateCache        // NEW — fetches network only if cache contains stale fields
}
```

`.revalidateCache` packages the SWR pattern. Its behavior depends on the consumer's `RequestConfiguration.ttlEnforcement` — the two configuration axes compose orthogonally rather than `.revalidateCache` overriding the enforcement mode.

**Under `ttlEnforcement = .permissive`** (the SWR-meaningful combination):

| Cache state | Stream yields |
|---|---|
| Fresh cache hit (all selected fields present, none stale) | One response: `source = .cache(containsStaleFields: false)`. No network call. |
| Stale cache hit (all selected fields present, any stale) | Two responses: stale `source = .cache(containsStaleFields: true)` first, then fresh `source = .network` after refresh. |
| Genuine miss (any selected field absent) | One response: from network. |

**Under `ttlEnforcement = .strict`** (the redundant intersection — see §3.2):

| Cache state | Stream yields |
|---|---|
| Fresh cache hit | One response: from cache. No network call. |
| Stale "hit" (any field expired) | Strict mode turns this into a `missingValue(.expired)` miss per [ADR 0003](./0003-ttl-semantics.md). One response: from network. |
| Genuine miss | One response: from network. |

Internally, `.revalidateCache` reads the cache using the consumer's `ttlEnforcement` setting. Under permissive, it consults the `Source.cache(containsStaleFields:)` flag to decide whether to fire the network fetch — the consumer doesn't need to write the branch themselves. Under strict, stale fields fail the read like any other miss and the policy falls back to network exactly as `.cacheFirst + .strict` would; there is nothing to revalidate when stale data is unobservable. The redundancy is mechanical (same code path), not merely behavioral; see §3.2.

Consumers who want SWR semantics must explicitly opt into stale tolerance via `ttlEnforcement: .permissive`. This is intentional: the schema author's `@cacheControl(maxAge:)` directive is honored by default, and stale tolerance is a separate axis from cache-policy choice. A consumer dynamically wiring `ttlEnforcement` (for example, a wrapper that honors a user preference for strict freshness across all queries) gets consistent behavior across cache policies — `.cacheFirst` and `.revalidateCache` both respect the setting.

## Alternatives considered

### A. Separate `CachePolicy.Query.StaleWhileRevalidate` group

Introduce a third enum group alongside `CacheAndNetwork` to hold an `.staleWhileRevalidate` case, mirroring the structure of `CacheOnly` and `CacheAndNetwork`.

- *Rejected because:* the response shape (multi-response stream that may contain a cached value followed by a network value) is the same as `.cacheAndNetwork`'s. Putting `.revalidateCache` in `CacheAndNetwork` keeps single-response and multi-response policies cleanly separated. Adding a new top-level group for one case would split a concept that belongs together.

### B. Top-level `cacheContainsStaleFields: Bool` on `GraphQLResponse`

Keep `Source` as a flat enum (`.cache | .network`) and put the staleness signal at the top level of `GraphQLResponse`.

- *Rejected because:* the signal is meaningful only for cache-sourced responses; on network-sourced responses, "containsStaleFields" is nonsensical. Encoding the signal at the top level admits the impossible state `Source = .network, cacheContainsStaleFields = true`. Encoding it as an associated value on `.cache` makes the impossible state unrepresentable in the type system. Pattern-matching consumers also benefit: `case .cache(containsStaleFields: true)` reads naturally; the alternative requires two-step matching (`if response.source == .cache && response.cacheContainsStaleFields`).

### C. Three TTL enforcement modes (`.strict`, `.staleAware`, `.permissive`)

Introduce a third mode where stale fields are returned and marked, distinct from a "permissive without marking" mode that returns silently.

- *Rejected because:* the marking is essentially free (one Bool on the response), and there is no use case in Phase 1 for "return stale silently with no observable signal." Permissive mode always marks; consumers who don't care about the flag ignore it; consumers who do care branch on it. Two modes is simpler and the lost distinction has no practical cost.

### D. `permitStaleCacheReads: Bool` on `RequestConfiguration` instead of the enum

Use a Bool flag rather than the `TTLEnforcement` enum on `RequestConfiguration`.

- *Rejected because:* the enum already exists at the `ApolloStore.load` layer ([ADR 0003](./0003-ttl-semantics.md) §2.3). Using the same type at the consumer-facing layer eliminates a translation step and keeps the design extensible — a future third mode would land naturally on the enum without breaking the API. A Bool would force a type change to add a third mode later.

### E. Separate `staleDataError` thrown from the cache resolver

Introduce a distinct error type (e.g., `StaleDataError`) thrown by `CacheDataExecutionSource.resolveField` on TTL expiry, distinct from `JSONDecodingError.missingValue`.

- *Rejected because:* errors short-circuit the executor. If the resolver threw a stale-data error on field A, the executor would stop walking the selection set; fields B, C, D would never resolve. There would be no completed result to deliver in the stale-while-revalidate pattern. The chosen design — keep `missingValue` as the cache-miss signal in strict mode, and use response metadata (`Source.cache(containsStaleFields:)`) to surface staleness in permissive mode — does not have this problem. The `MissingValueReason` enum (§2.3) preserves the diagnostic distinction without changing control flow.

### F. `.revalidateCache` ignores `ttlEnforcement` (no redundant intersection)

Make `.revalidateCache` always read permissively, regardless of the consumer's `RequestConfiguration.ttlEnforcement` setting. The combination `.revalidateCache + .strict` would be silently treated as `.revalidateCache + .permissive`.

- *Rejected because:* this breaks the orthogonality of the two configuration axes. Consumer code that passes a `RequestConfiguration` with `ttlEnforcement` set dynamically — for example, a wrapper that honors a user preference for strict freshness across all queries — would behave inconsistently: `.cacheFirst` would respect the setting, but `.revalidateCache` would not. The redundancy of `.revalidateCache + .strict ≡ .cacheFirst + .strict` is a smaller cost than the inconsistency this option would introduce. Consumers who pick `.revalidateCache` and want strict TTL behavior get the documented equivalent (cacheFirst-with-network-fallback-on-miss) — no behavior is silently lost.

### G. No built-in SWR — consumers DIY using `Source.cache(containsStaleFields:)`

Drop `.revalidateCache` and have consumers implement the SWR pattern themselves: read permissively, branch on the staleness signal, fire follow-up network fetches when stale.

- *Rejected because:* the SWR pattern is common enough to deserve a built-in primitive. Forcing every consumer who wants it to write the same branching boilerplate is a quality-of-life cost. The DIY pattern is still available for variations (e.g., revalidating only specific fields, or rate-limiting the follow-up fetches), but the common case gets one-line ergonomics.

## Consequences

### Positive

- **Composable axes.** `RequestConfiguration.ttlEnforcement` and `cachePolicy` compose freely: any of the existing cache policies plus either enforcement mode produces a sensible behavior. Offline-first apps use `.cacheOnly + ttlEnforcement = .permissive`; freshness-strict apps use `.cacheFirst + ttlEnforcement = .strict` (default); SWR apps use `.revalidateCache`. No combinatorial explosion of named cache policies.
- **Type-safe staleness signal.** `Source.cache(containsStaleFields:)` makes "network response with staleness flag" unrepresentable in the type system. Pattern matching is natural.
- **Diagnostic distinction without control-flow cost.** `MissingValueReason` lets logs and telemetry distinguish absent from expired cache misses without changing how callers handle the error. Existing `case .missingValue` catch sites continue to compile and behave as before.
- **`.revalidateCache` ergonomics.** The SWR pattern is one cache-policy choice plus `ttlEnforcement: .permissive`; consumers don't write the cache-read-then-conditionally-fetch-network branching themselves.
- **Default behavior preserves existing intent.** `RequestConfiguration.ttlEnforcement = .strict` by default means a schema author writing `@cacheControl(maxAge: N)` sees their directive honored automatically; consumers who want stale tolerance opt in.

### Negative

- **`.revalidateCache + ttlEnforcement = .strict` is mechanically redundant with `.cacheFirst + ttlEnforcement = .strict`.** Both configurations execute the same read path: strict TTL turns stale fields into `missingValue(.expired)` cache misses, which trigger network fallback. A consumer writing `.revalidateCache, ttlEnforcement: .strict` gets exactly the behavior of `.cacheFirst, ttlEnforcement: .strict` — there is nothing to revalidate when stale data is unobservable. Mitigation: the redundancy is documented in the API surface comments and in the migration guide. A category-error combination is an acceptable cost of preserving the orthogonal axes; consumers who write configurable code (where `ttlEnforcement` and `cachePolicy` come from different sources) get predictable behavior in every combination.
- **Existing pattern matches on `Source` need updating.** Code that pattern-matches `case .cache:` without the associated value will fail to compile in 3.0 (`.cache` no longer exists as a case without an associated value). Mitigation: this is a 3.0 breaking change called out in the migration guide; the typical fix is `case .cache(_):` or `case .cache(containsStaleFields: _):`. Trivial mechanical update.
- **`JSONDecodingError.missingValue` constructor signature changes.** Code that constructs `JSONDecodingError.missingValue` directly must now write `.missingValue(reason: nil)`. Internal call sites are the only known constructors; third-party code that catches the case is unaffected. Mitigation: 3.0 breaking change called out in the migration guide.
- **Three new public API surfaces in 3.0.** `RequestConfiguration.ttlEnforcement`, `Source.cache(containsStaleFields:)`, `MissingValueReason`, and `.revalidateCache` are all new public API. Each adds a small amount of conceptual surface area for new users. Mitigation: documentation comments on each; migration guide section explaining when to use which; the default behavior matches the most common intent so the new API surface is opt-in for the common case.

### Neutral

- **The redundancy in §3.2 is intentional and bounded.** Other combinations — `.cacheOnly + .permissive`, `.networkFirst + .permissive`, `.cacheFirst + .permissive`, `.cacheAndNetwork + .permissive`, etc. — are all distinct, useful, and orthogonal. Only the one corner is redundant, and it's the corner where the user has explicitly asked for two contradictory things at once (revalidate stale data, but treat stale as miss).
- **`.revalidateCache` does not separately expose the network response and the cache response in the result type.** Both responses are delivered through the same `AsyncSequence<GraphQLResponse<Query>>` API; consumers distinguish them via `response.source`. This is identical to `.cacheAndNetwork`'s existing shape.

## References

- [ADR 0003 — TTL semantics](./0003-ttl-semantics.md) §2.3, §2.4 — the read-mode split this ADR exposes to consumers
- [ADR 0004 — Watcher × TTL](./0004-watcher-ttl.md) §2.1 — confirms the watcher's `didChangeKeys` re-read uses `.permissive` internally regardless of consumer `RequestConfiguration`
- [Engineering plan §4.2](../cache-rewrite-phase1-plan.md) — read-path enforcement pseudocode (uses the `MissingValueReason` introduced here and the `markCacheContainsStaleFields()` mechanism for staleness tracking)
- [Engineering plan §6.4](../cache-rewrite-phase1-plan.md) — `GraphQLResponse` additions (the `Source` enum shape change is documented there)
- [Execution plan §8 PR-022a](../cache-rewrite-phase1-execution.md) — implementation PR for this ADR
- [CachePolicy.swift](../../Sources/Apollo/Caching/CachePolicy.swift) — current 2.x cache policy structure that gains `.revalidateCache`
- [RequestConfiguration.swift](../../Sources/Apollo/RequestConfiguration.swift) — current 2.x request configuration value type that gains `ttlEnforcement`
