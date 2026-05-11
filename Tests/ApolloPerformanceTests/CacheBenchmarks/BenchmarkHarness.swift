import Foundation

/// Async measurement harness used by the cache-rewrite Phase 1 perf dataset.
///
/// Runs `body` for `warmupIterations + measuredIterations`, discards warmup,
/// and computes mean/std/P50/P95/P99 from the measured samples in milliseconds.
/// Emits a single `BENCHMARK_RESULT_JSONL: { ... }` line to stdout per call so
/// the dataset assembler script can grep results out of `xcodebuild` output.
///
/// One iteration runs `body` exactly once; the harness does not retry on throw —
/// a thrown error fails the test outright. Pass `setup` for per-iteration state
/// that should not be timed (cache warmup, fresh fixtures, etc.).
public struct BenchmarkHarness: Sendable {
  public let scenario: String
  public let tier: Int
  public let warmupIterations: Int
  public let measuredIterations: Int

  public init(
    scenario: String,
    tier: Int,
    warmupIterations: Int = 5,
    measuredIterations: Int = 50
  ) {
    self.scenario = scenario
    self.tier = tier
    self.warmupIterations = warmupIterations
    self.measuredIterations = measuredIterations
  }

  /// Run `body` for the configured iteration count and emit a `BenchmarkResult`.
  ///
  /// `setup` runs before each iteration *outside* the measurement window. Use it
  /// to reset fixtures (clear cache, seed records) without polluting the sample.
  /// Closures are non-`Sendable` because they routinely capture references to
  /// non-`Sendable` caches/stores under test; the harness itself runs the loop
  /// sequentially so there's no actual concurrency to worry about.
  public func measure(
    setup: ((Int) async throws -> Void)? = nil,
    body: (Int) async throws -> Void
  ) async throws -> BenchmarkResult {
    var samplesNs: [UInt64] = []
    samplesNs.reserveCapacity(measuredIterations)

    for i in 0..<(warmupIterations + measuredIterations) {
      try await setup?(i)

      let start = DispatchTime.now().uptimeNanoseconds
      try await body(i)
      let end = DispatchTime.now().uptimeNanoseconds

      if i >= warmupIterations {
        samplesNs.append(end &- start)
      }
    }

    let result = BenchmarkResult(
      scenario: scenario,
      tier: tier,
      samplesNs: samplesNs,
      iterations: measuredIterations
    )
    BenchmarkOutput.emit(result)
    return result
  }
}

/// Emits `BenchmarkResult` records as JSONL lines that the run script picks up.
public enum BenchmarkOutput {
  static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return e
  }()

  public static func emit(_ result: BenchmarkResult) {
    guard let data = try? encoder.encode(result),
          let line = String(data: data, encoding: .utf8) else {
      return
    }
    // Single-line marker so the post-processor can grep + jq.
    print("BENCHMARK_RESULT_JSONL: \(line)")
  }
}
