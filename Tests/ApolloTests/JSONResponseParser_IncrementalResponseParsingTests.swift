@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

final class JSONResponseParser_IncrementalResponseParsingTests: XCTestCase {

  var subject: JSONResponseParsingInterceptor!

  override func setUp() {
    super.setUp()
    subject = JSONResponseParsingInterceptor()
  }

  override func tearDown() {
    super.tearDown()
    subject = nil
  }

  // MARK: - Error Handling Tests

  func test__parsing__givenIncrementalChunkWithoutPriorPartialResponse__shouldThrowMissingExistingData()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    // Send an incremental chunk without sending an initial partial response first
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": {
            "genus": "Canis"
          },
          "path": ["animal"]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
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
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    // Send initial partial response
    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when - send incremental item without "path"
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": {
            "genus": "Canis"
          }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
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
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    // Send initial partial response
    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when - send incremental item without "label"
    streamMocker.emit(
      """
      {
        "incremental": [{
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
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
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    // Send initial partial response
    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when - send incremental item with a label not registered in responseFormat
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "unknownFragment",
          "path": ["animal"],
          "data": {
            "key": "value"
          }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
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
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "extensions": {}
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    expect(result?.result.extensions).toNot(beNil())
    expect(result?.result.extensions).to(equal([:]))
  }

  func test__parsing__givenIncrementalItemWithNestedExtensions__extensionsShouldContainNestedValues()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
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

    // then
    let result = try await iterator.next()
    expect(result?.result.extensions).toNot(beNil())
    expect(result?.result.extensions?["parentKey"] as? [String: String])
      .to(equal(["childKey": "someValue"]))
  }

  func test__parsing__givenIncrementalItemWithMissingExtensions__extensionsShouldBeNil()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          }
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    expect(result?.result.extensions).to(beNil())
  }

  // MARK: - Error Field Parsing Tests

  func test__parsing__givenIncrementalItemWithError__errorMessageShouldBePresent()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "errors": [
            {
              "message": "Some error"
            }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    expect(result?.result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenIncrementalItemWithErrorLocation__errorLocationShouldBePresent()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "errors": [
            {
              "message": "Some error",
              "locations": [
                {"line": 1, "column": 2}
              ]
            }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?.locations?.first?.line).to(equal(1))
    expect(error?.locations?.first?.column).to(equal(2))
  }

  func test__parsing__givenIncrementalItemWithErrorPath__errorPathShouldBePresent()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "errors": [
            {
              "message": "Some error",
              "path": ["Some field", 1]
            }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?.path?[0]).to(equal(.field("Some field")))
    expect(error?.path?[1]).to(equal(.index(1)))
  }

  func test__parsing__givenIncrementalItemWithErrorCustomKey__errorCustomKeyShouldBePresent()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "errors": [
            {
              "message": "Some error",
              "userMessage": "Some message"
            }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    let error = result?.result.errors?.first
    expect(error?.message).to(equal("Some error"))
    expect(error?["userMessage"] as? String).to(equal("Some message"))
  }

  func test__parsing__givenIncrementalItemWithMultipleErrors__shouldReturnAllErrors()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: false
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "path": ["animal"],
          "data": {
            "genus": "Canis"
          },
          "errors": [
            {
              "message": "Some error"
            },
            {
              "message": "Another error"
            }
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    expect(result?.result.errors).to(haveCount(2))
    expect(result?.result.errors?[0].message).to(equal("Some error"))
    expect(result?.result.errors?[1].message).to(equal("Another error"))
  }

  // MARK: - Cache Reference Tests

  func test__parsing__givenIncrementalItem__dependentKeysShouldIncludeIncrementalPath()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()
    let urlResponse = HTTPURLResponse.deferResponseMock()

    var iterator = try await subject.parse(
      response: HTTPResponse(
        response: urlResponse,
        chunks: streamMocker.getStream()
      ),
      for: JSONRequest.mock(operation: operation, fetchBehavior: .NetworkOnly),
      includeCacheRecords: true
    )
    .getStream()
    .makeAsyncIterator()

    streamMocker.emit(
      """
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
    )

    _ = try await iterator.next()

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": {
            "genus": "Canis"
          },
          "path": ["animal"]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result = try await iterator.next()
    let dependentKeys = result?.result.dependentKeys
    expect(dependentKeys).toNot(beNil())
    expect(dependentKeys).to(contain(CacheKey("QUERY_ROOT.animal.genus")))
  }

  // MARK: - Mock Query Helpers

  struct AnimalQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AnimalQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredGenus", fieldPath: ["animal"]): AnAnimal.Animal.DeferredGenus.self,
        DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["animal"]): AnAnimal.Animal.DeferredFriend.self,
      ])
    }

    typealias Data = AnAnimal
    final class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("animal", Animal.self)
        ]
      }

      var animal: Animal { __data["animal"] }

      final class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("species", String.self),
            .deferred(DeferredGenus.self, label: "deferredGenus"),
            .deferred(DeferredFriend.self, label: "deferredFriend"),
          ]
        }

        var species: String { __data["species"] }

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredGenus = Deferred(_dataDict: _dataDict)
            _deferredFriend = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredGenus: DeferredGenus?
          @Deferred var deferredFriend: DeferredFriend?
        }

        final class DeferredGenus: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("genus", String.self)
            ]
          }

          var genus: String { __data["genus"] }
        }

        final class DeferredFriend: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("friend", Friend.self)
            ]
          }

          var friend: Friend { __data["friend"] }

          final class Friend: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {
              [
                .field("name", String.self)
              ]
            }

            var name: String { __data["name"] }
          }
        }
      }
    }
  }
}
