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

  func test__intercept__givenAliasedPathComponent_incrementalRecordsResolveToRealRecord()
    async throws
  {
    // given
    // The container is reached via an aliased field (`pet: animal`), so the incremental path is
    // ["pet"] but the record stores the field under its name `animal`. The resolver must map the
    // response key back to the field's cache key.
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let operation = AliasedAnimalQuery()
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
          "pet": {
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
          Record(key: "QUERY_ROOT", ["animal": CacheReference("Animal:1")]),
          Record(key: "Animal:1", ["__typename": "Animal", "id": "1", "species": "Canis Familiaris"]),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": { "genus": "Canis" },
            "path": ["pet"]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(key: "QUERY_ROOT", ["animal": CacheReference("Animal:1")]),
          Record(
            key: "Animal:1",
            ["__typename": "Animal", "id": "1", "genus": "Canis", "species": "Canis Familiaris"]
          ),
        ])
      )
    )
  }

  func test__intercept__givenArgumentBearingPathComponent_incrementalRecordsResolveToRealRecord()
    async throws
  {
    // given
    // The container is reached via a field with arguments (`animal(kind: "dog")`), so the record
    // stores the field under `animal(kind:dog)` while the path carries the response key `animal`.
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let operation = ArgumentAnimalQuery()
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
          Record(key: "QUERY_ROOT", ["animal(kind:dog)": CacheReference("Animal:1")]),
          Record(key: "Animal:1", ["__typename": "Animal", "id": "1", "species": "Canis Familiaris"]),
        ])
      )
    )

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredGenus",
            "data": { "genus": "Canis" },
            "path": ["animal"]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords).to(
      equal(
        RecordSet(records: [
          Record(key: "QUERY_ROOT", ["animal(kind:dog)": CacheReference("Animal:1")]),
          Record(
            key: "Animal:1",
            ["__typename": "Animal", "id": "1", "genus": "Canis", "species": "Canis Familiaris"]
          ),
        ])
      )
    )
  }

  func test__intercept__givenListIndexPathComponent_withNullSibling_resolvesToRealListElementRecord()
    async throws
  {
    // given
    // A deferred fragment on a list element must resolve through the index to the real `Friend:10`
    // record. The list (stored as `[JSONValue?]`) includes a null sibling to exercise the index
    // branch against the type the normalizer actually stores.
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let operation = AnimalFriendsQuery()
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
            "friends": [
              { "__typename": "Friend", "id": "10" },
              null
            ]
          }
        },
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    _ = try await actualResultsIterator.next()

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredNickname",
            "data": { "nickname": "Buster" },
            "path": ["animal", "friends", 0]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords?["Friend:10"]).to(
      equal(Record(key: "Friend:10", ["__typename": "Friend", "id": "10", "nickname": "Buster"]))
    )
    expect(result2?.cacheRecords?["QUERY_ROOT.animal.friends.0"]).to(beNil())
  }

  func test__intercept__givenMultiHopPath_resolvesAgainstContainerIntroducedByEarlierIncrement()
    async throws
  {
    // given
    // The first increment introduces `friend` (Friend:2); the second increment's path walks through
    // that container, so it must resolve against records the first increment merged in.
    await MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let operation = AnimalNestedFriendQuery()
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
          "animal": { "__typename": "Animal", "id": "1" }
        },
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    _ = try await actualResultsIterator.next()

    // First increment introduces the `friend` container.
    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredFriend",
            "data": {
              "friend": { "__typename": "Friend", "id": "2", "name": "Buster" }
            },
            "path": ["animal"]
          }
        ],
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    let result2 = try await actualResultsIterator.next()
    expect(result2?.cacheRecords?["Friend:2"]).to(
      equal(Record(key: "Friend:2", ["__typename": "Friend", "id": "2", "name": "Buster"]))
    )

    // Second increment resolves against the container the first increment introduced.
    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredNickname",
            "data": { "nickname": "B" },
            "path": ["animal", "friend"]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    let result3 = try await actualResultsIterator.next()
    expect(result3?.cacheRecords?["Friend:2"]).to(
      equal(
        Record(key: "Friend:2", ["__typename": "Friend", "id": "2", "name": "Buster", "nickname": "B"])
      )
    )
    expect(result3?.cacheRecords?["QUERY_ROOT.animal.friend"]).to(beNil())
  }

  func test__intercept__givenAmbiguousPathField_whenIncludingCacheRecords_shouldThrowAmbiguousPathField()
    async throws
  {
    // given
    // `friend` is selected twice with differing arguments, so the response key `friend` maps to two
    // fields with different cache keys. When the deferred path steps through `friend`, its real cache
    // key is ambiguous — that must throw rather than silently fall back to a phantom record.
    let operation = AmbiguousFriendAnimalQuery()
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
            "friend": { "__typename": "Friend", "id": "10" }
          }
        },
        "hasNext": true
      }
      """.data(using: .utf8)!
    )

    _ = try await actualResultsIterator.next()

    streamMocker.emit(
      """
      {
        "incremental": [
          {
            "label": "deferredNickname",
            "data": { "nickname": "Buster" },
            "path": ["animal", "friend"]
          }
        ],
        "hasNext": false
      }
      """.data(using: .utf8)!
    )

    // then
    do {
      _ = try await actualResultsIterator.next()
      fail("Expected IncrementalResponseError.ambiguousPathField to be thrown")
    } catch {
      expect(error as? IncrementalResponseError).to(equal(.ambiguousPathField("friend")))
    }
  }

  // MARK: Mock Query Helpers

  typealias AnimalQuery = MockDeferredAnimalQuery

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

  /// Selects the deferred container via an aliased field (`pet: animal`).
  struct AliasedAnimalQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AliasedAnimalQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredGenus", fieldPath: ["pet"]): AnAnimal.Animal.DeferredGenus.self
      ])
    }

    typealias Data = AnAnimal
    final class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [
          .field("animal", alias: "pet", Animal.self)
        ]
      }

      final class Animal: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("species", String.self),
            .deferred(DeferredGenus.self, label: "deferredGenus"),
          ]
        }

        final class DeferredGenus: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [.field("genus", String.self)]
          }
        }
      }
    }
  }

  /// Selects the deferred container via a field with arguments (`animal(kind: "dog")`).
  struct ArgumentAnimalQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "ArgumentAnimalQuery" }

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
          .field("animal", Animal.self, arguments: ["kind": "dog"])
        ]
      }

      final class Animal: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("species", String.self),
            .deferred(DeferredGenus.self, label: "deferredGenus"),
          ]
        }

        final class DeferredGenus: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [.field("genus", String.self)]
          }
        }
      }
    }
  }

  /// A deferred fragment on the elements of a nullable list (`animal.friends: [Friend?]`).
  struct AnimalFriendsQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AnimalFriendsQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredNickname", fieldPath: ["animal", "friends"]):
          AnAnimal.Animal.Friend.DeferredNickname.self
      ])
    }

    typealias Data = AnAnimal
    final class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [.field("animal", Animal.self)]
      }

      final class Animal: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .field("friends", [Friend?].self),
          ]
        }

        final class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .deferred(DeferredNickname.self, label: "deferredNickname"),
            ]
          }

          final class DeferredNickname: MockTypeCase, @unchecked Sendable {
            override class var __selections: [Selection] {
              [.field("nickname", String.self)]
            }
          }
        }
      }
    }
  }

  /// A deferred fragment nested inside another deferred fragment's container, for multi-hop paths.
  struct AnimalNestedFriendQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AnimalNestedFriendQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["animal"]):
          AnAnimal.Animal.DeferredFriend.self,
        DeferredFragmentIdentifier(label: "deferredNickname", fieldPath: ["animal", "friend"]):
          AnAnimal.Animal.Friend.DeferredNickname.self,
      ])
    }

    typealias Data = AnAnimal
    final class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [.field("animal", Animal.self)]
      }

      final class Animal: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("id", String.self),
            .deferred(DeferredFriend.self, label: "deferredFriend"),
          ]
        }

        final class DeferredFriend: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [.field("friend", Friend.self)]
          }
        }

        final class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .field("name", String.self),
              .deferred(DeferredNickname.self, label: "deferredNickname"),
            ]
          }

          final class DeferredNickname: MockTypeCase, @unchecked Sendable {
            override class var __selections: [Selection] {
              [.field("nickname", String.self)]
            }
          }
        }
      }
    }
  }

  /// Selects `friend` twice with differing arguments, so the response key `friend` maps to two
  /// fields with different cache keys — an ambiguous deferred path container.
  struct AmbiguousFriendAnimalQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "AmbiguousFriendAnimalQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        DeferredFragmentIdentifier(label: "deferredNickname", fieldPath: ["animal", "friend"]):
          AnAnimal.Animal.Friend.DeferredNickname.self
      ])
    }

    typealias Data = AnAnimal
    final class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {
        [.field("animal", Animal.self)]
      }

      final class Animal: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("friend", Friend?.self, arguments: ["kind": "dog"]),
            .field("friend", Friend?.self, arguments: ["kind": "cat"]),
          ]
        }

        final class Friend: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("id", String.self),
              .deferred(DeferredNickname.self, label: "deferredNickname"),
            ]
          }

          final class DeferredNickname: MockTypeCase, @unchecked Sendable {
            override class var __selections: [Selection] {
              [.field("nickname", String.self)]
            }
          }
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
