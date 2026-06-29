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

  /// `FieldProjection.init(cacheKey:fieldName:columnShape:cardinality:)`
  /// shorthand — these tests don't care about column shape / cardinality
  /// (they verify the loader's batching contract, not the cache backend's
  /// column projection). `.string` / `.scalar` are arbitrary placeholders.
  private func projection(_ cacheKey: CacheKey, _ fieldName: String) -> FieldProjection {
    FieldProjection(
      cacheKey: cacheKey,
      fieldName: fieldName,
      columnShape: .string,
      cardinality: .scalar
    )
  }

  /// Wraps a batch-load closure with a call-count and per-call key
  /// recording — the projection-layer equivalent of `DataLoaderTests`'
  /// `batchLoads` tracker. The actor isolation keeps the counter race-
  /// free under concurrent `.get()` forces.
  private actor BatchRecorder {
    private(set) var calls: [[FieldProjection]] = []

    func record(_ projections: [FieldProjection]) {
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

    XCTAssertEqual(result?.key, "A")
    XCTAssertEqual(result?["name"] as? String, "Alice")
    let calls = await recorder.calls
    XCTAssertEqual(calls.count, 1, "Exactly one batch fired")
    XCTAssertEqual(calls.first?.count, 1, "Batch carried exactly one projection")
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

    XCTAssertEqual(recordA?["name"] as? String, "Alice")
    XCTAssertEqual(recordB?["name"] as? String, "Bob")
    let calls = await recorder.calls
    XCTAssertEqual(calls.count, 1, "Sibling forces share a single flush")
    XCTAssertEqual(Set(calls.first ?? []), Set([
      projection("A", "name"),
      projection("B", "name"),
    ]))
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
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.count, 1, "Duplicates collapsed inside the batch")
    XCTAssertEqual(calls.first?.first, same)
  }

  func test__enqueue__givenAlreadyLoadedProjection__skipsRebatchingAcrossFlushes() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      // Return values for every projection asked. The second flush
      // should only carry the *new* projection.
      var result: [CacheKey: Record] = [:]
      for projection in projections {
        result[projection.cacheKey, default: Record(key: projection.cacheKey)]
          .fields[projection.fieldName] = CachedField(value: "v_\(projection.fieldName)", writtenAt: 0)
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
    XCTAssertEqual(calls.count, 2, "Two flushes (round 1 + round 2)")
    XCTAssertEqual(
      Set(calls[1]),
      Set([projection("C", "name")]),
      "Round 2 batch carries only the new projection — already-loaded A.name is skipped"
    )
  }

  func test__enqueue__givenSameKeyDifferentFieldAfterFlush__rebatchesTheNewField() async throws {
    let recorder = BatchRecorder()
    let loader = ProjectionLoader { projections in
      await recorder.record(projections)
      var fields: Record.Fields = [:]
      for projection in projections where projection.cacheKey == "A" {
        fields[projection.fieldName] = CachedField(value: "v_\(projection.fieldName)", writtenAt: 0)
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
    XCTAssertEqual(calls.count, 2, "Two flushes — distinct fields on same key still require a new batch")
    XCTAssertEqual(Set(calls[1]), Set([projection("A", "age")]))
    // The loader merges the new field into the existing record entry,
    // so the final result carries both fields.
    XCTAssertEqual(result?["name"] as? String, "v_name")
    XCTAssertEqual(result?["age"] as? String, "v_age")
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
    await assertThrows(TestError.self) {
      _ = try await loader.deferredRecord(forKey: "A").get()
    }

    // Second ask for the same key: should also throw the *same* failure
    // — sticky, no re-batch. `pending` is empty after the flush, so
    // `deferredRecord` returns immediately with the recorded failure.
    await assertThrows(TestError.self) {
      _ = try await loader.deferredRecord(forKey: "A").get()
    }

    let calls = await recorder.calls
    XCTAssertEqual(calls.count, 1, "No re-batch after a recorded failure for the key")
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
    XCTAssertEqual(calls.count, 2, "removeAll forces a re-batch on the next ask")
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
    XCTAssertEqual(calls.count, 2, "Second flush re-batches A but not B")
    XCTAssertEqual(
      Set(calls[1]),
      Set([projection("A", "name")]),
      "Round 2's batch must contain only the invalidated key's projection"
    )
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
    XCTAssertEqual(calls.count, 2, "Invalidation must clear `.absent` so a re-ask re-batches")
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
    XCTAssertEqual(calls.count, 1, "Empty invalidation must not clear unrelated state")
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
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(
      Set(calls[0]),
      Set([projection("B", "name")]),
      "Pending projection for an invalidated key must be dropped before flush"
    )
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
    XCTAssertEqual(calls.count, 2, "Pattern-matched keys re-batch; unmatched keys stay warm")
    XCTAssertEqual(
      Set(calls[1]),
      Set([projection("User:1", "name"), projection("User:2", "name")]),
      "Round 2's batch contains only the pattern-matched keys"
    )
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
    XCTAssertEqual(calls.count, 1, "Empty pattern must not clear any state")
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

    XCTAssertNil(result, "Absent record surfaces as nil, distinct from a thrown error")

    // Repeat-ask short-circuit: the projection was already attempted,
    // so a second enqueue must NOT trigger another batch. This is the
    // semantic the pre-3.0 whole-record loader provided implicitly
    // via `cache[key] = .success(nil)` for absent keys.
    loader.enqueue([projection("MISSING", "name")])
    let secondResult = try await loader.deferredRecord(forKey: "MISSING").get()

    XCTAssertNil(secondResult)
    let calls = await recorder.calls
    XCTAssertEqual(calls.count, 1, "Repeated enqueue of an already-attempted absent key must not re-batch")
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
    XCTAssertEqual(calls.count, 2, "Round 3 must short-circuit — `age` was attempted in round 2")
    XCTAssertEqual(Set(calls[1]), Set([projection("A", "age")]), "Round 2 carries only the new field")
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
    XCTAssertEqual(calls.count, 1, "Absent records must short-circuit on repeated enqueue")
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

    XCTAssertNil(secondResult, "Different field on absent record still surfaces as nil")
    let calls = await recorder.calls
    XCTAssertEqual(
      calls.count,
      1,
      "Absent records are sticky for every field — a different-field probe must not re-batch"
    )
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
    XCTAssertEqual(calls.count, 1, "Mixed-result batch memoizes every attempted key, including absent ones")
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
    XCTAssertEqual(firstA?["name"] as? String, "Alice")

    // Round 2: failed load of B. A's success must persist; B becomes
    // a sticky failure.
    loader.enqueue([projection("B", "name")])
    await assertThrows(TestError.self) {
      _ = try await loader.deferredRecord(forKey: "B").get()
    }

    // A's prior success survives the unrelated failure for B.
    let secondA = try await loader.deferredRecord(forKey: "A").get()
    XCTAssertEqual(secondA?["name"] as? String, "Alice",
                   "Prior success for A must not be overwritten by an unrelated failure for B")

    // B's failure is sticky; no re-batch on repeated ask.
    await assertThrows(TestError.self) {
      _ = try await loader.deferredRecord(forKey: "B").get()
    }

    let calls = await recorder.calls
    XCTAssertEqual(calls.count, 2, "Two flushes total — A's repeat ask short-circuits, B's repeat ask hits the sticky failure")
  }

  // MARK: - Throw helper

  /// Asserts the block throws an error of the given type. Inline because
  /// the project doesn't have a shared `XCTAssertThrowsErrorAsync` helper.
  private func assertThrows<E: Error>(
    _ type: E.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () async throws -> Void
  ) async {
    do {
      try await block()
      XCTFail("Expected throw of \(E.self)", file: file, line: line)
    } catch is E {
      // expected
    } catch {
      XCTFail("Expected \(E.self), got \(error)", file: file, line: line)
    }
  }
}
