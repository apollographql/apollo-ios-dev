import Nimble
import XCTest
@_spi(Execution) @testable import Apollo
@_spi(Execution) @_spi(Internal) import ApolloAPI

/// Unit tests for `ProjectionLoader`'s contract — the field-projection
/// batching behavior that replaced the pre-3.0 `DataLoader<CacheKey,
/// Record>`. Mirrors the original `DataLoaderTests` coverage at the
/// projection-aware layer:
///
/// - single load returns the right value
/// - sibling loads collapse into one batch
/// - duplicate projections coalesce within one batch
/// - already-loaded projections short-circuit (no re-fetch)
/// - sticky failures (a failed key fails consistently on repeat asks)
/// - `removeAll()` resets pending and loaded state
final class ProjectionLoaderTests: XCTestCase {

  // MARK: - Helpers

  /// Single-field `RecordProjection` shorthand.
  private func projection(_ cacheKey: CacheKey, _ fieldName: String) -> RecordProjection {
    RecordProjection(
      cacheKey: cacheKey,
      fieldNames: [fieldName]
    )
  }

  /// Wraps a batch-load closure with a call-count and per-call key
  /// recording — the projection-layer equivalent of `DataLoaderTests`'
  /// `batchLoads` tracker. The actor isolation keeps the counter race-
  /// free under concurrent `.get()` forces.
  private actor BatchRecorder {
    private(set) var calls: [[RecordProjection]] = []

    func record(_ projections: [RecordProjection]) {
      calls.append(projections)
    }
  }

  private struct TestError: Error, Equatable {
    let message: String
  }

  // MARK: - Tests

  func test__enqueue__givenSingleProjection__loadsViaBatchAndReturnsRecord() async throws {
    let recorder = BatchRecorder()
    let recordA = Record(key: "A", ["name": "Alice"])
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["A": recordA]
    }

    loader.enqueue([projection("A", "name")])
    let result = try await loader.deferredRecord(forKey: "A").get()

