import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class DeferTests: XCTestCase {

  private class TVShowQuery: MockQuery<TVShowQuery.Data> {
    class Data: MockSelectionSet {
      override class var __selections: [Selection] {[
        .field("show", Show.self),
      ]}

      var show: Show { __data["show"] }

      class Show: AbstractMockSelectionSet<Show.Fragments, MockSchemaMetadata> {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("characters", [Character].self),
          .deferred(DeferredGenres.self, label: "deferredGenres"),
        ]}

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

        class DeferredGenres: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("genres", [String].self),
          ]}
        }

        class Character: AbstractMockSelectionSet<Character.Fragments, MockSchemaMetadata> {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self),
            .deferred(DeferredFriend.self, label: "deferredFriend"),
          ]}

          var name: String { __data["name"] }

          struct Fragments: FragmentContainer {
            public let __data: DataDict
            public init(_dataDict: DataDict) {
              __data = _dataDict
              _deferredFriend = Deferred(_dataDict: _dataDict)
            }

            @Deferred var deferredFriend: DeferredFriend?
          }

          class DeferredFriend: MockTypeCase {
            override class var __selections: [Selection] {[
              .field("friend", String.self),
            ]}

            var friend: String { __data["friend"] }
          }
        }
      }
    }

    override class var deferredFragments: [DeferredFragmentIdentifier : any SelectionSet.Type]? {[
      DeferredFragmentIdentifier(label: "deferredGenres", fieldPath: ["show"]): Data.Show.DeferredGenres.self,
      DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["show", "characters"]): Data.Show.Character.DeferredFriend.self,
    ]}
  }

  let defaultTimeout = 0.5

  // MARK: Parsing tests

  private func buildNetworkTransport(
    responseData: Data
  ) -> RequestChainNetworkTransport {
    let client = MockURLSessionClient(
      response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;deferSpec=20220824"]),
      data: responseData
    )

    let provider = MockInterceptorProvider([
      NetworkFetchInterceptor(client: client),
      MultipartResponseParsingInterceptor(),
      IncrementalJSONResponseParsingInterceptor()
    ])

    return RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )
  }

  func test__parsing__givenPartialResponse_shouldReturnSingleSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      
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

    let expectation = expectation(description: "Result received")

    _ = network.send(operation: TVShowQuery()) { result in
      expect(result).to(beSuccess())

      let data = try? result.get().data
      expect(data?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.self),
      ]))
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      expect(show?.name).to(equal("The Scooby-Doo Show"))
      expect(show?.fragments.$deferredGenres).to(equal(.pending))
      expect(show?.fragments.deferredGenres).to(beNil())
      expect(show?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.self),
      ]))
      expect(show?.__data._deferredFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self),
      ]))

      let scoobyDoo = show?.characters[0]
      expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
      expect(scoobyDoo?.fragments.$deferredFriend).to(equal(.pending))
      expect(scoobyDoo?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
      ]))
      expect(scoobyDoo?.__data._deferredFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
      ]))

      let shaggyRogers = show?.characters[1]
      expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
      expect(shaggyRogers?.fragments.$deferredFriend).to(equal(.pending))
      expect(shaggyRogers?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
      ]))
      expect(shaggyRogers?.__data._deferredFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
      ]))

      let velmaDinkley = show?.characters[2]
      expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
      expect(velmaDinkley?.fragments.$deferredFriend).to(equal(.pending))
      expect(velmaDinkley?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
      ]))
      expect(velmaDinkley?.__data._deferredFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
      ]))

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPartialAndIncrementalResponses_withRootMerge_shouldReturnMultipleSuccesses() throws {
    let network = buildNetworkTransport(responseData: """
      
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
        "hasNext": true,
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

    let expectation = expectation(description: "Result received")
    expectation.expectedFulfillmentCount = 2

    _ = network.send(operation: TVShowQuery()) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      let data = try? result.get().data
      expect(data?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.self),
      ]))
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      if expectation.numberOfFulfillments == 0 { // Partial data
        expect(show?.name).to(equal("The Scooby-Doo Show"))
        expect(show?.fragments.$deferredGenres).to(equal(.pending))
        expect(show?.fragments.deferredGenres).to(beNil())
        expect(show?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.self),
        ]))
        expect(show?.__data._deferredFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self),
        ]))

      } else { // Incremental data
        expect(show?.name).to(equal("The Scooby-Doo Show"))
        expect(show?.fragments.deferredGenres?.genres).to(equal([
          "Comedy",
          "Mystery",
          "Adventure"
        ]))
        expect(show?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.self),
          ObjectIdentifier(TVShowQuery.Data.Show.DeferredGenres.self),
        ]))
        expect(show?.__data._deferredFragments).to(beEmpty())
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPartialAndIncrementalResponses_withNestedMerge_shouldReturnMultipleSuccesses() throws {
    let network = buildNetworkTransport(responseData: """
      
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

    let expectation = expectation(description: "Result received")
    expectation.expectedFulfillmentCount = 2

    _ = network.send(operation: TVShowQuery()) { result in
      defer {
        expectation.fulfill()
      }

      expect(result).to(beSuccess())

      let data = try? result.get().data
      expect(data?.__data._fulfilledFragments).to(equal([
        ObjectIdentifier(TVShowQuery.Data.self),
      ]))
      expect(data?.__data._deferredFragments).to(beEmpty())

      let show = data?.show
      if expectation.numberOfFulfillments == 0 { // Partial data
        expect(show?.name).to(equal("The Scooby-Doo Show"))

        let scoobyDoo = show?.characters[0]
        expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
        expect(scoobyDoo?.fragments.$deferredFriend).to(equal(.pending))
        expect(scoobyDoo?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
        ]))
        expect(scoobyDoo?.__data._deferredFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))

        let shaggyRogers = show?.characters[1]
        expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
        expect(shaggyRogers?.fragments.$deferredFriend).to(equal(.pending))
        expect(shaggyRogers?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
        ]))
        expect(shaggyRogers?.__data._deferredFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))

        let velmaDinkley = show?.characters[2]
        expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
        expect(velmaDinkley?.fragments.$deferredFriend).to(equal(.pending))
        expect(velmaDinkley?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
        ]))
        expect(velmaDinkley?.__data._deferredFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))

      } else { // Incremental data
        expect(show?.name).to(equal("The Scooby-Doo Show"))

        let scoobyDoo = show?.characters[0]
        expect(scoobyDoo?.name).to(equal("Scooby-Doo"))
        expect(scoobyDoo?.fragments.deferredFriend?.friend).to(equal("Scrappy-Doo"))
        expect(scoobyDoo?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())

        let shaggyRogers = show?.characters[1]
        expect(shaggyRogers?.name).to(equal("Shaggy Rogers"))
        expect(shaggyRogers?.fragments.deferredFriend?.friend).to(equal("Scooby-Doo"))
        expect(shaggyRogers?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())

        let velmaDinkley = show?.characters[2]
        expect(velmaDinkley?.name).to(equal("Velma Dinkley"))
        expect(velmaDinkley?.fragments.deferredFriend?.friend).to(equal("Daphne Blake"))
        expect(velmaDinkley?.__data._fulfilledFragments).to(equal([
          ObjectIdentifier(TVShowQuery.Data.Show.Character.self),
          ObjectIdentifier(TVShowQuery.Data.Show.Character.DeferredFriend.self),
        ]))
        expect(scoobyDoo?.__data._deferredFragments).to(beEmpty())
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

}
