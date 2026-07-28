# ADR 0008 — Incomplete cache hits and the fetch-policy surface

- **Status:** Proposed (problem statement accepted; design and decision required before the 3.0 final tag)
- **Date:** 2026-07-28
- **Engineering plan reference:** [cache-rewrite-phase1-execution.md](../cache-rewrite-phase1-execution.md) Pre-3.0 investigations, INV-004 (absorbs the former INV-006 and INV-007)
- **Related ADRs:** [0007](./0007-selection-aware-cache-reads.md) (selection-aware cache reads)

## Context

A cache read today reports exactly two states to the request chain: **hit** (a non-`nil` `GraphQLResponse`) or **miss** (`nil`). `DefaultCacheInterceptor.readCacheData` signals by nil-check, and `FetchBehavior.shouldFetchFromNetwork(.onCacheMiss)` — the `cacheFirst` policy — treats any non-`nil` result as fully satisfied.

Three behaviors, reviewed and accepted for the Phase 1 stack, all press against that two-state boundary. Each returns a *technically successful* cache result that is **incomplete** in a way the fetch machinery cannot see:

### Symptom 1 — Pending deferred fragments count as a full hit

A cache read that fulfills every non-deferred selection but leaves `@defer` fragments `.pending` is a non-`nil` result — a full hit under `cacheFirst`. The pending fragments never fulfill from that fetch; the caller needs `cacheAndNetwork`/`networkOnly` or a watcher to get them. This is inherited 2.x behavior (shipped with the original `@defer` execution work), not introduced by the Phase 1 stack.

`@defer` cannot be fetched piecemeal — completing the pending fragments means re-running the whole operation and streaming initial + incremental chunks. So "return the partial cache data and complete over the network" is closer to `cacheAndNetwork` semantics scoped to incomplete results, and it changes how many results a single fetch emits.

### Symptom 2 — `@fieldPolicy` list reads are all-or-nothing

A `.policyReferenceList` cache read fails entirely if any one of the N policy-derived target records is absent: `resolveReferences` propagates the missing-record error and the whole read misses. (2.x silently dropped missing entries; the stricter Phase 1 behavior was accepted as the interim state.)

The target model is the web client's partial-result behavior: return the records that exist up to the first missing one, drop the rest, and mark the result **incomplete** so the request chain knows to fetch the remainder from the server despite having returned cache data.

### Symptom 3 — Deferred-fragment load *errors* masquerade as `.pending`

On a cache read, each `@defer`red fragment executes in an isolated `do`/`catch`; *any* error marks the fragment `.pending` and the read continues. That is correct when the fragment's data is genuinely uncached, but it also swallows infrastructure failures: a SQLite IO error or a decode failure during one fragment's load is converted into the same `.pending` state as "the server hasn't delivered this yet."

Fragments execute sequentially and re-enqueue their own projections, so one fragment's failure does not prevent a sibling fragment's load attempt. But the failed fragment surfaces as indefinitely pending — and combined with Symptom 1, there is no recovery path: no error is reported and no network fetch fires.

## Problem statement

The cache read must be able to report richer state than hit-or-miss — at minimum distinguishing:

1. **Complete hit** — everything requested was served.
2. **Incomplete hit** — valid partial data was returned, but part of the request was not satisfied (pending deferred fragments; a truncated policy-derived list). The fetch policy needs the option to return the partial data *and* continue to the network.
3. **Degraded hit** — part of the result reflects a load *failure*, not absence (Symptom 3). This must be distinguishable from "incomplete" so errors are not silently converted into permanently-pending data.

Correspondingly, the fetch policies (or `FetchBehavior`) need a way to express what to do with each — e.g. treat an incomplete hit as requiring network continuation, or surface a degraded hit's underlying error.

## Decision

Deferred. The incomplete-hit signal should be **designed once**, covering all three symptoms, rather than patched per-symptom. Constraints already identified:

- The signal must flow from execution (where pending/partial/failed states are known) through `ApolloStore.load` and the cache interceptor to `FetchBehavior` — today's nil-check boundary discards it.
- Symptom 1's completion fetch re-runs the whole operation and streams multiple results; the fetch-policy API must accommodate multi-emission.
- Symptom 2's partial-list semantics change the shape of returned data and deserve a changelog entry and tests regardless of the signal design.
- Symptom 3 requires an error channel distinct from `.pending` — options include propagating as a read error, an explicit per-fragment error state, or folding into the degraded-hit signal.
- PR-029 (3.0 documentation) must document whichever semantics ship.

## Consequences

Until this lands: `cacheFirst` reads with pending deferred fragments do not fetch their deferred data; a missing `@fieldPolicy` list target misses the whole read; and a fragment-scoped load error is indistinguishable from uncached data. All three are accepted for the Phase 1 stack and tracked for resolution before the 3.0 final tag.
