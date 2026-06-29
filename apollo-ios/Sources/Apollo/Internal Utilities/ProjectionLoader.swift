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
/// pending and per-key state — called after a write so subsequent
/// reads within the same transaction observe fresh data.
final class ProjectionLoader {
  typealias BatchLoad = ([FieldProjection]) async throws -> [CacheKey: Record]

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
  /// - ``absent`` — the cache had no record for this key. Sticky for
  ///   the rest of the transaction: the read/write lock guarantees no
  ///   concurrent writes can surface a record under a key we already
  ///   observed missing, and an intra-transaction write calls
  ///   `removeAll()` to invalidate every entry. So every subsequent
  ///   field projection on this key — same field or different — must
  ///   short-circuit to the same "absent" answer; tracking which
  ///   fields were attempted would add no information.
  /// - ``failed(_:)`` — a prior flush threw for this key. Sticky for
  ///   the same lock-driven reason as `.absent`: every subsequent
  ///   projection on this key short-circuits as the same failure via
  ///   `loadResult(forKey:)`.
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

  /// Projections waiting to be flushed on the next force.
  private var pending: Set<FieldProjection> = []

  /// Per-cacheKey post-flush state. See ``KeyState`` for the four
  /// states this map encodes and how they replace the prior
  /// two-dictionary representation.
  private var state: [CacheKey: KeyState] = [:]

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

  /// Clears all pending and per-key state. Called after a write
  /// transaction merge so subsequent reads observe the updated data.
  func removeAll() {
    pending.removeAll()
    state.removeAll()
  }

  // MARK: - Private

  /// True iff a prior flush has already *attempted* to load this
  /// projection's `(cacheKey, fieldName)` pair — covering all
  /// post-flush states for the field:
  ///
  /// - **Found:** the cache returned a record containing this field.
  ///   The state is `.loaded(record, attempted: { fieldName, … })`.
  /// - **Known missing:** the cache returned a record for this key
  ///   but without this field. The state is
  ///   `.loaded(record, attempted: { fieldName, … })` and the field
  ///   is absent from `record.fields`.
  /// - **Absent record:** the cache had no record for this key at
  ///   all. The state is `.absent`, which short-circuits every field
  ///   on the key — same field, different field, doesn't matter.
  /// - **Sticky failure:** a prior flush threw for this key. The
  ///   state is `.failed(error)` and every subsequent projection on
  ///   this key short-circuits as the same failure via
  ///   `loadResult(forKey:)`.
  ///
  /// Short-circuiting in every post-attempt case avoids re-batching
  /// known-missing fields and known-absent records on repeated
  /// enqueue — a behavior the pre-3.0 whole-record `DataLoader`
  /// provided implicitly via `cache[key] = .success(nil)` for absent
  /// keys.
  private func isAlreadyLoaded(_ projection: FieldProjection) -> Bool {
    state[projection.cacheKey]?.hasAttempted(projection.fieldName) ?? false
  }

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
  /// attempted `(cacheKey, fieldName)` pair.
  ///
  /// Each returned `Record`'s `fields` is *merged* into any existing
  /// `.loaded` entry under the same key — a prior flush may have
  /// populated a subset of the fields a subsequent projection
  /// requests, and the caller wants to see the union.
  ///
  /// `.absent` and `.failed` are sticky and never updated — a key
  /// that landed in either state during a prior flush short-circuits
  /// at `enqueue` so its projections never reach this loop.
  private func flush() async throws {
    guard !pending.isEmpty else { return }
    let toLoad = Array(pending)
    pending.removeAll()

    do {
      let newRecords = try await batchLoad(toLoad)
      for projection in toLoad {
        let cacheKey = projection.cacheKey
        let fieldName = projection.fieldName
        let newRecord = newRecords[cacheKey]

        switch state[cacheKey] {
        case .some(.failed), .some(.absent):
          // Sticky states — should not reach this branch in practice
          // (the projection would have short-circuited at `enqueue`),
          // but coexisting with an already-sticky state is harmless:
          // we just don't update it.
          continue

        case .some(.loaded(var existing, var attempted)):
          if let newRecord {
            existing.fields.merge(newRecord.fields) { _, new in new }
          }
          attempted.insert(fieldName)
          state[cacheKey] = .loaded(existing, attempted: attempted)

        case .none:
          if let newRecord {
            state[cacheKey] = .loaded(newRecord, attempted: [fieldName])
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
