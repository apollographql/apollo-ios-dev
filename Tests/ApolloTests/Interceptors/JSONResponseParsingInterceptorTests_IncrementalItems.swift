@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable @_spi(Execution) import Apollo

final class JSONResponseParsingInterceptorTests_IncrementalItems: XCTestCase {

  var subject: JSONResponseParsingInterceptor!

  override func setUp() {
    super.setUp()
    subject = JSONResponseParsingInterceptor()
  }

  override func tearDown() {
    super.tearDown()
    subject = nil
  }

  // MARK: - Tests

  func test__intercept__givenSingleIncrementalResult_shouldMergeResult() async throws {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var actualResultsIterator = try await subject.parse(
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

    // then
    let result1 = try await actualResultsIterator.next()
    let graphQLResult = result1?.result
    expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
    expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(beNil())
    expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend).to(beNil())

    // when
    streamMocker.emit(
      """
      {
        "incremental": [{
          "label": "deferredGenus",
          "data": {
            "genus": "Canis"
          },
          "path": [
            "animal"
          ]
        }],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result2 = try await actualResultsIterator.next()
    let graphQLResult2 = result2?.result
    expect(graphQLResult2?.data?.animal.species).to(equal("Canis Familiaris"))
    expect(graphQLResult2?.data?.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
    expect(graphQLResult2?.data?.animal.fragments.deferredFriend?.friend).to(beNil())
  }

  func test__intercept__givenMultipleIncrementalResultsInSingleResponse_shouldMergeResults() async throws {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var actualResultsIterator = try await subject.parse(
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

    // then
    let result1 = try await actualResultsIterator.next()
    let graphQLResult = result1?.result
    expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
    expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(beNil())
    expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend).to(beNil())

    // when
    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": {
              "genus": "Canis"
            },
            "path": [
              "animal"
            ]
          },
          {
            "label": "deferredFriend",
            "data": {
              "friend": {
                "name": "Buster"
              }
            },
            "path": [
              "animal"
            ]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result2 = try await actualResultsIterator.next()
    let graphQLResult2 = result2?.result
    expect(graphQLResult2?.data?.animal.species).to(equal("Canis Familiaris"))
    expect(graphQLResult2?.data?.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
    expect(graphQLResult2?.data?.animal.fragments.deferredFriend?.friend.name).to(equal("Buster"))
  }

  func
    test__intercept__givenMultipleIncrementalObjectsInSingleIncrementalResponse_shouldMergeCacheRecordsForIncrementalResult()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var actualResultsIterator = try await subject.parse(
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

    // then
    let result1 = try await actualResultsIterator.next()
    expect(result1?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("QUERY_ROOT.animal")
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal",
            [
              "__typename": "Animal",
              "species": "Canis Familiaris",
            ]
          ),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": {
              "genus": "Canis"
            },
            "path": [
              "animal"
            ]
          },
          {
            "label": "deferredFriend",
            "data": {
              "friend": {
                "name": "Buster"
              }
            },
            "path": [
              "animal"
            ]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("QUERY_ROOT.animal")
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal",
            [
              "__typename": "Animal",
              "genus": "Canis",
              "species": "Canis Familiaris",
              "friend": CacheReference("QUERY_ROOT.animal.friend"),
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal.friend",
            [
              "name": "Buster"
            ]
          ),
        ])
      )
    )
  }

  func test__intercept__givenMultipleSeperateIncrementalResponses_shouldMergeCacheRecordsForIncrementalResults()
    async throws
  {
    // given
    let operation = AnimalQuery()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var actualResultsIterator = try await subject.parse(
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

    // then
    let result1 = try await actualResultsIterator.next()
    expect(result1?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("QUERY_ROOT.animal")
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal",
            [
              "__typename": "Animal",
              "species": "Canis Familiaris",
            ]
          ),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": {
              "genus": "Canis"
            },
            "path": [
              "animal"
            ]
          }
        ],
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("QUERY_ROOT.animal")
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal",
            [
              "__typename": "Animal",
              "genus": "Canis",
              "species": "Canis Familiaris",
            ]
          ),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredFriend",
            "data": {
              "friend": {
                "name": "Buster"
              }
            },
            "path": [
              "animal"
            ]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    let result3 = try await actualResultsIterator.next()
    expect(result3?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("QUERY_ROOT.animal")
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal",
            [
              "__typename": "Animal",
              "genus": "Canis",
              "species": "Canis Familiaris",
              "friend": CacheReference("QUERY_ROOT.animal.friend"),
            ]
          ),
          Record(
            key: "QUERY_ROOT.animal.friend",
            [
              "name": "Buster"
            ]
          ),
        ])
      )
    )
  }

  func test__intercept__givenIdBasedCacheKey_incrementalRecordsMergeOntoRealRecordNotNaivePath()
    async throws
  {
    // given
    // Normalize `animal` by its `id`, so the initial chunk writes it as `Animal:1`, not `QUERY_ROOT.animal`.
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let operation = AnimalWithIDQuery()
    let streamMocker = AsyncStreamMocker<Data>()

    let urlResponse = HTTPURLResponse.deferResponseMock()

    // when
    var actualResultsIterator = try await subject.parse(
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
            "id": "1",
            "species": "Canis Familiaris"
          }
        },
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    // then
    let result1 = try await actualResultsIterator.next()
    expect(result1?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("Animal:1")
            ]
          ),
          Record(
            key: "Animal:1",
            [
              "__typename": "Animal",
              "id": "1",
              "species": "Canis Familiaris",
            ]
          ),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": {
              "genus": "Canis"
            },
            "path": [
              "animal"
            ]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    // The deferred `path: ["animal"]` must resolve against the initial records to the real `Animal:1`
    // key. With the naive `QUERY_ROOT.animal` join this would land on a phantom record instead, and
    // the merged `Animal:1` record would never receive `genus`.
    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT",
            [
              "animal": CacheReference("Animal:1")
            ]
          ),
          Record(
            key: "Animal:1",
            [
              "__typename": "Animal",
              "id": "1",
              "genus": "Canis",
              "species": "Canis Familiaris",
            ]
          ),
        ])
      )
    )
  }

  // MARK: Mock Query Helpers

  typealias AnimalQuery = MockDeferredAnimalQuery

  /// Like ``MockDeferredAnimalQuery`` but selects `id` on `animal` so it normalizes by an id-based
  /// cache key when `cacheKeyInfo` is configured. Used to verify deferred paths resolve to the real
  /// record key rather than the naive `QUERY_ROOT.<path>` join.
  struct AnimalWithIDQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AnimalWithIDQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredGenus", fieldPath: ["animal"]): AnAnimal.Animal.DeferredGenus.self
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
            .field("id", String.self),
            .field("species", String.self),
            .deferred(DeferredGenus.self, label: "deferredGenus"),
          ]
        }

        var species: String { __data["species"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredGenus = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredGenus: DeferredGenus?
        }

        final class DeferredGenus: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("genus", String.self)
            ]
          }

          var genus: String { __data["genus"] }
        }
      }
    }
  }

  final class CatQuery: MockQuery<CatQuery.CatSelectionSet>, @unchecked Sendable {
    final class CatSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("isJellicle", Bool.self)
        ]
      }
    }
  }
}
