import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

#warning("TODO: We need a to test to make sure that there is either data or errors in the result?")
class JSONResponseParser_SingleResponseParsingTests: XCTestCase {

  // MARK: Parsing Tests (Extensions)

  func test__parsing__givenExtensionWithEmptyValue_extensionShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "extensions": [:] as JSONValue
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithEmptyValue_andData_extensionShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "data": ["human": NSNull()],
      "extensions": [:] as JSONValue,
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.extensions).to(equal([:]))
  }

  func test__parsing__givenExtensionWithChildValue_extensionShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "data": ["human": NSNull()],
      "extensions": ["parentKey": ["childKey": "someValue"]],
    ] as JSONObject

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.extensions?["parentKey"]).to(equal(["childKey": "someValue"]))
  }

  func test__parsing__givenMissingExtensions_extensionShouldBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "data": ["human": NSNull()]
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.extensions).to(beNil())
  }

  // MARK: Parsing Tests (Errors)

  func test__parsing__givenErrorWithMessage_errorMessageShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "errors": [
        [
          "message": "Some error"
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
  }

  func test__parsing__givenErrorWithLocation_errorLocationShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "errors": [
        [
          "message": "Some error",
          "locations": [
            ["line": 1, "column": 2]
          ]
        ]
      ]
    ] as JSONObject

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.locations?.first?.line).to(equal(1))
    expect(result.errors?.first?.locations?.first?.column).to(equal(2))
  }

  func test__parsing__givenErrorWithPath_errorPathShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "errors": [
        [
          "message": "Some error",
          "path": ["Some field", 1],
        ]
      ] as JSONValue
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?.path?[0]).to(equal(.field("Some field")))
    expect(result.errors?.first?.path?[1]).to(equal(.index(1)))
  }

  func test__parsing__givenErrorWithCustomKey_errorCustomKeyShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "errors": [
        [
          "message": "Some error",
          "userMessage": "Some message",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.errors?.first?.message).to(equal("Some error"))
    expect(result.errors?.first?["userMessage"] as? String).to(equal("Some message"))
  }

  func test__parsing__givenMultipleErrors_shouldReturnAllErrors() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "errors": [
        [
          "message": "Some error"
        ],
        [
          "message": "Another error"
        ],
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<MockSelectionSet>> = try await parser.parseSingleResponse(body: body)
    let result = response.result

    // then
    expect(result.errors?[0].message).to(equal("Some error"))
    expect(result.errors?[1].message).to(equal("Another error"))
  }

  // MARK: - Cache RecordSet Tests

  fileprivate class HeroQueryRoot: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] {
      [
        .field("hero", Hero?.self)
      ]
    }

    var hero: Hero { __data["hero"] }

    class Hero: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("__typename", String.self),
          .field("name", String.self),
        ]
      }

      var name: String { __data["name"] }
    }
  }

  func test__parsing__givenCachePolicyFetchIgnoringCacheCompletely_cacheRecordSetShouldBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: false)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(beNil())
  }

  func test__parsing__givenCachePolicyFetchIgnoringCacheData_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: true)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT.hero",
            [
              "name": "Luke Skywalker",
              "__typename": "Hero",
            ]
          ),
          Record(
            key: "QUERY_ROOT",
            [
              "hero": CacheReference("QUERY_ROOT.hero")
            ]
          ),
        ])
      )
    )
  }

  func test__parsing__givenCachePolicyReturnCacheDataAndFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: true)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT.hero",
            [
              "name": "Luke Skywalker",
              "__typename": "Hero",
            ]
          ),
          Record(
            key: "QUERY_ROOT",
            [
              "hero": CacheReference("QUERY_ROOT.hero")
            ]
          ),
        ])
      )
    )
  }

  func test__parsing__givenCachePolicyReturnCacheDataDontFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: true)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT.hero",
            [
              "name": "Luke Skywalker",
              "__typename": "Hero",
            ]
          ),
          Record(
            key: "QUERY_ROOT",
            [
              "hero": CacheReference("QUERY_ROOT.hero")
            ]
          ),
        ])
      )
    )
  }

  func test__parsing__givenCachePolicyReturnCacheDataElseFetch_cacheRecordSetShouldNotBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: true)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT.hero",
            [
              "name": "Luke Skywalker",
              "__typename": "Hero",
            ]
          ),
          Record(
            key: "QUERY_ROOT",
            [
              "hero": CacheReference("QUERY_ROOT.hero")
            ]
          ),
        ])
      )
    )
  }

  func test__parsing__givenCachePolicyDefault_cacheRecordSetShouldBeNil() async throws {
    // given
    let parser = JSONResponseParser(response: .mock(), operationVariables: nil, includeCacheRecords: true)

    let body = [
      "data": [
        "hero": [
          "__typename": "Hero",
          "name": "Luke Skywalker",
        ]
      ]
    ]

    // when
    let response: ParsedResult<MockQuery<HeroQueryRoot>> = try await parser.parseSingleResponse(body: body)
    let result = response.result
    let recordSet = response.cacheRecords

    // then  
    expect(result.data?.hero.name).to(equal("Luke Skywalker"))
    expect(recordSet).to(
      equal(
        RecordSet(records: [
          Record(
            key: "QUERY_ROOT.hero",
            [
              "name": "Luke Skywalker",
              "__typename": "Hero",
            ]
          ),
          Record(
            key: "QUERY_ROOT",
            [
              "hero": CacheReference("QUERY_ROOT.hero")
            ]
          ),
        ])
      )
    )
  }
}
