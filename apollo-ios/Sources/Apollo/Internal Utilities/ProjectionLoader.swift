@_spi(Execution) import ApolloAPI

/// Batches `RecordProjection` reads against a `NormalizedCache` for the
/// duration of one `ReadTransaction`. Projections enqueued across
/// multiple deferred call sites coalesce into a single
/// `loadFields(_:)` call when the first deferred value is forced —
/// the deferred-then-batched pattern that the 2.x `DataLoader<CacheKey,
/// Record>` previously provided at whole-record granularity, now
/// expressed at field granularity.
///
/// This is the "phase 2 resolve" half of ADR 0007 Principle 5's
/// two-phase pattern. `ProjectionCollector` drives "phase 1 collect"
/// at each selection-set recursion entry; the cache execution source
/// enqueues those projections here, then returns a
/// `PossiblyDeferred<Record?>` to the executor. The executor's
/// existing `lazilyEvaluateAll` forcing pattern triggers the flush at
/// level boundaries, preserving the cross-sibling batching the pre-3.0
/// implementation relied on.
///
/// # Lifecycle
///
/// One instance per `ReadTransaction`. Reads accumulate in the
/// transaction's lifetime. The `removeAll()` method clears both the
/// pending and per-key state — called after a write so subsequent
/// reads within the same transaction observe fresh data.
final class ProjectionLoader {
  typealias BatchLoad = ([RecordProjection]) async throws -> [CacheKey: Record]

  /// Per-cacheKey state machine for everything the loader needs to
  /// remember after a flush. Collapses the prior two-dictionary
  /// representation (`loaded: [CacheKey: Result<Record, Error>]` plus
  /// `attemptedFields: [CacheKey: Set<String>]`) into one enum so the
  /// possible states are exhaustive in the type system rather than
  /// enforced by hand at every read site.
  ///
  /// Four legal states, mapping back to the documented post-flush
  /// triage:
  ///
  /// - ``loaded(_:attempted:)`` — the cache returned a record for the
  ///   key (the `Record`), and every `attempted` field has been
  ///   asked about. Some attempted fields are present in
  ///   `record.fields` (found); the rest were asked about but came
  ///   back missing (known-missing). The reader merges new fields
  ///   into the existing record and unions new field names into
  ///   `attempted` on subsequent flushes. The `attempted` set is the
  ///   load-bearing distinction in this case: `loadFields(_:)` only
  ///   returns the fields the caller asked about, so an un-attempted
  ///   field on a `.loaded` record might still exist in the cache and
  ///   warrants a re-batch.
  /// - ``absent`` — the cache had no record for this key. Sticky
  ///   until something explicitly invalidates the entry: the
  ///   store's read/write lock guarantees no concurrent writer can
  ///   surface a record under a key we already observed missing,
  ///   and an intra-transaction write to this key would route
  ///   through `invalidate(keys:)` which clears the entry. While
  ///   the entry survives, every field projection on this key —
  ///   same field or different — must short-circuit to the same
  ///   "absent" answer, so tracking which fields were attempted
  ///   would add no information.
  /// - ``failed(_:)`` — a prior flush threw for this key. Sticky
  ///   for the same reason as `.absent`: no concurrent mutation can
  ///   change the recorded outcome under us, and any explicit
  ///   in-transaction mutation routes through `invalidate(keys:)`
  ///   to clear the entry first. While the entry survives, every
  ///   subsequent projection on this key short-circuits as the
  ///   same failure via `loadResult(forKey:)`.
  ///
  /// Absence of an entry (`state[key] == nil`) is the "never attempted"
  /// fourth state: the key has not been seen this transaction.
  private enum KeyState {
    case loaded(Record, attempted: Set<String>)
    case absent
    case failed(any Error)

    /// True iff this state has already attempted `fieldName`. For
    /// `.absent` and `.failed` the answer is always `true` — both are
    /// sticky states whose answer for any field is the recorded
    /// outcome of the key as a whole.
    func hasAttempted(_ fieldName: String) -> Bool {
      switch self {
      case .loaded(_, let attempted): return attempted.contains(fieldName)
      case .absent, .failed:           return true
      }
    }
  }

  private let batchLoad: BatchLoad

  /// Field names waiting to be flushed on the next force, accumulated
  /// per cache key. `RecordProjection` is a transfer type — same-key
  /// requests from different call sites must *merge*, so accumulation
  /// happens in a dictionary and converts to `[RecordProjection]` at
  /// the `batchLoad` boundary.
  private var pending: [CacheKey: Set<String>] = [:]

  /// Per-cacheKey post-flush state. See ``KeyState`` for the four
  /// states this map encodes and how they replace the prior
  /// two-dictionary representation.
  private var state: [CacheKey: KeyState] = [:]

  init(_ batchLoad: @escaping BatchLoad) {
    self.batchLoad = batchLoad
  }

  /// Enqueues the given projection for the next flush. Fields whose
  /// `(cacheKey, fieldName)` has already been attempted are skipped —
  /// the field's outcome is in the result cache and doesn't need to be
  /// re-read.
  func enqueue(_ projection: RecordProjection) {
    let newFields: Set<String>
    if let keyState = state[projection.cacheKey] {
      newFields = projection.fieldNames.filter { !keyState.hasAttempted($0) }
    } else {
      newFields = projection.fieldNames
    }
    guard !newFields.isEmpty else { return }
    pending[projection.cacheKey, default: []].formUnion(newFields)
  }

