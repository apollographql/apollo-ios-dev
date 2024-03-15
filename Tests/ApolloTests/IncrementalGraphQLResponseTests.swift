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

  // MARK: Error Tests

  func test__error__givenBodyWithMissingPath_whenInitializing_shouldThrow() throws {
    // given
    let jsonObject: JSONObject = [:]

    // when + then
    expect(try IncrementalGraphQLResponse(operation: DeferredQuery(), body: jsonObject)).to(
      throwError(IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingPath)
    )
  }

  func test__error__givenBodyWithMissingLabel_whenParsing_shouldThrow() throws {
    // given
    let jsonObject: JSONObject = ["path": ["something"]]

    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: jsonObject)

    // when + then
    expect(try subject.parseIncrementalResult()).to(
      throwError(IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingLabel)
    )
  }

  func test__error__givenValidIncrementalBody_whenParsingWithMissingDeferredSelectionSet_shouldThrow() throws {
    // given
    let jsonObject: JSONObject = [
      "label": "deliberatelyMissing",
      "path": ["one", "two", "three"],
      "data": [
        "key": "value"
      ]
    ]

    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: jsonObject)

    // when + then
    expect(try subject.parseIncrementalResult()).to(
      throwError(IncrementalGraphQLResponse<DeferredQuery>.ResponseError.missingDeferredSelectionSetType("deliberatelyMissing", "one.two.three"))
    )
  }

  // MARK: Cache Reference Tests

  func test__cacheReference__givenIncrementalBody_whenParsed_shouldAppendPathToRootCacheReference() throws {
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
    let actual = try subject.parseIncrementalResult()

    expect(actual.dependentKeys).to(equal([CacheKey("QUERY_ROOT.animal.friend")]))
  }

  // MARK: Parsing Tests

  func test__parsing__givenIncrementalBody_shouldSucceed() throws {
    // given
    let jsonObject: JSONObject = [
      "label": "deferredFriend",
      "path": ["animal"],
      "data": [
        "friend": "Buster"
      ],
      "errors": [
        [
          "message": "Forced error!"
        ]
      ],
      "extensions": [
        "key": "value"
      ]
    ]

    let subject = try IncrementalGraphQLResponse(operation: DeferredQuery(), body: jsonObject)

    // when + then
    let actual = try subject.parseIncrementalResult()

    expect(actual.label).to(equal("deferredFriend"))
    expect(actual.path).to(equal([PathComponent("animal")]))
    expect(actual.data as? DeferredQuery.Data.Animal.DeferredFriend).to(
      equal(try DeferredQuery.Data.Animal.DeferredFriend(data: ["friend": "Buster"]))
    )
    expect(actual.errors).to(equal([
      GraphQLError(["message": "Forced error!"])
    ]))
    expect(actual.extensions).to(equal([
      "key": "value",
    ]))
  }
}
