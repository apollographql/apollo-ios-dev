import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

final class IncrementalGraphQLResponseTests: XCTestCase {

  class DeferredQuery: MockQuery<DeferredQuery.Data> {
    class Data: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata> {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("species", String.self),
          .deferred(DeferredFriend.self, label: "deferredFriend"),
          .deferred(DeliberatelyMissing.self, label: "deliberatelyMissing"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredFriend = Deferred(_dataDict: _dataDict)
            _deliberatelyMissing = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredFriend: DeferredFriend?
          @Deferred var deliberatelyMissing: DeliberatelyMissing?
        }

        class DeferredFriend: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("friend", String.self),
          ]}
        }

        class DeliberatelyMissing: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("key", String.self),
          ]}
        }
      }
    }

    override class var deferredFragments: [DeferredFragmentIdentifier : any SelectionSet.Type]? {[
      DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["animal"]): Data.Animal.DeferredFriend.self,
      // Data.Animal.DeliberatelyMissing is intentionally not here for error testing
    ]}
  }

  // MARK: - Initialization Tests

  func test__error__givenBodyWithMissingPath_whenInitializing_shouldThrow() throws {
    // given + when + then
    expect(try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [:])).to(
      throwError(IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingPath)
    )
  }

  // MARK: - Parsing Tests

  func test__parsing__givenBodyWithMissingLabel_shouldThrow() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: ["path": ["something"]])

    // when + then
    await expect { try await subject.parseIncrementalResult(withCachePolicy: .default) }.to(
      throwError(IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingLabel)
    )
  }

  func test__parsing__givenValidIncrementalBody_withMissingDeferredSelectionSet_shouldThrow() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deliberatelyMissing",
      "path": ["one", "two", "three"],
      "data": [
        "key": "value"
      ]
    ])

    // when + then
    await expect { try await subject.parseIncrementalResult(withCachePolicy: .default) }.to(
      throwError(
        IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingDeferredSelectionSetType(
          "deliberatelyMissing",
          "one.two.three"
        )
      ))
  }

  func test__parsing__givenIncrementalBody_shouldSucceed() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let result = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.0.label).to(equal("deferredFriend"))
    expect(result.0.path).to(equal([PathComponent("animal")]))
    await expect(result.0.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
  }

  // MARK: Parsing Tests (Extensions)

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyFetchIgnoringCacheCompletely_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:]  as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyFetchIgnoringCacheData_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:]  as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataAndFetch_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:]  as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataDontFetch_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataElseFetch_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyDefault_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithChildValue_extensionShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "extensions": ["parentKey": ["childKey": "someValue"]]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.extensions?["parentKey"]).to(equal(["childKey": "someValue"]))
  }

  func test__parsing__givenMissingExtensions_extensionShouldBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.extensions).to(beNil())
  }

  // MARK: Parsing Tests (Errors)

  func test__parsing__givenErrorWithMessage_usingCachePolicyFetchIgnoringCacheCompletely_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyFetchIgnoringCacheData_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataAndFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataDontFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataElseFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyDefault_errorMessageShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithLocation_usingCachePolicyDefault_errorLocationShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
          "locations": [
            ["line": 1, "column": 2]
          ]
        ]
      ] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.locations?.first?.line).to(equal(1))
    expect(result.errors?.first?.locations?.first?.column).to(equal(2))
  }

  func test__parsing__givenErrorWithPath_usingCachePolicyDefault_errorPathShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
          "path": ["Some field", 1]
        ]
      ] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.path?[0]).to(equal(.field("Some field")))
    expect(result.errors?.first?.path?[1]).to(equal(.index(1)))
  }

  func test__parsing__givenErrorWithCustomKey_usingCachePolicyDefault_errorCustomKeyShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error",
          "userMessage": "Some message"
        ]
      ] as JSONValue
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?["userMessage"] as? String).to(equal("Some message"))
  }

  func test__parsing__givenMultipleErrors_shouldReturnAllErrors() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "errors": [
        [
          "message": "Some error"
        ],
        [
          "message": "Another error"
        ]
      ]
    ])

    // when
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    expect(result.errors?[0].message).to(equal("Some error"))
    expect(result.errors?[1].message).to(equal("Another error"))
  }

  // MARK: - Cache RecordSet Tests

  func test__parsing__givenCachePolicyFetchIgnoringCacheCompletely_cacheRecordSetShouldBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(beNil())
  }

  func test__parsing__givenCachePolicyFetchIgnoringCacheData_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.animal", [
        "friend": "Buster"
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataAndFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.animal", [
        "friend": "Buster"
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataDontFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.animal", [
        "friend": "Buster"
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataElseFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.animal", [
        "friend": "Buster"
      ])
    ])))
  }

  func test__parsing__givenCachePolicyDefault_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ])

    // when
    let (result, recordSet) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    // then
    await expect(result.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.animal", [
        "friend": "Buster"
      ])
    ])))
  }

  // MARK: Cache Reference Tests

  func test__cacheReference__givenIncrementalBody_whenParsed_shouldAppendPathToRootCacheReference() async throws {
    // given
    let jsonObject: JSONObject = [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ]
    ]

    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: jsonObject)

    // when + then
    let (result, _) = try await subject.parseIncrementalResult(withCachePolicy: .default)

    expect(result.dependentKeys).to(equal([CacheKey("QUERY_ROOT.animal.friend")]))
  }
}
