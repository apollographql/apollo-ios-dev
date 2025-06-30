import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

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

  // MARK: Mock Query Helpers

  final class CatQuery: MockQuery<CatQuery.CatSelectionSet>, @unchecked Sendable {
    final class CatSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("isJellicle", Bool.self)
        ]
      }
    }
  }

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
