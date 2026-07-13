# ADR 0004 — Watcher × TTL: opt-in auto-refresh with permissive propagating reads

- **Status:** Accepted
- **Date:** 2026-05-07
- **Phase 1 PR:** PR-004 (cache rewrite execution plan §8)
- **Engineering plan reference:** [cache-rewrite-phase1-plan.md §6](../cache-rewrite-phase1-plan.md)

## Context

Phase 1 introduces per-field TTL on cached data. Watchers (`GraphQLQueryWatcher`) interact with the cache in a way that's distinct from explicit fetches: they subscribe to `ApolloStore.didChangeKeys` events and re-read the query on overlap. This raises questions that weren't present in the 2.x model — questions that are not answered by the read-mode split alone:

1. **Should watchers automatically detect that their delivered data has expired?** The watcher's last delivered result was fresh when delivered. If `writtenAt + maxAge` elapses while the watcher sits idle and nothing else writes to the cache, the data the consumer sees is now stale, but no `didChangeKeys` event will fire.
2. **What should happen when a `didChangeKeys` event fires for an unrelated reason and the re-read encounters expired data?** Without an explicit policy, the existing missing-value propagation would trigger a network refetch — but that fires not because the consumer asked for fresh data, but because some unrelated mutation happened to overlap with the watcher's dependent keys. The user-experience consequence is unpredictable network traffic.
3. **How should `maxAge: 0` (the always-stale case from ADR 0003 §2.1) interact with watcher behavior?** A literal reading would mean every watcher whose query touches a `maxAge: 0` field thrashes — every relevant cache write triggers a refetch, every refetch produces stale data again, every read keeps missing.

These are interlocking questions about watcher semantics that need a coherent answer. The read-mode split from [ADR 0003 §2.3](./0003-ttl-semantics.md) is the substrate this ADR builds on; this ADR specifies the watcher-specific policy on top.

## Decision

### 2.1 Default behavior: lazy

By default, watchers do **not** automatically refresh on TTL expiry. Specifically:

- The watcher continues to subscribe to `ApolloStore.didChangeKeys` events and re-read the query on overlap (existing 2.x behavior, preserved).
- The re-read uses `ttlEnforcement: .permissive` (per [ADR 0003 §2.3](./0003-ttl-semantics.md)). Time-based expiry has no effect on the watcher's delivered output during a propagating read.
- The watcher's last delivered result remains visible until either:
  - A cache write to a dependent key triggers a re-read (which delivers the post-write value, regardless of TTL), or
  - The consumer explicitly calls `watcher.fetch(cachePolicy: .cacheFirst)`. That goes through the strict read path; if any field has expired, the strict read fails and the existing network fallback triggers a refetch.

This is the conservative default. Consumers who want time-based revalidation opt in (§2.2).

### 2.2 Opt-in auto-refresh

A new `GraphQLQueryWatcher` initializer parameter:

```swift
public init(
  client: ApolloClient,
  query: Query,
  refetchOnFailedUpdates: Bool = true,
  automaticallyRefreshOnExpiry: Bool = false,    // new in 3.0
  resultHandler: @escaping ResultHandler
) async
```

When `automaticallyRefreshOnExpiry == true`:

1. After every successful result delivery, the watcher computes the **earliest finite expiry** across all fields in `dependentKeys`. This is the minimum of `cachedField.writtenAt + maxAge` across fields whose `cacheControl.maxAge` is non-nil and `> 0`. Fields with `maxAge: 0` are excluded (they have no schedulable expiry — see §2.4).
2. The watcher schedules a one-shot `Task` that sleeps until the earliest expiry.
3. When the timer fires, the watcher calls `fetch(cachePolicy: .cacheFirst)`. The strict read path will hit the network if anything has expired; otherwise it redelivers the cached value. Either path produces a result, which triggers a reschedule of the timer for the new earliest expiry.
4. Cache writes that arrive via `didChangeKeys` cancel the existing timer and reschedule based on the post-merge timestamps (writes refresh `writtenAt`, so the earliest expiry typically moves forward in time).
5. Watcher cancellation cancels the timer.

The earliest-expiry calculation is supported by a new `GraphQLResponse.earliestExpiry: Date?` field (engineering plan §6.4) computed by the dependency tracker during normalization. The watcher reads it from the result rather than walking the cache itself.

