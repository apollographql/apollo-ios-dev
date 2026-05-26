@_spi(Execution) import Apollo
import ApolloAPI
import Foundation

/// Synthetic workload helpers shared across Tier 2 (`NormalizedCache`) benchmarks.
///
/// Mirrors the size buckets in `cache-rewrite-phase1-perf.md` §3.1. Records use
/// stable cache keys (`record_<index>`) and a deterministic field-name pattern
/// so independent runs produce comparable shapes.
public enum BenchmarkWorkloads {
  public static let fieldsPerRecord = 10

  /// Build `count` records of `fieldsPerRecord` scalar fields each. Fields
  /// alternate between String and Int values so the cache exercises both
  /// scalar paths during serialization.
  public static func syntheticRecords(count: Int) -> [Record] {
    (0..<count).map { i in
      var values: [CacheKey: Record.Value] = [:]
      for f in 0..<fieldsPerRecord {
        let key: CacheKey = "field_\(f)"
        if f % 2 == 0 {
          values[key] = "value_\(i)_\(f)"
        } else {
          values[key] = i * 100 + f
        }
      }
      return Record(key: "record_\(i)", values)
    }
  }

  /// First `count` cache keys produced by `syntheticRecords(count:)`. Useful
  /// for batched `loadRecords(forKeys:)` scenarios.
  public static func syntheticKeys(count: Int) -> Set<CacheKey> {
    Set((0..<count).map { CacheKey("record_\($0)") })
  }
}
