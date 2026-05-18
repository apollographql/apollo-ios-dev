# Cache Rewrite — Phase 1 Performance Measurement Plan

**Audience:** The cache rewrite implementer; reviewers; future maintainers; customers evaluating the 3.0-alpha.
**Companion documents:**
- [cache-rewrite-phase1-summary.md](./cache-rewrite-phase1-summary.md) — manager-facing summary.
- [cache-rewrite-phase1-plan.md](./cache-rewrite-phase1-plan.md) — engineering design plan.
- [cache-rewrite-phase1-execution.md](./cache-rewrite-phase1-execution.md) — AI execution workflow with the PR list.

This document specifies the performance measurement plan for the Phase 1 cache rewrite. The deliverable is a comprehensive comparison dataset between Apollo iOS 2.x (current `main`) and 3.0-alpha (end of Phase 1A) covering cache I/O, in-memory serialization, and GraphQL execution. The dataset is published alongside the 3.0-alpha release tag.

## 1. Goals

1. **Detect regression early.** Catch any operation that becomes meaningfully slower in 3.0 before customers do. The new SQLite schema is expected to be faster on most operations and equivalent on the rest (per Zach's benchmark); other layers must not regress measurably.
2. **Quantify expected improvements.** Where 3.0 is faster, publish the magnitude. Customers evaluating whether to upgrade need numbers, not adjectives.
3. **Establish a multi-version baseline.** The dataset format and tooling continue past 3.0 — Phase 2 features re-run the same harness and the comparison framework continues to apply.
4. **Produce a customer-shareable artifact.** The 3.0-alpha release notes link to a published dataset that any consumer can read to understand the perf change at upgrade time.

The performance gates in the engineering plan §7.4 are pass/fail thresholds for SQLite operations. This plan is broader: it produces a *dataset*, not just a gate. The gates remain as CI-blocking assertions; the dataset is informational.

## 2. Measurement tiers

Three tiers organized by the surface being measured.

### Tier 1 — End-to-end `ApolloClient.fetch`

What customers actually feel. Drives a full operation through `ApolloClient.fetch(query:cachePolicy:)` with each cache policy and measures wall-clock latency from call to result delivery.

| Scenario | Cache policy | Measures |
|---|---|---|
| Cold cache, network only | `.networkOnly` | Baseline: pure network + parse + normalize + write |
| Warm cache, cache-first hit | `.cacheFirst` | Pure cache read + executor + response model construction |
| Warm cache, cache-first miss falling back to network | `.cacheFirst` (after manual eviction of one field) | Cache read attempt + miss + network fallback |
| Cache and network | `.cacheAndNetwork` | Two deliveries; measures both |
| TTL-induced miss (3.0 only) | `.cacheFirst` with `@cacheControl(maxAge: 1)` query, sleep 2s | TTL strict-read path → network fallback |

Public `ApolloClient` API is stable across 2.x and 3.0 for the first four scenarios. The fifth is 3.0-only by design.

### Tier 2 — `NormalizedCache` protocol level

The cache API surface that custom-cache implementors and direct cache consumers see. Exercises `loadRecords(forKeys:)`, `merge(records:)`, `removeRecord(for:)`, `removeRecords(matching:)`, and `clear()`.

| Scenario | Workload | Measures |
|---|---|---|
| Single-key load | One record of 10 fields | `loadRecords` latency, deserialization cost |
| Batch load | 100 records loaded by key set | Batched load throughput |
| Single-record merge | Add 10 new fields to one record | `merge` latency, serialization cost |
| Many-record merge | 1,000 records into a fresh cache | Bulk-write throughput |
| Pattern delete | `removeRecords(matching: "User_")` against 10k records | Pattern-match and delete cost |

Run against both `InMemoryNormalizedCache` and `SQLiteNormalizedCache`.

### Tier 3 — SQLite raw operations

The lowest tier: direct measurements of the new schema's performance characteristics. Uses Zach's existing benchmark methodology (500k-row dataset, 50 iterations per scenario, multiple devices) and the scenarios documented in the [SQLite Performance Benchmarks Confluence page](https://apollographql.atlassian.net/wiki/spaces/ClientDev/pages/1585152147).

The 2.x baseline for this tier **is the existing Confluence benchmark.** We do not re-capture; we publish the new schema's numbers against the same scenarios and produce a delta. The existing methodology is the reference.

| Scenario | Workload | Measures |
|---|---|---|
| Insert (single field) | Single row INSERT in transaction | Insert latency |
| Select by exact cache key | `SELECT * WHERE cache_key = ?` | Exact-key hit latency (target ≤ 0.2 ms) |
| Select with `LIKE` patterns | Mid/prefix/suffix `LIKE` queries | Pattern-match latency |
| Select by selection set | `IN (?, ?, …)` against multiple cache keys | Batched selection-set load (target ≤ 50 ms with `ORDER BY`) |
| Update by composite key | `UPDATE … WHERE cache_key = ? AND field_name = ?` | Field-level update latency |
| Sort by field (CTE join) | CTE join sorting by `mass` | Worst-case query latency (target ≤ 250 ms) |

These mirror Zach's benchmark scenarios so the delta is directly meaningful.

### Tier 4 — Memory and CPU profiling

A separate, smaller tier focused on resource consumption rather than latency. Captured via Instruments / `xctrace`, not via XCTest performance tests.

| Scenario | Tool | Measures |
|---|---|---|
| Steady-state cache after 10k operations | Instruments Allocations | Peak RSS; sustained heap; `CachedField` allocation count vs `Record` |
| Sustained read load | Time Profiler | CPU time per `loadRecords`, per executor pass |
| GraphQL executor with deeply-nested query (5 levels, 50 fields) | Time Profiler | Hot-path identification; comparison of executor cost between versions |

Tier 4 produces qualitative findings rather than a numeric dataset row. Captured once near the end of Phase 1A; included in the published report as a brief commentary section.

## 3. Workloads

Three workload classes. Every tier runs scenarios from at least one class; some run all three.

### 3.1 Synthetic micro-workloads

Controlled record sizes, controlled query shapes. The scenarios from Tier 3 (matching Zach's benchmark) are all synthetic.

- **Tiny:** 100 records × 5 fields each.
- **Small:** 1,000 records × 10 fields each.
- **Medium:** 10,000 records × 10 fields each.
- **Large:** 500,000 records × ~10 fields each (matches Zach).

### 3.2 Real-schema workloads

Drive the existing test schemas (`AnimalKingdomAPI`, `StarWarsAPI`, `GitHubAPI` — present in `Sources/`) with realistic queries. Records are sized as the schemas naturally produce them; query shapes match the test operations.

This catches issues that synthetic workloads miss — heterogeneous record sizes, real selection-set patterns, type-system effects (interfaces, unions, fragments).

### 3.3 Stress workloads

Find the cliff edges:

- **Wide records:** records with 100+ fields. Tests serialization cost scaling.
- **Deep query nesting:** queries 6+ levels deep, with fragments at each level. Tests executor scaling.
- **Hot-key contention:** repeated reads of the same record across concurrent tasks. Tests `AsyncReadWriteLock` overhead.

Stress workloads are not part of the per-PR gate; they run once at end of Phase 1A and any regression discovered is filed against the alpha tag for triage before 3.0-beta.

## 4. Methodology

### 4.1 Iteration count and statistics

- **50 iterations per scenario** (matching Zach's methodology). For each scenario, report mean, standard deviation, P50, P95, P99 latency.
- **Cold and warm cache states** measured separately. A cold scenario is preceded by `cache.clear()` and a fresh database file; a warm scenario is preceded by populating the cache to the workload's required state.
- **Test isolation.** Each scenario runs in a fresh test fixture; no cross-scenario state.

### 4.2 Device matrix

> **Phase 1 simplification (2026-05):** macOS is the only active baseline destination for the 2.x → 3.0-alpha comparison. The iOS rows below remain documented as the eventual goal but are deferred — `ApolloPerformanceTests` is configured as a host-app-less unit-test target, which means iOS device and Simulator destinations reject the test bundle (*"Tool-hosted testing is unavailable on device destinations"*). Reviving the iOS rows requires adding a host-app target for `ApolloPerformanceTests`; that work is a candidate follow-up but is not blocking Phase 1.

| Device | Purpose | Phase 1 status |
|---|---|---|
| **macOS (Apple Silicon)** | Phase 1 primary gate. Runs the harness via the existing host-less unit-test target — no project structural changes required. Reference numbers come from an `arm64` developer host (e.g., MacBook Pro M-series). | **Active gate** |
| **iPhone 16 Pro (physical)** | Matches Zach's original benchmark methodology; the eventual real-world gate. Requires a host-app target for `ApolloPerformanceTests`. | Deferred |
| **iPhone 16 Pro Simulator** | CI-runnable approximate tracking of device numbers. Also requires a host-app target. | Deferred |
| **iPhone SE (3rd gen) Simulator** | Older-device regression catch. Requires a host-app target. | Deferred |

The published dataset for the 3.0-alpha tag captures the macOS row. iOS rows are restored to the dataset shape when their gate is reactivated.

### 4.3 Tooling

- **XCTest performance tests (`measure { … }`)** for Tier 1, 2, and 3 latency captures. Built-in, integrates with the test runners. Statistical reporting limited to mean and standard deviation; we extract richer percentiles by inspecting the iteration array directly via the `XCTPerformanceMetric` API.
- **`xctrace record`** for Tier 4 profiling. Captures `.trace` files; exported via `xctrace export`.
- **Custom JSON exporter** for cross-version comparison. Each test produces a JSON line with `{scenario, tier, device, version, mean_ms, std_ms, p50_ms, p95_ms, p99_ms, iteration_count, timestamp}`. The reporter aggregates lines into the published dataset.

### 4.4 What we explicitly do not measure in Phase 1

- **Cold-launch cache initialization.** The drop-and-rebuild migration adds startup latency on the first 3.0 launch (one extra network round trip). This is documented behavior, not a regression to detect; not measured in this dataset.
- **Database file size on disk.** Zach's benchmark measured this; the 7% size delta between single-col and multi-col layouts is settled. Re-measurement is not informative.
- **Network costs.** Tier 1 uses a stubbed local network transport. Real network variability would dominate the signal; we measure the cache layer's contribution only.
- **Multi-process or multi-app cache sharing.** Phase 2+.

## 5. Comparison and reporting

### 5.1 The published dataset

A single JSON file (`cache-rewrite-phase1-perf-dataset.json`) checked into `apollo-ios/Design/perf/` and linked from the 3.0-alpha release notes. Schema:

```json
{
  "version": "3.0-alpha",
  "captured_at": "<ISO8601 timestamp>",
  "git_sha": "<sha of the alpha commit>",
  "baseline_version": "2.x",
  "baseline_git_sha": "<sha of the 2.x commit>",
  "device": "<device descriptor>",
  "results": [
    {
      "tier": 1,
      "scenario": "warm-cache-first-hit-ten-fields",
      "version": "3.0-alpha",
      "mean_ms": <number>,
      "std_ms": <number>,
      "p50_ms": <number>,
      "p95_ms": <number>,
      "p99_ms": <number>,
      "iterations": 50,
      "delta_vs_baseline_pct": <number>,
      "verdict": "improved" | "parity" | "regressed"
    },
    ...
  ]
}
```

Verdict thresholds:
- **Improved:** mean is at least 5% faster than 2.x baseline.
- **Parity:** within ±5% of 2.x baseline.
- **Regressed:** at least 5% slower than 2.x baseline.

A regressed verdict on any Tier 1 or Tier 2 scenario is a blocker for the 3.0-alpha tag; it must be either fixed or explicitly accepted by the reviewer with documented rationale before tagging.

### 5.2 Published report

A short markdown document (`cache-rewrite-phase1-perf-report.md`) accompanies the JSON dataset. Format:

1. Executive summary table (one row per tier, with overall improved/parity/regressed counts).
2. Headline numbers (top 5 improvements, top 5 regressions or parity-edge cases).
3. Tier 4 (memory/CPU) commentary section.
4. Methodology section pointing back to this document.

Both the JSON and the markdown are checked into the repo so reviewers can see exactly what's published.

## 6. Schedule and execution-plan integration

### 6.1 Phase 0 deliverables

A new PR in Phase 0 captures the 2.x baseline:

- **PR-004a** (new): `chore(cache): capture 2.x performance baseline dataset`. Builds the harness against the 2.x codebase, runs against `main` on the gate device, produces `apollo-ios/Design/perf/baseline-2.x.json`. Stacks on PR-004 (the last ADR).

The harness code lives in a new directory `Tests/PerformanceBenchmarks/` outside the subtree directories so it is visible to dev-repo CI but not pushed upstream.

Phase 0 calendar grows from 2 weeks to 3 weeks to absorb this work. Engineer-weeks: 2 → 3.

### 6.2 Phase 1A deliverables

Two new PRs after PR-011 (the existing SQLite perf gate):

- **PR-011a** (new): `feat(cache): comprehensive performance measurement harness`. Implements Tier 1 and Tier 2 scenarios against the 3.0 codebase. Stacks on PR-011.
- **PR-011b** (new): `chore(cache): alpha-vs-2.x comparison reporter`. Generates `cache-rewrite-phase1-perf-dataset.json` and `cache-rewrite-phase1-perf-report.md` from the harness output and the 2.x baseline JSON. Stacks on PR-011a.

Phase 1A engineer-weeks: 4 → 5; calendar: 6–7 weeks → 7–8 weeks.

### 6.3 Phase 1A exit criterion update

The existing alpha-shippability exit criterion in execution plan §8 is augmented:

> *"…3.0-alpha tag is releasable from this milestone. The published performance dataset (`cache-rewrite-phase1-perf-dataset.json`) accompanies the tag. No Tier 1 or Tier 2 scenario shows a `regressed` verdict, or all such regressions are explicitly accepted with documented rationale."*

### 6.4 Total Phase 1 timeline impact

| Phase | Engineer-weeks (was → now) | Calendar (was → now) |
|---|---|---|
| 0 | 2 → 3 | 2 → 3 |
| 1A | 4 → 5 | 6–7 → 7–8 |
| 1B | 4 (unchanged) | 5–6 (unchanged) |
| 1C | 3 (unchanged) | 4 (unchanged) |
| 1D | 4 (unchanged) | 4–5 (unchanged) |
| **Total** | **17 → 19** | **21–24 → 23–26 (≈ 5.5–6 months)** |
| **With 25% contingency** | | **27–30 → 29–33 (≈ 6.5–7.5 months)** |

Plan against 6.5–7.5 months calendar.

## 7. Subsequent phases

Phase 1B, 1C, and 1D do not add new measurement work. The harness from PR-011a is run again at the end of each phase; results are appended to the dataset under a new version label (`3.0-beta-pr-019`, `3.0-beta-pr-026`, `3.0-beta`). The reporter is regenerated at each milestone.

If a phase introduces a new performance-relevant subsystem not covered by the existing scenarios — for example, the watcher's auto-refresh timer in Phase 1D adds new timing characteristics that aren't covered by Tier 1 scenarios — a small `feat(perf): add scenario for X` PR adds the scenario before the phase exits. These are anticipated to be small (~100 LoC each) and are not pre-allocated in the §8 PR list; they are added inline as discovered.

## 8. Open questions

These are flagged for Phase 0 design lock alongside the ones in [cache-rewrite-phase1-plan.md §12](./cache-rewrite-phase1-plan.md):

1. **Where does the published dataset live?** Options: GitHub release notes attachment, dedicated `apollo-ios/Design/perf/` directory in the repo, Confluence page in ClientDev, or a combination. This document assumes the repo-resident option.
2. **Iteration count tradeoff.** 50 iterations matches Zach but doubles CI time when the harness lives in CI. Some scenarios may warrant fewer iterations (10–20) for the per-PR gate, with the full 50 reserved for the alpha-tag dataset. Confirm during Phase 0.
3. **Regression threshold.** ±5% may be too tight for some scenarios (especially Tier 1 where network stubbing adds variance) or too loose for others (Tier 3 single-row operations where 5% is meaningful). Per-tier thresholds may be more honest than a single 5% rule.
4. **Tier 4 inclusion criteria.** Memory and CPU profiling captures are qualitative; how prominent should they be in the published report? Brief commentary section (this document's current assumption) versus full second dataset.
5. **Real-device CI access.** PR-merge-gating tests need device access. Option: run on a self-hosted Mac runner with a tethered iPhone 16 Pro; option: run synthetic-only on Simulator in CI and take real-device numbers manually pre-tag. The latter is what the engineering plan §7.4 currently assumes.
