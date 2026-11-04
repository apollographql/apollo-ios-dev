@_spi(Execution) import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import ApolloSQLite
import Foundation
import XCTest

/// Tier 2 — `NormalizedCache` protocol benchmarks. See
/// `apollo-ios/Design/cache-rewrite-phase1-perf.md` §2.2 for scenario definitions.
///
/// Subclasses bind `makeCache` to a specific backend so XCTest discovery yields
/// one test class per backend (`InMemory`, `SQLite`). The five scenarios are
/// identical across backends; the only difference is the cache factory.
class Tier2CacheBenchmarksBase: XCTestCase {

  /// Backend label included in the emitted scenario name (e.g. "InMemory", "SQLite").
  class var backendLabel: String { "Base" }

  /// Build a fresh cache plus optional teardown handler for resource cleanup.
  class func makeCache() async -> TestDependency<any NormalizedCache> {
    fatalError("override in subclass")
  }

  /// Holder for per-iteration cache state. `@unchecked Sendable` because the
  /// harness runs the setup → body loop sequentially — there is no actual
  /// concurrent access despite the compiler's pessimism about closures that
  /// span async/main-actor boundaries.
  final class CacheHolder: @unchecked Sendable {
    var cache: (any NormalizedCache)?
    var teardown: TearDownHandler?

    func reset(with cache: any NormalizedCache, teardown: TearDownHandler?) throws {
      try self.teardown?()
      self.cache = cache
      self.teardown = teardown
    }

    func tearDownIfNeeded() throws {
      try teardown?()
      cache = nil
      teardown = nil
    }
  }

  // MARK: - Scenario 1: Single-key load (one record, 10 fields)

  func runSingleKeyLoad() async throws {
    let (cache, tearDown) = await Self.makeCache()
    addTeardownBlock { try? tearDown?() }

    _ = try await cache.merge(records: RecordSet(records: BenchmarkWorkloads.syntheticRecords(count: 1)))
    let keys: Set<CacheKey> = ["record_0"]

    let harness = BenchmarkHarness(
      scenario: "tier2.\(Self.backendLabel.lowercased()).single_key_load_10_fields",
      tier: 2
    )
    _ = try await harness.measure { _ in
      _ = try await cache.loadRecords(forKeys: keys)
    }
  }

  // MARK: - Scenario 2: Batch load (100 records)

  func runBatchLoad() async throws {
    let (cache, tearDown) = await Self.makeCache()
    addTeardownBlock { try? tearDown?() }

    _ = try await cache.merge(records: RecordSet(records: BenchmarkWorkloads.syntheticRecords(count: 100)))
    let keys = BenchmarkWorkloads.syntheticKeys(count: 100)

    let harness = BenchmarkHarness(
      scenario: "tier2.\(Self.backendLabel.lowercased()).batch_load_100_records",
      tier: 2
    )
    _ = try await harness.measure { _ in
      _ = try await cache.loadRecords(forKeys: keys)
    }
  }

  // MARK: - Scenario 3: Single-record merge (10 new fields into one record)
  //
  // The perf plan asks for "merge 10 new fields into one record". We model that
  // by merging a fresh single-record set into the same cache each iteration —
  // the merge logic exercises the same code path as a real per-record write.

  func runSingleRecordMerge() async throws {
    let (cache, tearDown) = await Self.makeCache()
    addTeardownBlock { try? tearDown?() }

    let harness = BenchmarkHarness(
      scenario: "tier2.\(Self.backendLabel.lowercased()).single_record_merge_10_fields",
      tier: 2
    )
    _ = try await harness.measure { iteration in
      // Use a distinct key per iteration so each merge is a write, not a no-op
      // upsert; otherwise the cache could optimize the second-onwards writes.
      var values: [CacheKey: Record.Value] = [:]
      for f in 0..<BenchmarkWorkloads.fieldsPerRecord {
        values["field_\(f)"] = "value_\(iteration)_\(f)"
      }
      let record = Record(key: "merge_iter_\(iteration)", values)
      _ = try await cache.merge(records: RecordSet(records: [record]))
    }
  }

