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
  /// projections returned a record has a `Record` here containing the
  /// fields the cache held.
  ///
  /// `Result` rather than `Record` directly so that a load failure
  /// for one key fails subsequent reads of that key consistently —
  /// a sticky-failure semantic carried over from the pre-3.0
  /// whole-record loader.
  ///
  /// Note that the absence of a `loaded[key]` entry is a third state:
  /// "the key was attempted at some point and the cache had no record
  /// for it." That state is encoded by combining `loaded[key] == nil`
  /// with a populated `attemptedFields[key]` (see below).
  private var loaded: [CacheKey: Result<Record, any Error>] = [:]

  /// Per-cacheKey set of field names a prior flush has *asked the
  /// cache about*. Distinct from `loaded[key].fields` because a field
  /// can be attempted-and-found (`loaded[key].fields` contains it),
  /// attempted-and-known-missing (cache had the record but not the
  /// field — `loaded[key]` is `.success(record)` but the field is
  /// not in `record.fields`), or attempted-and-absent-record (no
  /// `loaded[key]` entry at all, but the cache key was requested).
  ///
  /// `isAlreadyLoaded(_:)` consults this map to short-circuit *every*
  /// attempted projection — including known-missing and absent-record
  /// cases — so repeated enqueues for the same `(cacheKey, fieldName)`
  /// never re-batch within one transaction's lifetime. Without this,
  /// the `loaded[key].fields` check alone would re-batch known-missing
  /// fields on every subsequent enqueue.
  private var attemptedFields: [CacheKey: Set<String>] = [:]

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

  /// Clears all pending, loaded, and attempted state. Called after a
  /// write transaction merge so subsequent reads observe the updated
  /// data.
  func removeAll() {
    pending.removeAll()
    loaded.removeAll()
    attemptedFields.removeAll()
  }

  // MARK: - Private

  /// True iff a prior flush has already *attempted* to load this
  /// projection's `(cacheKey, fieldName)` pair — covering all three
  /// post-flush states for the field:
  ///
  /// - **Found:** the cache returned a record containing this field.
  ///   The value is in `loaded[cacheKey].fields[fieldName]`.
  /// - **Known missing:** the cache returned a record for this key
  ///   but without this field. `loaded[cacheKey]` exists; the field
  ///   is absent from its `fields`.
  /// - **Absent record:** the cache had no record for this key at
  ///   all. `loaded[cacheKey]` is nil; the `attemptedFields` entry
  ///   alone records the attempt.
  /// - **Sticky failure:** a prior flush threw for this key. Every
  ///   subsequent projection on this key short-circuits as the same
  ///   failure via `loadResult(forKey:)`.
  ///
  /// Short-circuiting in every post-attempt case avoids re-batching
  /// known-missing fields and known-absent records on repeated
  /// enqueue — a behavior the pre-3.0 whole-record `DataLoader`
  /// provided implicitly via `cache[key] = .success(nil)` for absent
  /// keys.
  private func isAlreadyLoaded(_ projection: FieldProjection) -> Bool {
    // Sticky failure: every projection on a failed key short-circuits.
    if case .failure = loaded[projection.cacheKey] { return true }
    // Any prior attempt — found, known-missing, or absent record —
    // is recorded in `attemptedFields`.
    return attemptedFields[projection.cacheKey]?.contains(projection.fieldName) ?? false
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
  /// records every attempted `(cacheKey, fieldName)` in
  /// `attemptedFields` regardless of whether the field was found.
  ///
  /// Each loaded `Record`'s `fields` is *merged* into any existing
  /// entry under the same key — a prior flush may have populated a
  /// subset of the fields a subsequent projection requests, and the
  /// caller wants to see the union.
  ///
  /// The `attemptedFields` update is independent of the
  /// found/missing/absent triage so subsequent enqueues for already-
  /// attempted pairs always short-circuit, eliminating the re-batch
  /// of known-missing fields and absent records that the pre-3.0
  /// whole-record loader avoided implicitly.
  private func flush() async throws {
    guard !pending.isEmpty else { return }
    let toLoad = Array(pending)
    pending.removeAll()

    // Every projection in this batch is now "attempted" — regardless
    // of whether the batchLoad call succeeds or throws. Recording
    // here (before the call) avoids divergence between the success
    // and failure paths.
    for projection in toLoad {
      attemptedFields[projection.cacheKey, default: []].insert(projection.fieldName)
    }

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
          }
          // Absent record: the `attemptedFields` entry above
          // already records the attempt, so subsequent enqueues
          // short-circuit via `isAlreadyLoaded` even though
          // `loaded[cacheKey]` stays nil.
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
