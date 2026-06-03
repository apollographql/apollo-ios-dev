@_spi(Execution) import ApolloAPI

/// Batches `FieldProjection` reads against a `NormalizedCache` for the
/// duration of one `ReadTransaction`. Projections enqueued across
/// multiple deferred call sites coalesce into a single
/// `loadFields(_:)` call when the first deferred value is forced —
/// the deferred-then-batched pattern that the 2.x `DataLoader<CacheKey,
/// Record>` previously provided at whole-record granularity, now
/// expressed at field-projection granularity.
///
/// This is the "phase 2 resolve" half of ADR 0007 Principle 5's
/// two-phase pattern. `FieldProjectionCollector` (PR-009d-i) drives
/// "phase 1 collect" at each selection-set recursion entry; the
/// cache execution source enqueues those projections here, then
/// returns a `PossiblyDeferred<Record?>` to the executor. The
/// executor's existing `lazilyEvaluateAll` forcing pattern triggers
/// the flush at level boundaries, preserving the cross-sibling
/// batching the pre-3.0 implementation relied on.
///
/// # Lifecycle
///
/// One instance per `ReadTransaction`. Reads accumulate in the
/// transaction's lifetime. The `removeAll()` method clears both the
/// pending and loaded state — called after a write so subsequent
/// reads within the same transaction observe fresh data.
final class ProjectionLoader {
  typealias BatchLoad = ([FieldProjection]) async throws -> [CacheKey: Record]

  private let batchLoad: BatchLoad

  /// Projections waiting to be flushed on the next force.
  private var pending: Set<FieldProjection> = []

  /// Per-cacheKey result cache. After a flush, each cache key whose
  /// projections were loaded has a `Record` here containing only the
  /// projected fields. Subsequent enqueues for the same `(cacheKey,
  /// fieldName)` short-circuit out of `pending` via
  /// `isAlreadyLoaded(_:)`.
  ///
  /// `Result` rather than `Record` directly so that a load failure
  /// for one key fails subsequent reads of that key consistently —
  /// a sticky-failure semantic carried over from the pre-3.0
  /// whole-record loader.
  private var loaded: [CacheKey: Result<Record, any Error>] = [:]

  init(_ batchLoad: @escaping BatchLoad) {
    self.batchLoad = batchLoad
  }

  /// Enqueues the given projections for the next flush. Projections
  /// whose `(cacheKey, fieldName)` is already loaded are skipped —
  /// the field's value is in the result cache and doesn't need to be
  /// re-read.
  func enqueue<S: Sequence>(_ projections: S) where S.Element == FieldProjection {
    for projection in projections where !isAlreadyLoaded(projection) {
      pending.insert(projection)
    }
  }

  /// Returns a `PossiblyDeferred` that, when forced, ensures all
  /// `pending` projections have been flushed and then returns the
  /// `Record` for `cacheKey`. If the cache had nothing stored for
  /// `cacheKey` after flushing, the deferred resolves to `nil`.
  ///
  /// The first force across all siblings is the one that triggers the
  /// `batchLoad` call — every other sibling's force finds its key in
  /// `loaded` and returns immediately. Single flush per level,
  /// matching the pre-3.0 whole-record loader's batching shape.
  func deferredRecord(forKey cacheKey: CacheKey) -> PossiblyDeferred<Record?> {
    if pending.isEmpty {
      return .immediate(loadResult(forKey: cacheKey))
    }
    return .deferred {
      try await self.flush()
      return try self.loadResult(forKey: cacheKey).get()
    }
  }

  /// Clears all pending and loaded state. Called after a write
  /// transaction merge so subsequent reads observe the updated data.
  func removeAll() {
    pending.removeAll()
    loaded.removeAll()
  }

  // MARK: - Private

  /// True iff a prior flush has already loaded a value for this
  /// projection's `(cacheKey, fieldName)` pair. Used to avoid
  /// re-issuing already-satisfied projections on subsequent forces.
  private func isAlreadyLoaded(_ projection: FieldProjection) -> Bool {
    guard let result = loaded[projection.cacheKey] else { return false }
    switch result {
    case .success(let record):
      return record.fields.keys.contains(projection.fieldName)
    case .failure:
      // A prior failure for this key is final; counting it as
      // "loaded" prevents re-issuing the same projection.
      return true
    }
  }

  /// Returns the `Result<Record?, Error>` for the given key, lifting
  /// a missing key to `.success(nil)`. A failure short-circuits as
  /// the recorded error.
  private func loadResult(forKey cacheKey: CacheKey) -> Result<Record?, any Error> {
    switch loaded[cacheKey] {
    case .none: return .success(nil)
    case .some(.success(let record)): return .success(record)
    case .some(.failure(let error)): return .failure(error)
    }
  }

  /// Fires one `batchLoad` covering every currently-pending
  /// projection, merges the returned records into `loaded`, and
  /// clears `pending`.
  ///
  /// Each loaded `Record`'s `fields` is *merged* into any existing
  /// entry under the same key — a prior flush may have populated a
  /// subset of the fields a subsequent projection requests, and the
  /// caller wants to see the union.
  private func flush() async throws {
    guard !pending.isEmpty else { return }
    let toLoad = Array(pending)
    pending.removeAll()

    do {
      let newRecords = try await batchLoad(toLoad)
      for projection in toLoad {
        let cacheKey = projection.cacheKey
        let newRecord = newRecords[cacheKey]
        switch loaded[cacheKey] {
        case .some(.success(var existing)):
          if let newRecord {
            existing.fields.merge(newRecord.fields) { _, new in new }
            loaded[cacheKey] = .success(existing)
          }
          // If newRecord is nil, the prior partial record still
          // covers what we had; nothing to merge.
        case .none:
          if let newRecord {
            loaded[cacheKey] = .success(newRecord)
          } else {
            // Record the absence so subsequent projections for this
            // key short-circuit via `loadResult`'s `.success(nil)`
            // path. We do NOT insert a sentinel here — `loaded[key]
            // == nil` already encodes "absent". The next enqueue
            // for the same `(cacheKey, fieldName)` will rejoin the
            // pending set, which is wasteful but correct; a future
            // refinement (e.g. PR-009g) can introduce a per-key
            // "known missing" set if profiling motivates it.
            break
          }
        case .some(.failure):
          // Prior failure is sticky; new load doesn't overwrite it.
          break
        }
      }
    } catch {
      // Record the failure for every key that was in this batch so
      // subsequent reads see a consistent error.
      for projection in toLoad {
        if loaded[projection.cacheKey] == nil {
          loaded[projection.cacheKey] = .failure(error)
        }
      }
      throw error
    }
  }
}