  // MARK: - Scenario 4: Many-record merge (1,000 records into fresh cache)

  func runManyRecordMerge() async throws {
    let harness = BenchmarkHarness(
      scenario: "tier2.\(Self.backendLabel.lowercased()).many_record_merge_1000_records",
      tier: 2
    )
    let holder = CacheHolder()
    addTeardownBlock { try? holder.tearDownIfNeeded() }

    let records = RecordSet(records: BenchmarkWorkloads.syntheticRecords(count: 1_000))
    _ = try await harness.measure(
      setup: { _ in
        let (c, t) = await Self.makeCache()
        try holder.reset(with: c, teardown: t)
      },
      body: { _ in
        _ = try await holder.cache!.merge(records: records)
      }
    )
  }

  // MARK: - Scenario 5: Pattern delete against 10k records

  func runPatternDelete() async throws {
    let harness = BenchmarkHarness(
      scenario: "tier2.\(Self.backendLabel.lowercased()).pattern_delete_10k_records",
      tier: 2
    )
    let holder = CacheHolder()
    addTeardownBlock { try? holder.tearDownIfNeeded() }

    // Seed records under two prefixes; the matching delete only targets
    // `User_*`, leaving `Other_*` untouched. This matches the perf plan
    // scenario which exercises pattern selectivity, not full clear.
    let userPrefixCount = 10_000
    let otherPrefixCount = 1_000
    let seedRecords: [Record] = (0..<userPrefixCount).map { i in
      var values: [CacheKey: Record.Value] = [:]
      for f in 0..<BenchmarkWorkloads.fieldsPerRecord {
        values["field_\(f)"] = "value_\(i)_\(f)"
      }
      return Record(key: "User_\(i)", values)
    } + (0..<otherPrefixCount).map { i in
      Record(key: "Other_\(i)", ["field_0": "value_\(i)"])
    }
    let seedSet = RecordSet(records: seedRecords)

    _ = try await harness.measure(
      setup: { _ in
        let (c, t) = await Self.makeCache()
        try holder.reset(with: c, teardown: t)
        _ = try await c.merge(records: seedSet)
      },
      body: { _ in
        try await holder.cache!.removeRecords(matching: "User_")
      }
    )
  }
}

final class Tier2InMemoryCacheBenchmarks: Tier2CacheBenchmarksBase {
  override class var backendLabel: String { "InMemory" }
  override class func makeCache() async -> TestDependency<any NormalizedCache> {
    await InMemoryTestCacheProvider.makeNormalizedCache()
  }

  func test__tier2_inMemory__singleKeyLoad() async throws { try await runSingleKeyLoad() }
  func test__tier2_inMemory__batchLoad() async throws { try await runBatchLoad() }
  func test__tier2_inMemory__singleRecordMerge() async throws { try await runSingleRecordMerge() }
  func test__tier2_inMemory__manyRecordMerge() async throws { try await runManyRecordMerge() }
  func test__tier2_inMemory__patternDelete() async throws { try await runPatternDelete() }
}

final class Tier2SQLiteCacheBenchmarks: Tier2CacheBenchmarksBase {
  override class var backendLabel: String { "SQLite" }
  override class func makeCache() async -> TestDependency<any NormalizedCache> {
    await SQLiteTestCacheProvider.makeNormalizedCache()
  }

  func test__tier2_sqlite__singleKeyLoad() async throws { try await runSingleKeyLoad() }
  func test__tier2_sqlite__batchLoad() async throws { try await runBatchLoad() }
  func test__tier2_sqlite__singleRecordMerge() async throws { try await runSingleRecordMerge() }
  func test__tier2_sqlite__manyRecordMerge() async throws { try await runManyRecordMerge() }
  func test__tier2_sqlite__patternDelete() async throws { try await runPatternDelete() }
}
