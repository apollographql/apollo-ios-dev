import Foundation

/// One measured scenario row in the published perf dataset.
///
/// Schema corresponds to `cache-rewrite-phase1-perf.md` §5.1. Latencies are
/// reported in milliseconds for human readability; the harness records in
/// nanoseconds internally to avoid integer truncation on sub-ms samples.
public struct BenchmarkResult: Codable, Sendable {
  public let scenario: String
  public let tier: Int
  public let iterations: Int
  public let mean_ms: Double
  public let std_ms: Double
  public let p50_ms: Double
  public let p95_ms: Double
  public let p99_ms: Double

  public init(scenario: String, tier: Int, iterationDurationsNs: [UInt64], iterations: Int) {
    self.scenario = scenario
    self.tier = tier
    self.iterations = iterations

    let iterationDurationsMs = iterationDurationsNs.map { Double($0) / 1_000_000.0 }
    let sorted = iterationDurationsMs.sorted()

    let mean = iterationDurationsMs.reduce(0, +) / Double(max(iterationDurationsMs.count, 1))
    let variance = iterationDurationsMs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
      / Double(max(iterationDurationsMs.count - 1, 1))

    self.mean_ms = mean
    self.std_ms = variance.squareRoot()
    self.p50_ms = Self.percentile(sorted, 0.50)
    self.p95_ms = Self.percentile(sorted, 0.95)
    self.p99_ms = Self.percentile(sorted, 0.99)
  }

  private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = p * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = Int(rank.rounded(.up))
    if lo == hi { return sorted[lo] }
    let frac = rank - Double(lo)
    return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
  }
}