  /// Convenience: enqueues several projections. Same-key projections
  /// merge into one pending field-name set.
  func enqueue<S: Sequence>(_ projections: S) where S.Element == RecordProjection {
    for projection in projections {
      enqueue(projection)
    }
  }

  /// Returns a `PossiblyDeferred` that, when forced, ensures all
  /// `pending` projections have been flushed and then returns the
  /// `Record` for `cacheKey`. If the cache had nothing stored for
  /// `cacheKey` after flushing, the deferred resolves to `nil`.
  ///
  /// The first force across all siblings is the one that triggers the
  /// `batchLoad` call — every other sibling's force finds its key in
  /// `state` and returns immediately. Single flush per level, matching
  /// the pre-3.0 whole-record loader's batching shape.
  func deferredRecord(forKey cacheKey: CacheKey) -> PossiblyDeferred<Record?> {
    if pending.isEmpty {
      return .immediate(loadResult(forKey: cacheKey))
    }
    return .deferred {
      try await self.flush()
      return try self.loadResult(forKey: cacheKey).get()
    }
  }

  /// Clears all pending and per-key state. Reserved as an escape
  /// hatch for cases that need a full reset; production callers
  /// invalidate selectively (see ``invalidate(keys:)`` and
  /// ``invalidate(matching:)``).
  func removeAll() {
    pending.removeAll()
    state.removeAll()
  }

  /// Drops per-key state and pending field names for `keys` only.
  /// Other keys keep whatever they last observed.
  ///
  /// Called by `ReadWriteTransaction.write(_:withKey:variables:)`
  /// (with the cache keys of the records the merge wrote) and by the
  /// transaction's remove methods, so reads later in the same
  /// transaction see fresh state for the keys whose underlying data
  /// changed — but reads for *unrelated* keys keep their warm
  /// `.loaded`/`.absent` state and do not re-batch on the next ask.
  func invalidate<S: Sequence>(keys: S) where S.Element == CacheKey {
    for key in keys {
      state.removeValue(forKey: key)
      pending.removeValue(forKey: key)
    }
  }

  /// Drops per-key state for every tracked cacheKey whose value
  /// contains `pattern` (case-insensitive). Mirrors
  /// `NormalizedCache.removeRecords(matching:)`'s match semantics so
  /// the loader's invalidated set matches the cache's deleted set
  /// exactly. Untracked keys can't be invalidated — they have no
  /// loader state to drop — and are by definition not in the
  /// short-circuit path.
  func invalidate(matching pattern: CacheKey) {
    guard !pattern.isEmpty else { return }
    let matchingKeys = state.keys.filter {
      $0.range(of: pattern, options: .caseInsensitive) != nil
    }
    invalidate(keys: matchingKeys)
  }

  // MARK: - Private

  /// Returns the `Result<Record?, Error>` for the given key, lifting
  /// a missing key or an `.absent` state to `.success(nil)`. A failure
  /// short-circuits as the recorded error.
  private func loadResult(forKey cacheKey: CacheKey) -> Result<Record?, any Error> {
    switch state[cacheKey] {
    case .none, .some(.absent):           return .success(nil)
    case .some(.loaded(let record, _)):   return .success(record)
    case .some(.failed(let error)):       return .failure(error)
    }
  }

  /// Fires one `batchLoad` covering every currently-pending
  /// projection, then updates `state` to reflect the outcome for each
  /// attempted key and its field names.
  ///
  /// Each returned `Record`'s `fields` is *merged* into any existing
  /// `.loaded` entry under the same key — a prior flush may have
  /// populated a subset of the fields a subsequent projection
  /// requests, and the caller wants to see the union.
  ///
  /// `.absent` and `.failed` are sticky and never updated — a key
  /// that landed in either state during a prior flush short-circuits
  /// at `enqueue` so its fields never reach this loop.
  private func flush() async throws {
    guard !pending.isEmpty else { return }
    let toLoad = pending.map { RecordProjection(cacheKey: $0.key, fieldNames: $0.value) }
    pending.removeAll()

    do {
      let newRecords = try await batchLoad(toLoad)
      for projection in toLoad {
        let cacheKey = projection.cacheKey
        let newRecord = newRecords[cacheKey]

        switch state[cacheKey] {
        case .some(.failed), .some(.absent):
          // Sticky states — should not reach this branch in practice
          // (the fields would have short-circuited at `enqueue`), but
          // coexisting with an already-sticky state is harmless: we
          // just don't update it.
          continue

        case .some(.loaded(var existing, var attempted)):
          if let newRecord {
            existing.fields.merge(newRecord.fields) { _, new in new }
          }
          attempted.formUnion(projection.fieldNames)
          state[cacheKey] = .loaded(existing, attempted: attempted)

        case .none:
          if let newRecord {
            state[cacheKey] = .loaded(newRecord, attempted: projection.fieldNames)
          } else {
            state[cacheKey] = .absent
          }
        }
      }
    } catch {
      // Record the failure for every key that was in this batch so
      // subsequent reads see a consistent error. A key that already
      // has a `.loaded` entry keeps it — only previously un-attempted
      // keys are marked failed.
      for projection in toLoad {
        if state[projection.cacheKey] == nil {
          state[projection.cacheKey] = .failed(error)
        }
      }
      throw error
    }
  }
}
