import ApolloAPI
import ApolloInternalTestHelpers
import Nimble
import XCTest

@testable import Apollo

final class DeferTests: XCTestCase, MockResponseProvider {

  var network: RequestChainNetworkTransport!

  override func setUp() async throws {
    try await super.setUp()
    let session = MockURLSession(responseProvider: Self.self)

    let provider = MockProvider(
      interceptors: [
        JSONResponseParsingInterceptor()
      ],
      urlSession: session
    )

    self.network = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )
  }

  override func tearDown() async throws {
    await Self.cleanUpRequestHandlers()
    self.network = nil
    try await super.tearDown()
  }

  private struct MockProvider: MockInterceptorProvider {
    let interceptors: [any ApolloInterceptor]
    let urlSession: MockURLSession

    func interceptors<Operation>(for operation: Operation) -> [any ApolloInterceptor]
    where Operation: GraphQLOperation {
      return interceptors
    }
  }

  private struct TVShowQuery: GraphQLQuery, @unchecked Sendable {
    static var operationName: String { "TVShowQuery" }

    static var operationDocument: OperationDocument {
      .init(definition: .init("Mock Operation Definition"))
    }

    static var responseFormat: IncrementalDeferredResponseFormat {
      IncrementalDeferredResponseFormat(deferredFragments: [
        .init(label: "deferredGenres", fieldPath: ["show"]): Data.Show.DeferredGenres.self,
        .init(label: "deferredFriend", fieldPath: ["show", "characters"]): Data.Show.Character.DeferredFriend.self,
      ])
    }

    public var __variables: Variables?

    final class Data: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {
        [
          .field("show", Show.self)
        ]
      }

      var show: Show { __data["show"] }

      final class Show: AbstractMockSelectionSet<Show.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {
          [
            .field("__typename", String.self),
            .field("name", String.self),
            .field("characters", [Character].self),
            .deferred(DeferredGenres.self, label: "deferredGenres"),
          ]
        }

        var name: String { __data["name"] }
        var characters: [Character] { __data["characters"] }

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredGenres = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredGenres: DeferredGenres?
        }

        final class DeferredGenres: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("genres", [String].self)
            ]
          }

          var genres: [String] { __data["genres"] }
        }

        final class Character: AbstractMockSelectionSet<Character.Fragments, MockSchemaMetadata>, @unchecked Sendable {
          override class var __selections: [Selection] {
            [
              .field("__typename", String.self),
              .field("name", String.self),
              .deferred(DeferredFriend.self, label: "deferredFriend"),
            ]
          }

          var name: String { __data["name"] }

          struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) {
              __data = _dataDict
              _deferredFriend = Deferred(_dataDict: _dataDict)
            }

            @Deferred var deferredFriend: DeferredFriend?
          }

          final class DeferredFriend: MockTypeCase, @unchecked Sendable {
            override class var __selections: [Selection] {
              [
                .field("friend", String.self)
              ]
            }

            var friend: String { __data["friend"] }
          }
        }
      }
    }
  }

  let defaultTimeout = 0.5

  // MARK: Parsing tests

  private func registerRequestHandler(
    responseData: Data,
    multipartBoundary boundary: String = "graphql"
  ) async {
    await Self.registerRequestHandler(for: network.endpointURL) { request in
      return (
        .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=\(boundary);deferSpec=20220824"]),
        responseData
      )
    }
  }

  func test__parsing__givenPartialResponse_shouldReturnSingleSuccess() async throws {
    await registerRequestHandler(
      responseData: """

        --graphql
        content-type: application/json

        {
          "hasNext": true,
          "data": {
            "show" : {
              "__typename": "show",
              "name": "The Scooby-Doo Show",
              "characters": [
                {
                  "__typename": "Character",
                  "name": "Scooby-Doo"
                },
                {
                  "__typename": "Character",
                  "name": "Shaggy Rogers"
                },
                {
                  "__typename": "Character",
                  "name": "Velma Dinkley"
                }
              ]
            }
          }
        }
        --graphql--
        """.crlfFormattedData()
    )

    let results = try await network.send(query: TVShowQuery(), cachePolicy: .fetchIgnoringCacheCompletely)
      .getAllValues()

    expect(results.count).to(equal(1))

    let response = results.first
    let data = response?.data

    expect(data?.__data._fulfilledFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.self)
      ])
    )
    expect(data?.__data._deferredFragments).to(beEmpty())

    let show = data?.show
    expect(show?.name).to(equal("The Scooby-Doo Show"))
    expect(show?.fragments.$deferredGenres).to(equal(.pending))
    expect(show?.fragments.deferredGenres).to(beNil())
    expect(show?.__data._fulfilledFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.self)
      ])
    )
    expect(show?.__data._deferredFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self)
      ])
    )

    let scoobyDoo = show?.characters[0]
    expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
    expect(scoobyDoo?.fragments.$deferredFriend).to(equal(.pending))
    expect(scoobyDoo?.__data._fulfilledFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
      ])
    )
    expect(scoobyDoo?.__data._deferredFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
      ])
    )

    let shaggyRogers = show?.characters[1]
    expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
    expect(shaggyRogers?.fragments.$deferredFriend).to(equal(.pending))
    expect(shaggyRogers?.__data._fulfilledFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
      ])
    )
    expect(shaggyRogers?.__data._deferredFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
      ])
    )

    let velmaDinkley = show?.characters[2]
    expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
    expect(velmaDinkley?.fragments.$deferredFriend).to(equal(.pending))
    expect(velmaDinkley?.__data._fulfilledFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
      ])
    )
    expect(velmaDinkley?.__data._deferredFragments).to(
      equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
      ])
    )
  }

  func test__parsing__givenPartialAndIncrementalResponses_withRootMerge_shouldReturnMultipleSuccesses() async throws {
    await registerRequestHandler(
      responseData: """

        --graphql
        content-type: application/json

        {
          "hasNext": true,
          "data": {
            "show" : {
              "__typename": "show",
              "name": "The Scooby-Doo Show",
              "characters": [
                {
                  "__typename": "Character",
                  "name": "Scooby-Doo"
                },
                {
                  "__typename": "Character",
                  "name": "Shaggy Rogers"
                },
                {
                  "__typename": "Character",
                  "name": "Velma Dinkley"
                }
              ]
            }
          }
        }
        --graphql
        content-type: application/json

        {
          "hasNext": false,
          "incremental": [
            {
              "label": "deferredGenres",
              "path": [
                "show"
              ],
              "data": {
                "genres": [
                  "Comedy",
                  "Mystery",
                  "Adventure"
                ]
              }
            }
          ]
        }
        --graphql--
        """.crlfFormattedData()
    )

    var responseCount = 0

    for try await response in try network.send(query: TVShowQuery(), cachePolicy: .fetchIgnoringCacheCompletely) {
      responseCount += 1

      let data = response.data

      expect(data?.__data._fulfilledFragments).to(
        equal([
          ObjectIdentifier(TVShowQuery.Data.self)
        ])
      )
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      if responseCount == 1 {  // Partial data
        expect(show?.name).to(equal("The Scooby-Doo Show"))
        expect(show?.fragments.$deferredGenres).to(equal(.pending))
        expect(show?.fragments.deferredGenres).to(beNil())
        expect(show?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.self)
          ])
        )
        expect(show?.__data._deferredFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self)
          ])
        )

      } else {  // Incremental data
        expect(show?.name).to(equal("The Scooby-Doo Show"))
        expect(show?.fragments.deferredGenres?.genres).to(
          equal([
            "Comedy",
            "Mystery",
            "Adventure",
          ])
        )
        expect(show?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.self),
            ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self),
          ])
        )
        expect(show?.__data._deferredFragments).to(beEmpty())
      }
    }

    expect(responseCount).to(equal(2))
  }

  func test__parsing__givenPartialAndIncrementalResponses_withNestedMerge_shouldReturnMultipleSuccesses() async throws {
    await registerRequestHandler(
      responseData: """

        --graphql
        content-type: application/json

        {
          "hasNext": true,
          "data": {
            "show" : {
              "__typename": "show",
              "name": "The Scooby-Doo Show",
              "characters": [
                {
                  "__typename": "Character",
                  "name": "Scooby-Doo"
                },
                {
                  "__typename": "Character",
                  "name": "Shaggy Rogers"
                },
                {
                  "__typename": "Character",
                  "name": "Velma Dinkley"
                }
              ]
            }
          }
        }
        --graphql
        content-type: application/json

        {
          "hasNext": false,
          "incremental": [
            {
              "label": "deferredFriend",
              "path": [
                "show", "characters", 0
              ],
              "data": {
                "friend": "Scrappy-Doo"
              }
            },
            {
              "label": "deferredFriend",
              "path": [
                "show", "characters", 1
              ],
              "data": {
                "friend": "Scooby-Doo"
              }
            },
            {
              "label": "deferredFriend",
              "path": [
                "show", "characters", 2
              ],
              "data": {
                "friend": "Daphne Blake"
              }
            }
          ]
        }
        --graphql--
        """.crlfFormattedData()
    )

    var requestCount = 0

    for try await response in try network.send(query: TVShowQuery(), cachePolicy: .fetchIgnoringCacheCompletely) {
      requestCount += 1

      let data = response.data
      expect(data?.__data._fulfilledFragments).to(
        equal([
          ObjectIdentifier(TVShowQuery.Data.self)
        ])
      )
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      if requestCount == 1 {  // Partial data
        expect(show?.name).to(equal("The Scooby-Doo Show"))

        let scoobyDoo = show?.characters[0]
        expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
        expect(scoobyDoo?.fragments.$deferredFriend).to(equal(.pending))
        expect(scoobyDoo?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
          ])
        )
        expect(scoobyDoo?.__data._deferredFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
          ])
        )

        let shaggyRogers = show?.characters[1]
        expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
        expect(shaggyRogers?.fragments.$deferredFriend).to(equal(.pending))
        expect(shaggyRogers?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
          ])
        )
        expect(shaggyRogers?.__data._deferredFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
          ])
        )

        let velmaDinkley = show?.characters[2]
        expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
        expect(velmaDinkley?.fragments.$deferredFriend).to(equal(.pending))
        expect(velmaDinkley?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self)
          ])
        )
        expect(velmaDinkley?.__data._deferredFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self)
          ])
        )

      } else {  // Incremental data
        expect(show?.name).to(equal("The Scooby-Doo Show"))

        let scoobyDoo = show?.characters[0]
        expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
        expect(scoobyDoo?.fragments.deferredFriend?.friend).to(equal("Scrappy-Doo"))
        expect(scoobyDoo?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
          ])
        )
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())

        let shaggyRogers = show?.characters[1]
        expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
        expect(shaggyRogers?.fragments.deferredFriend?.friend).to(equal("Scooby-Doo"))
        expect(shaggyRogers?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
          ])
        )
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())

        let velmaDinkley = show?.characters[2]
        expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
        expect(velmaDinkley?.fragments.deferredFriend?.friend).to(equal("Daphne Blake"))
        expect(velmaDinkley?.__data._fulfilledFragments).to(
          equal([
            ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
            ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
          ])
        )
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())
      }
    }

    expect(requestCount).to(equal(2))
  }

  func test__parsing__givenPartialAndIncrementalResponses_withDashBoundaryInMessageBody_shouldNotSplitChunk()
    async throws
  {
    let multipartBoundary = "-"
    let mysteryCharacterName =
      "lots\(multipartBoundary)of-\(multipartBoundary)similar--\(multipartBoundary)boundaries---\(multipartBoundary)in----\(multipartBoundary)this-----\(multipartBoundary)string"

    await registerRequestHandler(
      responseData: """

        --\(multipartBoundary)
        content-type: application/json

        {
          "hasNext": true,
          "data": {
            "show" : {
              "__typename": "show",
              "name": "The Scooby-Doo Show",
              "characters": [
                {
                  "__typename": "Character",
                  "name": "Scooby-Doo"
                },
                {
                  "__typename": "Character",
                  "name": "Shaggy Rogers"
                },
                {
                  "__typename": "Character",
                  "name": "Velma Dinkley"
                },
                {
                  "__typename": "Character",
                  "name": "\(mysteryCharacterName)"
                }
              ]
            }
          }
        }
        --\(multipartBoundary)
        content-type: application/json

        {
          "hasNext": false,
          "incremental": [
            {
              "label": "deferredGenres",
              "path": [
                "show"
              ],
              "data": {
                "genres": [
                  "Comedy",
                  "Mystery",
                  "Adventure"
                ]
              }
            }
          ]
        }
        --\(multipartBoundary)--
        """.crlfFormattedData(),
      multipartBoundary: multipartBoundary
    )

    var requestCount = 0

    for try await response in try network.send(query: TVShowQuery(), cachePolicy: .fetchIgnoringCacheCompletely) {
      requestCount += 1

      let data = response.data
      expect(data?.__data._fulfilledFragments).to(
        equal([
          ObjectIdentifier(TVShowQuery.Data.self)
        ])
      )
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      if requestCount == 1 {  // Partial data
        expect(show?.characters).to(haveCount(4))

        let mysteryCharacter = show?.characters[3]
        expect(mysteryCharacter?.name).to(equal(mysteryCharacterName))
      }
    }

    expect(requestCount).to(equal(2))
  }

}
