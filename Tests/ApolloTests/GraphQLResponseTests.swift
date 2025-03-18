import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class GraphQLResponseTests: XCTestCase {

  // MARK: Parsing Tests (Extensions)

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyFetchIgnoringCacheCompletely_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyFetchIgnoringCacheData_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataAndFetch_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataDontFetch_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyReturnCacheDataElseFetch_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_usingCachePolicyDefault_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_andData_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "data": ["human": NSNull()],
      "extensions": [:] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithChildValue_extensionShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "data": ["human": NSNull()],
      "extensions": ["parentKey": ["childKey": "someValue"]]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.extensions?["parentKey"]).to(equal(["childKey": "someValue"]))
  }

  func test__parsing__givenMissingExtensions_extensionShouldBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "data": ["human": NSNull()]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.extensions).to(beNil())
  }

  // MARK: Parsing Tests (Errors)

  func test__parsing__givenErrorWithMessage_usingCachePolicyFetchIgnoringCacheCompletely_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyFetchIgnoringCacheData_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataAndFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataDontFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyReturnCacheDataElseFetch_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithMessage_usingCachePolicyDefault_errorMessageShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithLocation_errorLocationShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
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
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.locations?.first?.line).to(equal(1))
    expect(result.errors?.first?.locations?.first?.column).to(equal(2))
  }

  func test__parsing__givenErrorWithPath_errorPathShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
          "path": ["Some field", 1]
        ]
      ] as JSONValue
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.path?[0]).to(equal(.field("Some field")))
    expect(result.errors?.first?.path?[1]).to(equal(.index(1)))
  }

  func test__parsing__givenErrorWithCustomKey_errorCustomKeyShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
          "userMessage": "Some message"
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?["userMessage"] as? String).to(equal("Some message"))
  }

  func test__parsing__givenMultipleErrors_shouldReturnAllErrors() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery.mock(), body: [
      "errors": [
        [
          "message": "Some error",
        ],
        [
          "message": "Another error",
        ]
      ]
    ])

    // when
    let (result, _) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.errors?[0].message).to(equal("Some error"))
    expect(result.errors?[1].message).to(equal("Another error"))
  }

  // MARK: - Cache RecordSet Tests

  fileprivate class HeroQuery: MockSelectionSet {
    override class var __selections: [Selection] { [
      .field("hero", Hero?.self),
    ]}

    var hero: Hero { __data["hero"] }

    class Hero: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("name", String.self),
      ]}

      var name: String { __data["name"] }
    }
  }

  func test__parsing__givenCachePolicyFetchIgnoringCacheCompletely_cacheRecordSetShouldBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheCompletely)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(beNil())
  }

  func test__parsing__givenCachePolicyFetchIgnoringCacheData_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .fetchIgnoringCacheData)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "name": "Luke Skywalker",
        "__typename": "Hero"
      ]),
      Record(key: "QUERY_ROOT", [
        "hero": CacheReference("QUERY_ROOT.hero")
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataAndFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .returnCacheDataAndFetch)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "name": "Luke Skywalker",
        "__typename": "Hero"
      ]),
      Record(key: "QUERY_ROOT", [
        "hero": CacheReference("QUERY_ROOT.hero")
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataDontFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .returnCacheDataDontFetch)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "name": "Luke Skywalker",
        "__typename": "Hero"
      ]),
      Record(key: "QUERY_ROOT", [
        "hero": CacheReference("QUERY_ROOT.hero")
      ])
    ])))
  }

  func test__parsing__givenCachePolicyReturnCacheDataElseFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .returnCacheDataElseFetch)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "name": "Luke Skywalker",
        "__typename": "Hero"
      ]),
      Record(key: "QUERY_ROOT", [
        "hero": CacheReference("QUERY_ROOT.hero")
      ])
    ])))
  }

  func test__parsing__givenCachePolicyDefault_cacheRecordSetShouldBeNil() async throws {
    // given
    let response = GraphQLResponse(operation: MockQuery<HeroQuery>(), body: [
      "data": ["hero": [
        "__typename": "Hero",
        "name": "Luke Skywalker"
      ]]
    ])

    // when
    let (result, recordSet) = try await response.parseResult(withCachePolicy: .default)

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(equal(RecordSet(records: [
      Record(key: "QUERY_ROOT.hero", [
        "name": "Luke Skywalker",
        "__typename": "Hero"
      ]),
      Record(key: "QUERY_ROOT", [
        "hero": CacheReference("QUERY_ROOT.hero")
      ])
    ])))
  }
}