### 2.3 Read-mode policy is independent of the opt-in flag

The opt-in flag controls **timer scheduling**, not read mode. Watcher re-reads on `didChangeKeys` use `.permissive` regardless of whether `automaticallyRefreshOnExpiry` is true or false.

The mental model: opt-in means "I want a timer that fires when finite-TTL fields expire, so my UI can show fresh data after a known interval." It does **not** mean "I want every cache write to be treated as a freshness opportunity." Those are different concerns; the flag addresses only the first.

### 2.4 `maxAge: 0` interaction

The combination of decisions above produces clean `maxAge: 0` semantics in both watcher modes:

- **Default watcher (auto-refresh off).** Permissive read on `didChangeKeys` ignores the always-stale field; the cached value is returned. No thrash. The `maxAge: 0` field's "always stale" property has no effect on watchers in this mode; it activates only when the consumer issues an explicit fetch.
- **Opt-in watcher (auto-refresh on).** `maxAge: 0` fields are excluded from the earliest-expiry calculation in §2.2 step 1. They have no schedulable expiry; "now" is not a valid sleep deadline. So the timer is not scheduled around them. The propagating-read path is permissive (per §2.3), so unrelated cache writes don't trigger refetches either. `maxAge: 0` fields refresh only on consumer-initiated fetches.

`maxAge: 0` thus has a precise semantics in the watcher world: *force network on consumer-initiated reads of this field, and do nothing in propagating or timer-driven paths.*

## Alternatives considered

### A. Default watcher uses strict reads on `didChangeKeys`

Make the strict read mode the default for both consumer-initiated reads and watcher propagating reads. The opt-in flag is unnecessary because TTL is always enforced.

- *Rejected because:* This produces the surprise behavior described in §Context item 2 — unrelated cache writes trigger network refetches because of TTL on fields that aren't visibly stale to the consumer. The "happy accident" revalidation would actually be unwanted behavior. Also, this rejected the option that ADR 0003 §2.3 already settled (single-strict mode).

### B. No opt-in flag; auto-refresh is always on

Remove the conservative default; every watcher schedules a timer for finite-TTL fields by default.

- *Rejected because:* This makes timer-driven network calls implicit in any query that uses `@cacheControl`, which has battery, network-cost, and user-control implications that should be explicit. Some apps use TTL purely as a freshness hint for explicit fetches and don't want timers driving refetches in the background. Defaulting auto-refresh on couples the directive with timer behavior in a way that the directive itself doesn't imply.

### C. Auto-refresh as a global client setting, not a per-watcher flag

Configure auto-refresh on `ApolloClient` (e.g., `ApolloClient.Configuration.autoRefreshWatchersOnExpiry: Bool`); apply uniformly to all watchers.

- *Rejected because:* Different watchers in the same app have different freshness requirements. A list view that shows cached items doesn't need timer-driven refresh; a detail view that shows volatile data does. Per-watcher control is the right granularity. A global setting is layered on top if desired (e.g., a default initializer parameter the client provides), but the per-watcher flag is the primitive.

### D. Auto-refresh fires the timer with `.networkOnly`, not `.cacheFirst`

When the timer fires, force a network fetch directly rather than re-reading the cache first.

- *Rejected because:* If a write happened between the timer being scheduled and the timer firing — e.g., another query happened to refresh the relevant fields — the cache may already be fresh. `.cacheFirst` correctly handles that case (delivers cached data, no network call, reschedules). `.networkOnly` would force a wasteful network roundtrip even when unnecessary. The strict read path of `.cacheFirst` is exactly designed for this — go to network only if the cache can't satisfy the request.

### E. Earliest-expiry includes `maxAge: 0` fields by treating them as instant expiry

Schedule the timer to fire "immediately" for any `maxAge: 0` field in the watcher's dependencies, producing tight-loop refetch behavior.

- *Rejected because:* This is the thrash failure mode. `maxAge: 0` should mean "force refresh on consumer-initiated reads," not "thrash forever." The cleaner semantics — `maxAge: 0` is excluded from the timer; refresh happens only on explicit consumer fetches — preserves the directive's usefulness without the thrash. If a consumer wants polling, they should implement it explicitly at the app level (a `Timer` driving a fetch loop), not have it be implicit in the watcher.

### F. Coalesced store-level timer instead of per-watcher timer

