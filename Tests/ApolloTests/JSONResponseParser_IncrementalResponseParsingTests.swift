@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

final class JSONResponseParser_IncrementalResponseParsingTests: XCTestCase {

  typealias AnimalQuery = MockDeferredAnimalQuery

  var subject: JSONResponseParsingInterceptor!

  override func setUp() {
    super.setUp()
    subject = JSONResponseParsingInterceptor()
  }

  override func tearDown() {
    super.tearDown()
    subject = nil
  }

  // MARK: - Helpers

  private static let initialPartialResponse = """
    {
      "data": {
        "animal": {
          "__typename": "Animal",
          "species": "Canis Familiaris"
        }
      },
      "hasNext": true
    }
    """.data(using: .utf8)!

  /// Sets up the interceptor with a stream mocker, returns the iterator and mocker.
  /// The initial partial response has NOT been emitted yet.
  private func setUpIterator(
    includeCacheRecords: Bool = false
  ) async throws -> (
    iterator: AsyncThrowingStream<ParsedResult<AnimalQuery>, any Error>.AsyncIterator,
    mocker: AsyncStreamMocker<Data>
  ) {
    let operation = AnimalQuery()
    let mocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: mocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: includeCacheRecords
    )
    .getStream()
    .makeAsyncIterator()

    return (iterator, mocker)
  }

  /// Sets up the interceptor, emits the initial partial response, and consumes it.
  /// Returns the iterator (ready for incremental chunks) and mocker.
  private func setUpIteratorWithInitialResponse(
    includeCacheRecords: Bool = false
  ) async throws -> (
    iterator: AsyncThrowingStream<ParsedResult<AnimalQuery>, any Error>.AsyncIterator,
    mocker: AsyncStreamMocker<Data>
  ) {
    var (iterator, mocker) = try await setUpIterator(includeCacheRecords: includeCacheRecords)

    mocker.emit(Self.initialPartialResponse)
    _ = try await iterator.next()

    return (iterator, mocker)
  }

  // MARK: - Error Handling Tests

  func test__parsing__givenIncrementalChunkWithoutPriorPartialResponse__shouldThrowMissingExistingData()
    async throws
  {
    var (iterator, mocker) = try await setUpIterator()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": { "genus": "Canis" },
          "path": ["animal"]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    do {
      _ = try await iterator.next()
      fail("Expected IncrementalResponseError.missingExistingData to be thrown")
    } catch {
      expect(error as? IncrementalResponseError).to(equal(.missingExistingData))
    }
  }

  func test__parsing__givenIncrementalItemMissingPath__shouldThrowMissingPath()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": { "genus": "Canis" }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    do {
      _ = try await iterator.next()
      fail("Expected IncrementalResponseError.missingPath to be thrown")
    } catch {
      expect(error as? IncrementalResponseError).to(equal(.missingPath))
    }
  }

  func test__parsing__givenIncrementalItemMissingLabel__shouldThrowMissingLabel()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "path": ["animal"],
          "data": { "genus": "Canis" }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    do {
      _ = try await iterator.next()
      fail("Expected IncrementalResponseError.missingLabel to be thrown")
    } catch {
      expect(error as? IncrementalResponseError).to(equal(.missingLabel))
    }
  }

  func test__parsing__givenIncrementalItemWithUnrecognizedLabel__shouldThrowMissingDeferredSelectionSetType()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "unknownFragment",
          "path": ["animal"],
          "data": { "key": "value" }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    do {
      _ = try await iterator.next()
      fail("Expected IncrementalResponseError.missingDeferredSelectionSetType to be thrown")
    } catch {
      expect(error as? IncrementalResponseError)
        .to(equal(.missingDeferredSelectionSetType("unknownFragment", "animal")))
    }
  }

  // MARK: - Extensions Tests

  func test__parsing__givenIncrementalItemWithEmptyExtensions__extensionsShouldNotBeNil()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "extensions": {}
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.extensions).toNot(beNil())
    expect(result?.result.extensions).to(equal([:]))
  }

  func test__parsing__givenIncrementalItemWithNestedExtensions__extensionsShouldContainNestedValues()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "extensions": {
            "parentKey": {
              "childKey": "someValue"
            }
          }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.extensions).toNot(beNil())
    expect(result?.result.extensions?["parentKey"] as? [String: String])
      .to(equal(["childKey": "someValue"]))
  }

  func test__parsing__givenIncrementalItemWithMissingExtensions__extensionsShouldBeNil()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.extensions).to(beNil())
  }

  // MARK: - Error Field Parsing Tests

  func test__parsing__givenIncrementalItemWithError__errorMessageShouldBePresent()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "errors": [{ "message": "Some error" }]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.errors?.first?.message).to(equal("Some error"))
    // Data should also be merged despite the error
    expect(result?.result.data?.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
  }

  func test__parsing__givenIncrementalItemWithErrorLocation__errorLocationShouldBePresent()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "errors": [{
            "message": "Some error",
            "locations": [{"line": 1, "column": 2}]
          }]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?.locations?.first?.line).to(equal(1))
    expect(error?.locations?.first?.column).to(equal(2))
  }

  func test__parsing__givenIncrementalItemWithErrorPath__errorPathShouldBePresent()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "errors": [{
            "message": "Some error",
            "path": ["Some field", 1]
          }]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?.path?[0]).to(equal(.field("Some field")))
    expect(error?.path?[1]).to(equal(.index(1)))
  }

  func test__parsing__givenIncrementalItemWithErrorCustomKey__errorCustomKeyShouldBePresent()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "errors": [{
            "message": "Some error",
            "userMessage": "Some message"
          }]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?["userMessage"] as? String).to(equal("Some message"))
  }

  func test__parsing__givenIncrementalItemWithMultipleErrors__shouldReturnAllErrors()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": { "genus": "Canis" },
          "errors": [
            { "message": "Some error" },
            { "message": "Another error" }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.errors).to(haveCount(2))
    expect(result?.result.errors?[0].message).to(equal("Some error"))
    expect(result?.result.errors?[1].message).to(equal("Another error"))
  }

  // MARK: - Edge Case Tests

  func test__parsing__givenEmptyIncrementalArray__shouldReturnUnchangedResult()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse()

    mocker.emit(
      """
      {
        "incremental": [],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    expect(result?.result.data?.animal.species).to(equal("Canis Familiaris"))
    expect(result?.result.data?.animal.fragments.deferredGenus?.genus).to(beNil())
    expect(result?.result.data?.animal.fragments.deferredFriend?.friend).to(beNil())
  }

  // MARK: - Cache Reference Tests

  func test__parsing__givenIncrementalItem__dependentKeysShouldIncludeIncrementalPath()
    async throws
  {
    var (iterator, mocker) = try await setUpIteratorWithInitialResponse(includeCacheRecords: true)

    mocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": { "genus": "Canis" },
          "path": ["animal"]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result = try await iterator.next()
    let dependentKeys = result?.result.dependentKeys
    expect(dependentKeys).toNot(beNil())
    expect(dependentKeys).to(contain(CacheKey("QUERY_ROOT.animal.genus")))
  }
}