    expect(result?.key) == "A"
    expect(result?["name"] as? String) == "Alice"
    let calls = await recorder.calls
    // Exactly one batch fired with exactly one projection.
    expect(calls).to(haveCount(1))
    expect(calls.first).to(haveCount(1))
  }

  func test__enqueue__givenMultipleDistinctProjectionsForcedTogether__collapseIntoSingleBatchLoad() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return [
        "A": Record(key: "A", ["name": "Alice"]),
        "B": Record(key: "B", ["name": "Bob"]),
      ]
    }

    loader.enqueue([
      projection("A", "name"),
      projection("B", "name"),
    ])

    // Force both deferreds — first force triggers the flush; second
    // finds its key in `loaded` and returns immediately.
    let deferredA = loader.deferredRecord(forKey: "A")
    let deferredB = loader.deferredRecord(forKey: "B")
    let recordA = try await deferredA.get()
    let recordB = try await deferredB.get()

    expect(recordA?["name"] as? String) == "Alice"
    expect(recordB?["name"] as? String) == "Bob"
    let calls = await recorder.calls
    // Sibling forces share a single flush.
    expect(calls).to(haveCount(1))
    expect(Set(calls.first ?? [])) == Set([
      projection("A", "name"),
      projection("B", "name"),
    ])
  }

  func test__enqueue__givenDuplicateProjections__coalescesIntoSingleEntryInBatch() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    // Same projection enqueued multiple times — the loader's `pending`
    // set must dedupe so the batch carries only one copy.
    let same = projection("A", "name")
    loader.enqueue([same, same, same])
    _ = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    expect(calls).to(haveCount(1))
    // Duplicates collapsed inside the batch.
    expect(calls.first).to(haveCount(1))
    expect(calls.first?.first) == same
  }

  func test__enqueue__givenAlreadyLoadedProjection__skipsRebatchingAcrossFlushes() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // Return values for every projection asked. The second flush
      // should only carry the *new* projection.
      var result: [CacheKey: Record] = [:]
      for projection in projections {
        for fieldName in projection.fieldNames {
          result[projection.cacheKey, default: Record(key: projection.cacheKey)]
            .fields[fieldName] = CachedField(value: "v_\(fieldName)", writtenAt: 0)
        }
      }
      return result
    }

    // Round 1: enqueue A.name + B.name, force flush.
    loader.enqueue([projection("A", "name"), projection("B", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    // Round 2: enqueue A.name again + C.name. A.name is already loaded
    // and must be skipped; only C.name should reach the batch.
    loader.enqueue([projection("A", "name"), projection("C", "name")])
    _ = try await loader.deferredRecord(forKey: "C").get()

    let calls = await recorder.calls
    // Two flushes (round 1 + round 2); round 2 batch carries only the
    // new projection — already-loaded A.name is skipped.
    expect(calls).to(haveCount(2))
    expect(Set(calls[1])) == Set([projection("C", "name")])
  }

  func test__enqueue__givenSameKeyDifferentFieldAfterFlush__rebatchesTheNewField() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      var fields: Record.Fields = [:]
      for projection in projections where projection.cacheKey == "A" {
        for fieldName in projection.fieldNames {
          fields[fieldName] = CachedField(value: "v_\(fieldName)", writtenAt: 0)
        }
      }
      return ["A": Record(key: "A", fields: fields)]
    }

    // Round 1: load A.name only.
    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    // Round 2: load A.age — same record key, different field. The
    // record's `loaded` entry holds only `name`; `age` is NOT
    // already-loaded and must be re-batched.
    loader.enqueue([projection("A", "age")])
    let result = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    // Two flushes — distinct fields on same key still require a new batch.
    expect(calls).to(haveCount(2))
    expect(Set(calls[1])) == Set([projection("A", "age")])
    // The loader merges the new field into the existing record entry,
    // so the final result carries both fields.
    expect(result?["name"] as? String) == "v_name"
    expect(result?["age"] as? String) == "v_age"
  }

  func test__deferredRecord__givenBatchLoadFailure__returnsSameFailureOnRepeatedAsk() async throws {
    let recorder = BatchRecorder()
    let failure = TestError(message: "boom")
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      throw failure
    }

    loader.enqueue([projection("A", "name")])

    // First ask: should throw the batch-load failure.
    await expect { _ = try await loader.deferredRecord(forKey: "A").get() }
      .to(throwError(errorType: TestError.self))

    // Second ask for the same key: should also throw the *same* failure
    // — sticky, no re-batch. `pending` is empty after the flush, so
    // `deferredRecord` returns immediately with the recorded failure.
    await expect { _ = try await loader.deferredRecord(forKey: "A").get() }
      .to(throwError(errorType: TestError.self))

    let calls = await recorder.calls
    // No re-batch after a recorded failure for the key.
    expect(calls).to(haveCount(1))
  }

  func test__removeAll__clearsPendingAndLoadedState__allowsRefetch() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    // Round 1: enqueue + flush populates the `loaded` cache.
    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    // Wipe. Subsequent enqueue + ask must re-batch.
    loader.removeAll()

    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    // removeAll forces a re-batch on the next ask.
    expect(calls).to(haveCount(2))
  }

  // MARK: - Selective invalidation

  func test__invalidate_keys__clearsOnlySpecifiedKeys__preservesOthersWarm() async throws {
    // After a write that touches only key A, other reads (B) in the
    // same transaction should keep their warm `.loaded` state and
    // not re-batch. This is the win Option A captures over a blanket
    // `removeAll()`: per-key state survives partial-cache mutation.
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return [
        "A": Record(key: "A", ["name": "Alice"]),
        "B": Record(key: "B", ["name": "Bob"]),
      ]
    }

    // Round 1: load both A and B into `.loaded` state.
    loader.enqueue([projection("A", "name"), projection("B", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()
    _ = try await loader.deferredRecord(forKey: "B").get()

    // Invalidate only A (simulating a write that touched A).
    loader.invalidate(keys: ["A"])

    // Round 2: re-asks must re-batch A (state was cleared) but NOT B
    // (state is still warm). The recorded batch must contain *only*
    // the A projection.
    loader.enqueue([projection("A", "name"), projection("B", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()
    _ = try await loader.deferredRecord(forKey: "B").get()

    let calls = await recorder.calls
    // Second flush re-batches A but not B.
    expect(calls).to(haveCount(2))
    // Round 2's batch must contain only the invalidated key's projection.
    expect(Set(calls[1])) == Set([projection("A", "name")])
  }

  func test__invalidate_keys__givenAbsentKey__allowsRefreshOnNextAsk() async throws {
    // A key in `.absent` state should be re-batched after invalidation
    // — covers the `removeObject(for:)` use case where the cache state
    // for the key changes and the loader's prior absent-observation
    // must not stick.
    var callCount = 0
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      defer { callCount += 1 }
      // First call: empty (cache miss). Second call: empty again
      // (still a miss, but we want to confirm a *re-batch happens*).
      return callCount == 0 ? [:] : [:]
    }

    loader.enqueue([projection("MISSING", "name")])
    _ = try await loader.deferredRecord(forKey: "MISSING").get()

    // Without invalidation, this would short-circuit via `.absent`.
    loader.invalidate(keys: ["MISSING"])

    loader.enqueue([projection("MISSING", "name")])
    _ = try await loader.deferredRecord(forKey: "MISSING").get()

    let calls = await recorder.calls
    // Invalidation must clear `.absent` so a re-ask re-batches.
    expect(calls).to(haveCount(2))
  }

  func test__invalidate_keys__givenEmptyInput__isANoop() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    loader.invalidate(keys: [] as [CacheKey])

    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    // Empty invalidation must not clear unrelated state.
    expect(calls).to(haveCount(1))
  }

  func test__invalidate_keys__alsoDropsPendingProjectionsForThoseKeys() async throws {
    // If a projection for key A is enqueued but the flush hasn't
    // happened yet, an invalidation of A should drop the pending
    // projection too — otherwise the next flush would re-batch a
    // projection whose source-of-truth has been invalidated under us.
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["B": Record(key: "B", ["name": "Bob"])]
    }

    loader.enqueue([projection("A", "name"), projection("B", "name")])
    loader.invalidate(keys: ["A"])

    // The next force should flush only B's projection.
    _ = try await loader.deferredRecord(forKey: "B").get()

    let calls = await recorder.calls
    expect(calls).to(haveCount(1))
    // Pending projection for an invalidated key must be dropped before flush.
    expect(Set(calls[0])) == Set([projection("B", "name")])
  }

  func test__invalidate_matching__clearsKeysContainingPattern_caseInsensitive() async throws {
    // Mirrors `NormalizedCache.removeRecords(matching:)`'s substring,
    // case-insensitive match. Only tracked keys whose value contains
    // `pattern` should be invalidated.
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return [
        "User:1": Record(key: "User:1", ["name": "Alice"]),
        "User:2": Record(key: "User:2", ["name": "Bob"]),
        "Post:1": Record(key: "Post:1", ["title": "Hi"]),
      ]
    }

    loader.enqueue([
      projection("User:1", "name"),
      projection("User:2", "name"),
      projection("Post:1", "title"),
    ])
    _ = try await loader.deferredRecord(forKey: "User:1").get()
    _ = try await loader.deferredRecord(forKey: "User:2").get()
    _ = try await loader.deferredRecord(forKey: "Post:1").get()

    // Invalidate all User: keys via pattern match.
    loader.invalidate(matching: "user")  // lowercase to verify case-insensitive

    // Re-ask all three. Only User:1 and User:2 should re-batch; Post:1
    // stays warm.
    loader.enqueue([
      projection("User:1", "name"),
      projection("User:2", "name"),
      projection("Post:1", "title"),
    ])
    _ = try await loader.deferredRecord(forKey: "User:1").get()
    _ = try await loader.deferredRecord(forKey: "User:2").get()
    _ = try await loader.deferredRecord(forKey: "Post:1").get()

    let calls = await recorder.calls
    // Pattern-matched keys re-batch; unmatched keys stay warm.
    expect(calls).to(haveCount(2))
    // Round 2's batch contains only the pattern-matched keys.
    expect(Set(calls[1])) == Set([
      projection("User:1", "name"),
      projection("User:2", "name"),
    ])
  }

  func test__invalidate_matching__givenEmptyPattern__isANoop() async throws {
    // Matches `removeRecords(matching:)`'s behavior: empty pattern
    // means no-op (rather than "match everything").
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    loader.invalidate(matching: "")

    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    // Empty pattern must not clear any state.
    expect(calls).to(haveCount(1))
  }

  func test__deferredRecord__givenAbsentRecord__returnsNilWithoutThrowing() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // Cache has no record for the requested key — return empty dict.
      return [:]
    }

    loader.enqueue([projection("MISSING", "name")])
    let result = try await loader.deferredRecord(forKey: "MISSING").get()

    // Absent record surfaces as nil, distinct from a thrown error.
    expect(result).to(beNil())

    // Repeat-ask short-circuit: the projection was already attempted,
    // so a second enqueue must NOT trigger another batch. This is the
    // semantic the pre-3.0 whole-record loader provided implicitly
    // via `cache[key] = .success(nil)` for absent keys.
    loader.enqueue([projection("MISSING", "name")])
    let secondResult = try await loader.deferredRecord(forKey: "MISSING").get()

    expect(secondResult).to(beNil())
    let calls = await recorder.calls
    // Repeated enqueue of an already-attempted absent key must not re-batch.
    expect(calls).to(haveCount(1))
  }

  // MARK: - Absence memoization (close the DataLoaderTests.testCachesRepeatedRequests gap)

  func test__enqueue__givenPriorFlushReturnedRecordWithoutTheRequestedField__doesNotRebatchOnRepeatedAsk() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // Cache holds an "A" record with `name` only — never `age`. The
      // loader must remember `age` was *attempted*, even though it's
      // absent from the returned record, so subsequent asks short-
      // circuit instead of re-batching.
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    // Round 1: load `name` (found).
    loader.enqueue([projection("A", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    // Round 2: load `age` (known-missing — record present but field absent).
    loader.enqueue([projection("A", "age")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    // Round 3: ask `age` again. Must NOT re-batch.
    loader.enqueue([projection("A", "age")])
    _ = try await loader.deferredRecord(forKey: "A").get()

    let calls = await recorder.calls
    // Round 3 must short-circuit — `age` was attempted in round 2.
    expect(calls).to(haveCount(2))
    // Round 2 carries only the new field.
    expect(Set(calls[1])) == Set([projection("A", "age")])
  }

  func test__enqueue__givenPriorFlushReturnedAbsentRecord__doesNotRebatchOnRepeatedAsk() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // Cache has no record at all for the requested key.
      return [:]
    }

    // Round 1: load `MISSING.name` — absent record. The loader records
    // the attempt even though `loaded[MISSING]` stays nil.
    loader.enqueue([projection("MISSING", "name")])
    _ = try await loader.deferredRecord(forKey: "MISSING").get()

    // Round 2: ask the same `(cacheKey, fieldName)` again. Must NOT
    // re-batch — repeated probes of an absent key are wasteful.
    loader.enqueue([projection("MISSING", "name")])
    _ = try await loader.deferredRecord(forKey: "MISSING").get()

    let calls = await recorder.calls
    // Absent records must short-circuit on repeated enqueue.
    expect(calls).to(haveCount(1))
  }

  func test__enqueue__givenPriorFlushReturnedAbsentRecord__doesNotRebatchOnAskForDifferentField() async throws {
    // `.absent` is sticky across the rest of the transaction: the
    // read/write lock prevents a concurrent write from surfacing a
    // record under a key we already observed missing, and an
    // intra-transaction write would call `removeAll()` to invalidate
    // all state. So once `(MISSING, name)` returns absent, asking for
    // `(MISSING, age)` must also short-circuit to the same answer —
    // re-batching for a different field on a known-missing record is
    // wasteful, and the cache would return the same "no record" answer
    // regardless.
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      return [:]
    }

    loader.enqueue([projection("MISSING", "name")])
    _ = try await loader.deferredRecord(forKey: "MISSING").get()

    loader.enqueue([projection("MISSING", "age")])
    let secondResult = try await loader.deferredRecord(forKey: "MISSING").get()

    // Different field on absent record still surfaces as nil.
    expect(secondResult).to(beNil())
    let calls = await recorder.calls
    // Absent records are sticky for every field — a different-field
    // probe must not re-batch.
    expect(calls).to(haveCount(1))
  }

  func test__enqueue__givenMixedSuccessAndAbsentInSameBatch__remembersBothForFutureShortCircuit() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // "A" exists with `name`; "B" is absent. The loader must remember
      // both attempts so future enqueues skip both.
      return ["A": Record(key: "A", ["name": "Alice"])]
    }

    loader.enqueue([projection("A", "name"), projection("B", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()
    _ = try await loader.deferredRecord(forKey: "B").get()

    // Both attempts memoized. Re-enqueueing either must not re-batch.
    loader.enqueue([projection("A", "name"), projection("B", "name")])
    _ = try await loader.deferredRecord(forKey: "A").get()
    _ = try await loader.deferredRecord(forKey: "B").get()

    let calls = await recorder.calls
    // Mixed-result batch memoizes every attempted key, including absent ones.
    expect(calls).to(haveCount(1))
  }

  // MARK: - Sticky failure isolation

  func test__deferredRecord__givenBatchFailure__doesNotPoisonPriorSuccessfulKeyLoads() async throws {
    let recorder = BatchRecorder()
    let failure = TestError(message: "boom")
    let callCount = Atomic<Int>(wrappedValue: 0)
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // First call succeeds; subsequent calls throw. Dispatch on the
      // atomic counter so this works under any execution order.
      let current = callCount.increment()
      if current == 1 {
        return ["A": Record(key: "A", ["name": "Alice"])]
      } else {
        throw failure
      }
    }

    // Round 1: successful load of A.
    loader.enqueue([projection("A", "name")])
    let firstA = try await loader.deferredRecord(forKey: "A").get()
    expect(firstA?["name"] as? String) == "Alice"

    // Round 2: failed load of B. A's success must persist; B becomes
    // a sticky failure.
    loader.enqueue([projection("B", "name")])
    await expect { _ = try await loader.deferredRecord(forKey: "B").get() }
      .to(throwError(errorType: TestError.self))

    // A's prior success survives the unrelated failure for B.
    let secondA = try await loader.deferredRecord(forKey: "A").get()
    expect(secondA?["name"] as? String) == "Alice"

    // B's failure is sticky; no re-batch on repeated ask.
    await expect { _ = try await loader.deferredRecord(forKey: "B").get() }
      .to(throwError(errorType: TestError.self))

    let calls = await recorder.calls
    // Two flushes total — A's repeat ask short-circuits, B's repeat
    // ask hits the sticky failure.
    expect(calls).to(haveCount(2))
  }
}
