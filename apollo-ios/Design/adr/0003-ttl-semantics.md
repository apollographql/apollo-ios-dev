# ADR 0003 — TTL semantics: tri-state `maxAge`, selection-set scope, read-mode split

- **Status:** Accepted
- **Date:** 2026-05-07
- **Phase 1 PR:** PR-003 (cache rewrite execution plan §8)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §3.4, §3.5, §4, §5](../cache-rewrite-phase1-plan.md)

## Context

Phase 1 introduces per-field Time-to-Live via the new `@cacheControl(maxAge:)` directive (engineering plan §3.5; sample resolution rules in [Samples/cache-control-samples.md](../Samples/cache-control-samples.md)). The directive itself defines what schema authors and operation authors can write; the runtime semantics — what those values *do* when the cache is read — are a separate set of decisions, captured in this ADR.

Three sub-decisions are bundled together because they are interlocking: each one would be incoherent in isolation. They are presented in §1.1, §1.2, and §1.3 below.

The Apollo cache spec ([specs.apollo.dev/cache/v0.2](https://specs.apollo.dev/cache/v0.2/)) is silent on the meaning of `maxAge: 0` and on what happens when no `@cacheControl` directive is present. Apollo iOS therefore defines its own runtime semantics for these cases. The Apollo Server documentation referenced by the spec was inaccessible in the relevant section at the time of writing, so the spec's silence is taken at face value.

### 1.1 What does `maxAge` mean?

Three plausible meanings for `maxAge` need disambiguation:

- **No directive applied to the field at all.** Could mean "do not cache" or "cache forever".
- **`@cacheControl(maxAge: 0)`.** Could mean "always force a refetch" or "no TTL applied" (same as no directive).
- **`@cacheControl(maxAge: N)` for `N > 0`.** Means "valid for N seconds after `writtenAt`". This is unambiguous in the spec.

A fourth case — `@cacheControl` with no `maxAge` argument — is technically legal syntactically but semantically ambiguous and must be resolved.

### 1.2 What is the *scope* of an expiry check?

When a query is executed against the cache, fields it selects may have different TTL states. Four possible interpretations:

- **Whole-record:** if any field anywhere on the record has expired, the record is considered expired and any query reading it misses.
- **Selection-set:** if any field that the *current query selects* has expired, the query misses; fields not in the selection are ignored.
- **Per-field:** the executor returns a partial result, mixing fresh values with stale values per field.
- **Per-field with revalidation hint:** like per-field, but expired fields are flagged so the caller can choose to refetch.

### 1.3 When should TTL be enforced?

The cache is read from multiple call sites with different intents:

- **Explicit fetches** (`client.fetch(query:)`, `watcher.fetch(...)`, etc.). The consumer asked for data; they have an opinion about freshness.
- **Watcher re-reads on `didChangeKeys`.** A watcher reacts to a cache write that touches one of its dependent keys. The consumer didn't ask for anything; the watcher is propagating cumulative cache state to its delivered result.
- **Cache mutation transactions** (`store.withinReadWriteTransaction`). User code is reading data to mutate it.

Whether TTL is enforced should depend on the intent of the read.

## Decision

### 2.1 Tri-state `maxAge` semantics

| Schema input | Codegen output | Runtime behavior |
|---|---|---|
| (no `@cacheControl` directive applied to the field's resolution chain) | `cacheControl:` parameter omitted on `Selection.Field` | No TTL check; cache indefinitely |
| `@cacheControl(maxAge: 0)` | `cacheControl: .init(maxAge: 0)` | Always treated as cache miss on **consumer-initiated** reads (per-field force-refetch) |
| `@cacheControl(maxAge: N)` where `N > 0` | `cacheControl: .init(maxAge: N)` | Check `writtenAt + N < now` at read time |
| `@cacheControl` with no `maxAge` argument | **Codegen error**: *"@cacheControl requires an explicit maxAge argument"* | — |

The `cacheControl` parameter on `Selection.Field` is `CacheControlDirective? = nil`. Generated code for fields with no resolved directive omits the parameter entirely (smaller files, common case is cheaper at the source level).

The `inheritMaxAge: true` argument on the directive is a codegen-time concern (it adjusts the precedence resolution algorithm). After resolution, the field's `maxAge` is one of the three runtime cases above.

### 2.2 Selection-set-scoped TTL

When a query is executed against the cache:

- TTL is checked **only** for fields the query's selection set requires.
- If any selected field has `cacheControl?.maxAge` and is currently expired (`writtenAt + maxAge < now`, or `maxAge == 0` under strict enforcement — see §2.3), the query is treated as a cache miss as a whole and the existing miss path triggers a network refetch.
- Fields that exist on the same `Record` but are not in the current query's selection are not evaluated. Their staleness is irrelevant to this read.

Implementation: the TTL check lives in `CacheDataExecutionSource.resolveField`. When the check fails, the resolver throws `JSONDecodingError.missingValue`. The existing missing-value propagation in `GraphQLExecutor` and `ApolloStore.load` turns this into a cache miss naturally — no new error type, no new control flow.

### 2.3 Read-mode split (strict vs permissive)

Two read modes exist on `ApolloStore.load`:

| Mode | TTL behavior | Used by |
|---|---|---|
| `.strict` (default) | TTL enforced; expired fields throw `missingValue` with reason `.expired` (see §2.4); query becomes a cache miss | `client.fetch(query:)`, `watcher.fetch(...)` (any explicit fetch by the consumer with `RequestConfiguration.ttlEnforcement = .strict`), watcher auto-refresh timer firing (Phase 1D) |
| `.permissive` | Expired fields are returned as values; the response's `source` is set to `.cache(containsStaleFields: true)` to mark the staleness for callers that branch on it. **Genuine missing-value errors still throw** (see §2.4) | Watcher re-read on `didChangeKeys`; consumer fetches with `RequestConfiguration.ttlEnforcement = .permissive`; the `.revalidateCache` cache policy as part of its SWR semantics |

API:

```swift
public enum TTLEnforcement: Sendable { case strict, permissive }

public func load<Operation: GraphQLOperation>(
  _ operation: Operation,
  ttlEnforcement: TTLEnforcement = .strict
) async throws -> GraphQLResponse<Operation>?
```

Configuration of the read mode at the consumer-facing layer is via [ADR 0005](./0005-stale-tolerance.md): `RequestConfiguration.ttlEnforcement: TTLEnforcement = .strict` for explicit fetches, plus the `.revalidateCache` cache policy which always reads permissively as part of its SWR contract. The watcher's `didChangeKeys` re-read uses `.permissive` directly (per [ADR 0004](./0004-watcher-ttl.md)) and ignores the consumer's `RequestConfiguration` for that internal read.

### 2.4 What permissive mode does and does not bypass

The permissive mode bypasses **only** TTL-induced misses. Genuine missing fields still throw, and the resolver tracks staleness on the execution context so that the assembled response's `source` can be set to `.cache(containsStaleFields: true)` when permissive mode returns any expired values. The pseudocode in `CacheDataExecutionSource.resolveField` makes this explicit:

```swift
// Genuine missing field — throws unconditionally, regardless of mode:
guard let cachedField = record.cachedField(for: cacheKeyForField) else {
  throw JSONDecodingError.missingValue(reason: .absent)
}

// TTL checks — only these are gated by enforcement mode:
if let maxAge = field.cacheControl?.maxAge {
  let isExpired = (maxAge == 0) || (cachedField.writtenAt + Int64(maxAge) < now)
  if isExpired {
    if ttlEnforcement == .strict {
      throw JSONDecodingError.missingValue(
        reason: .expired(writtenAt: Date(timeIntervalSince1970: TimeInterval(cachedField.writtenAt)),
                         maxAge: maxAge)
      )
    }
    // Permissive: continue with the value, but mark that the response
    // was sourced from cache containing stale fields. The flag is read
    // by the result accumulator and set on response.source.
    executionContext.markCacheContainsStaleFields()
  }
}

return cachedField.value
```

Two related pieces of public API are introduced alongside this: a richer `JSONDecodingError.missingValue(reason:)` distinguishing absent from expired (for diagnostics), and `Source.cache(containsStaleFields:)` as the staleness signal on the response. Both are designed and rationalized in [ADR 0005](./0005-stale-tolerance.md).

Genuine missing-value errors still propagate under permissive, which means the existing watcher revalidation-on-actual-cache-miss behavior from 2.x is fully preserved (see [ADR 0001](./0001-major-version-bump.md) §Context item 4 for context).

## Alternatives considered

### A. `maxAge: 0` collapses to "no TTL" (same as no directive)

Treat `@cacheControl(maxAge: 0)` and the absence of a directive identically — both mean "cache indefinitely, no TTL check."

- *Rejected because:* This conflates two distinct authorial intents. A schema author writing `@cacheControl(maxAge: 0)` is making an explicit choice — they want this field to be volatile. Collapsing it with "no directive applied" loses that signal. Furthermore, the directive's purpose is to *configure* cache behavior; if `maxAge: 0` had no effect, writing it would be useless. The chosen tri-state semantics give `maxAge: 0` a real and useful meaning (per-field force-refetch on consumer-initiated reads), distinguishable from both "no TTL" and "expire after some non-zero time."

### B. `maxAge: 0` collapses to "always uncacheable" (HTTP `Cache-Control: max-age=0` analogy)

Treat `@cacheControl(maxAge: 0)` as "this field is never cacheable" — every read goes to the network, the cache is bypassed entirely.

- *Rejected because:* The HTTP `Cache-Control: max-age=0` analogy is a wire-protocol cache-busting signal between client and server, with no relationship to client-side normalized cache semantics. Borrowing the reading would be a footgun. More importantly, "always uncacheable" is already expressible at a different layer — the `cachePolicy: .networkOnly` per-query setting. Per-field cache-bypass adds no new capability over per-query cache-bypass for that intent. The chosen meaning ("force refetch on consumer-initiated reads, but the cache *is* updated when results return") is the more useful semantic and is genuinely new — it lets schema authors mark volatile fields once and have all consuming queries respect that volatility automatically.

### C. Whole-record TTL scope

Check TTL across all fields of a record on every read; if any field anywhere on the record has expired, every query touching the record misses.

- *Rejected because:* Different queries select different subsets of an object's fields. A high-precision query that needs only the always-fresh fields would be forced into network refetches because some unrelated stale field happens to live on the same record. A casual query that needs only fields that change rarely would be similarly burdened. Whole-record scope is too coarse and produces unnecessary network traffic. The selection-set scope respects the principle that the cache should serve queries based on what each query actually needs.

### D. Per-field TTL with mixed-freshness results

Allow the executor to return a partial result mixing fresh and stale field values, with the staleness exposed to the caller as metadata.

- *Rejected because:* GraphQL's response model doesn't admit "partially valid" data — a response is either valid against the schema or it isn't. Surfacing per-field staleness to consumers would require an entirely new result shape (every field accessor would need to indicate freshness), changing the public API of every generated `SelectionSet`. The complexity is enormous for a feature whose primary value (timely refresh of stale data) is better served by simply triggering a refetch when any selected field is stale.

### E. Single read mode (always strict)

Have only one read mode: TTL is always enforced. Every read, regardless of caller, applies the TTL check. The watcher's `didChangeKeys` re-read uses the same path.

- *Rejected because:* This produces surprise behavior. A watcher whose query happens to share dependent keys with an unrelated mutation would refetch from the network every time that mutation fires — even though nothing about the watcher's data has changed and the consumer didn't ask for fresh data. The mutation triggers a `didChangeKeys` event, the watcher does a re-read to pick up the change, the re-read encounters an unrelated field with an expired TTL, the read fails, and a network fetch is triggered. The consumer sees a network roundtrip they didn't request. This is the exact kind of unpredictable, expensive behavior that good cache design avoids.

### F. Single read mode (always permissive)

Have only one read mode: TTL is never enforced at the cache layer. The TTL check moves to a higher layer (e.g., a wrapper around `client.fetch` that consults `earliestExpiry` after the result returns and re-fetches if expired).

- *Rejected because:* This duplicates work and produces wrong behavior in subtle cases. The cache executor walks every field in the selection set during a read; checking TTL during that pass is essentially free. Pushing the check to a higher layer means the executor returns a complete result and the wrapper then walks the response a second time to check expiries, then potentially throws the entire result away to refetch. Worse, the higher-layer check cannot easily distinguish "this field was selected and expired" from "this field was unselected and irrelevant" without re-walking the operation's selection-set tree. The cleaner abstraction places the TTL check at the same layer that knows the selection set: the executor.

## Consequences

### Positive

- **Tri-state semantics give schema authors a real volatility signal.** `@cacheControl(maxAge: 0)` lets a single schema declaration mark a field as always-volatile and have every consuming query inherit the freshness requirement automatically. This is cheaper for authors than per-query `.networkOnly` and more granular than per-record approaches.
- **Selection-set scope respects what queries actually need.** The same record can serve a high-precision query (which would trigger refetch on staleness of its selected fields) and a casual query (which is happy with the stale fields it doesn't read) without conflict.
- **Read-mode split keeps watcher behavior predictable.** Cache writes from unrelated mutations do not cause watchers to surprise-fetch from the network. Watchers serve cumulative cache state; consumer-initiated fetches respect TTL; the two concerns are cleanly separated.
- **Genuine missing-value behavior is preserved.** Permissive mode bypasses TTL-induced misses but not actual missing-data misses. Watchers' existing 2.x revalidation-on-missing behavior carries forward unchanged for consumers that have not adopted the new directive (cf. [ADR 0001](./0001-major-version-bump.md)).
- **Codegen for fields without TTL stays minimal.** Generated `Selection.Field` declarations omit the `cacheControl:` parameter entirely when there's no resolved directive. The common-case generated code is no larger than 2.x's.

### Negative

- **Two read modes adds API surface.** `ApolloStore.load(_:ttlEnforcement:)` is one new parameter. Custom `CacheInterceptor` implementors who delegate to `store.load` may need to think about which mode to pass. Mitigation: the default is `.strict`, which is what most callers want; permissive is internal to the watcher path.
- **`maxAge: 0` semantics differ from the HTTP `Cache-Control: max-age=0` reading.** Some users coming from HTTP backgrounds may expect "uncacheable." Mitigation: the migration guide includes a paragraph clarifying the difference and pointing at `.networkOnly` for per-query cache-bypass.
- **Bare `@cacheControl` is a codegen error.** A schema author who writes `@cacheControl` thinking they've opted into "some default" will get a compile error rather than silent behavior. This is a deliberate footgun-removal but may surprise authors writing the directive for the first time.
- **Selection-set scope means a single stale field forces a whole-query refetch.** A query selecting 50 fields where one has `@cacheControl(maxAge: 60)` will refetch all 50 from the network when the one expires. Mitigation: GraphQL fetches whole selection sets by design; partial refetch isn't a feature anywhere in the system.

### Neutral

- **`maxAge: 0` does not refresh on watcher `didChangeKeys`.** Per §2.3 and the watcher × TTL design (covered separately in ADR 0004), the watcher's propagating-read path uses permissive mode regardless of the watcher's opt-in flag. A watcher's query that includes a `maxAge: 0` field will not refetch on every unrelated cache write that touches its dependent keys. The `maxAge: 0` field refreshes only on consumer-initiated fetches. This is the right behavior — `maxAge: 0` means "force refresh when *consumer* asks for fresh data" — but it is worth pinning down because it is not the most obvious reading.

## References

- [Engineering plan §3.4](../cache-rewrite-phase1-plan.md) — *Selection-set-scoped per-field TTL*
- [Engineering plan §3.5](../cache-rewrite-phase1-plan.md) — *Tri-state maxAge semantics*
- [Engineering plan §4](../cache-rewrite-phase1-plan.md) — *TTL semantics specification* (resolution algorithm + read-path enforcement)
- [Engineering plan §5](../cache-rewrite-phase1-plan.md) — *Read-mode split*
- [Samples/cache-control-samples.md](../Samples/cache-control-samples.md) — concrete scenarios for `maxAge` resolution
- [Apollo cache spec v0.2](https://specs.apollo.dev/cache/v0.2/) — silent on `maxAge: 0` and the no-directive default
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) — context for why these new TTL semantics ship as 3.0
- [ADR 0002 — Record abstraction](./0002-record-abstraction.md) — `CachedField.writtenAt` is the timestamp consulted by §2.4's pseudocode
- [ADR 0004 — Watcher × TTL](./0004-watcher-ttl.md) — the `automaticallyRefreshOnExpiry` opt-in design that builds on this ADR's read-mode split
- ADR 0005 — Stale tolerance via `RequestConfiguration` and `.revalidateCache` (forthcoming, PR-004b): the consumer-facing API for choosing read mode, the `Source.cache(containsStaleFields:)` signal, and the `MissingValueReason` diagnostic distinction
