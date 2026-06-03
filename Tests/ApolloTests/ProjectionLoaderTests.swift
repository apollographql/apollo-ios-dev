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

  func test__deferredRecord__givenAbsentRecord__returnsNilWithoutThrowing() async throws {
    let loader = ProjectionLoader { _ in
      // Cache has no record for the requested key — return empty dict.
      return [:]
    }

    loader.enqueue([projection("MISSING", "name")])
    let result = try await loader.deferredRecord(forKey: "MISSING").get()

    XCTAssertNil(result, "Absent record surfaces as nil, distinct from a thrown error")
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