Maintain a min-heap of expiry times across all watchers in `ApolloStore`. One global timer fires at the earliest expiry across the whole cache; the store walks subscribers and notifies whoever's affected.

- *Rejected because:* The min-heap data structure must be kept in sync with every cache write and every watcher subscription/cancellation, which is meaningful complexity for a primitive (timers) that has cheap natural alternatives. Per-watcher timers cost one sleeping `Task` per opt-in watcher; for the watcher counts typical in iOS apps (typically dozens, not thousands), this is negligible. The complexity of a coalesced timer is not justified by the per-timer cost. Reconsider in Phase 2+ if profiling shows per-watcher-task overhead is meaningful in real apps.

## Consequences

### Positive

- **Default behavior is conservative and predictable.** Time-based expiry doesn't cause surprise network calls in apps that haven't opted in. The 2.x revalidation behavior (refetch on actual cache miss during a propagating read) is preserved.
- **Opt-in feature is genuinely useful.** Apps that want time-based UI refresh get it via one parameter at watcher construction. The implementation is bounded — one sleeping `Task` per opt-in watcher, with deterministic cancellation.
- **`maxAge: 0` thrash is structurally impossible.** The combination of permissive propagating reads and finite-only timer scheduling means that volatile fields refresh on consumer-initiated reads only, regardless of whether the watcher is opt-in. There is no path through the watcher that produces a refetch loop.
- **Earliest-expiry calculation lives in `GraphQLResponse`.** Watchers don't walk the cache to find expiries; they read a precomputed value. This isolates the watcher from cache internals and lets the calculation be optimized in the dependency tracker once.
- **Reversible default.** If real-world usage shows that the conservative default is too cautious, a future minor release can change the default of `automaticallyRefreshOnExpiry` to `true` without breaking the API surface.

### Negative

- **Stale data persists silently in the default mode.** A watcher whose query has finite TTL and whose `automaticallyRefreshOnExpiry` is false will continue to deliver the last known result indefinitely if no other writes touch its dependent keys. The UI shows stale data; nothing notifies the consumer. Mitigation: this is documented in the migration guide; consumers who want freshness either opt in or call `fetch(.cacheFirst)` at meaningful moments (app foreground, pull-to-refresh, etc.).
- **Per-watcher `Task` overhead.** Opt-in watchers each hold a sleeping `Task`. For thousands of opt-in watchers in a single app, this could accumulate measurable scheduler overhead. Mitigation: watcher counts in real apps are typically far below thousands; if profiling later shows this is meaningful, Option F (coalesced timer) is the upgrade path.
- **Earliest-expiry is recomputed on every result delivery.** Each result delivery cancels and reschedules the timer. The recomputation walks the dependent fields' metadata. For very large dependent-key sets this is non-trivial work. Mitigation: the dependent-key set for typical queries is bounded (~10s of fields); the overhead is below the per-fetch network cost it's preventing.

### Neutral

- **The opt-in flag does not affect the read-mode split.** A consumer who reads ADR 0003 expecting the read-mode split and the auto-refresh feature to be a single concept will need to read both ADRs to understand they're independent. Mitigation: this ADR's §2.3 makes the independence explicit; the migration guide spells it out for end users.
- **`maxAge: 0` fields refresh only on consumer-initiated reads, even in opt-in mode.** Some readers may expect the opt-in flag to enable polling-style behavior for `maxAge: 0` fields. It does not; that's a separate concern (a `Timer.publish` driving fetches at the app level). Documented and intentional.

## References

- [Engineering plan §6 — Watcher × TTL behavior](../cache-rewrite-phase1-plan.md)
- [Engineering plan §6.2 — Opt-in auto-refresh](../cache-rewrite-phase1-plan.md)
- [Engineering plan §6.4 — Required additions to GraphQLResponse](../cache-rewrite-phase1-plan.md) (`earliestExpiry`)
- [GraphQLQueryWatcher.swift](../../Sources/Apollo/GraphQLQueryWatcher.swift) — current 2.x implementation that this ADR extends
- [ADR 0003 — TTL semantics](./0003-ttl-semantics.md) — the read-mode split this ADR builds on, and the `maxAge: 0` semantics that the watcher rules complete
- [ADR 0001 — Major version bump](./0001-major-version-bump.md) §Context item 4 — confirms the watcher × TTL design is a new feature on top of the TTL surface, not a 2.x breaking change
