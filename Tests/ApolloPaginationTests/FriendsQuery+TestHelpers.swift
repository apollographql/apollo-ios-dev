import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

extension Mocks.Hero.FriendsQuery {
  static func expectationForFirstPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMg==",
        "hasNextPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }

  static func expectationForSecondPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": "Y3Vyc29yMg=="]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMw==",
        "hasNextPage": false,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }

  static func expectationForFirstPageWithErrors(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "endCursor": "Y3Vyc29yMg==",
        "hasNextPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue,
        "errors": [
          [
            "message": "uh oh!"
          ],
          [
            "message": "Some error"
          ],
        ],
      ]
    }
  }

  static func expectationForFirstPageErrorsOnly(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return await server.expect(query) { _ in
      return [
        "errors": [
          [
            "message": "uh oh!"
          ],
          [
            "message": "Some error"
          ],
        ],
      ]
    }
  }

  static func expectationForSecondPageErrorsOnly(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": "Y3Vyc29yMg=="]
    return await server.expect(query) { _ in
      return [
        "errors": [
          [
            "message": "uh oh!"
          ],
          [
            "message": "Some error"
          ],
        ],
      ]
    }
  }
}

extension Mocks.Hero.ReverseFriendsQuery {
  static func expectationForPreviousItem(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.ReverseFriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMg=="]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "startCursor": "Y3Vyc29yZg==",
        "hasPreviousPage": false,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }
  static func expectationForLastItem(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.ReverseFriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "startCursor": "Y3Vyc29yMg==",
        "hasPreviousPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }
}

extension Mocks.Hero.BidirectionalFriendsQuery {
  static func expectationForFirstFetchInMiddleOfList(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "before": GraphQLNullable<String>.null, "after": "Y3Vyc29yMw=="]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "startCursor": "Y3Vyc29yMw==",
        "hasPreviousPage": true,
        "endCursor": "Y3Vyc29yMg==",
        "hasNextPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]
      let friendsConnection = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }

  static func expectationForLastPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "after": "Y3Vyc29yMg==", "before": GraphQLNullable<String>.null]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "startCursor": "Y3Vyc29yMg==",
        "hasPreviousPage": true,
        "endCursor": "Y3Vyc29yMa==",
        "hasNextPage": false,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }

  static func expectationForPreviousPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "before": "Y3Vyc29yMw==", "after": GraphQLNullable<String>.null]
    return await server.expect(query) { _ in
      let pageInfo: [AnyHashable: AnyHashable] = [
        "__typename": "PageInfo",
        "startCursor": "Y3Vyc29yMq==",
        "hasPreviousPage": false,
        "endCursor": "Y3Vyc29yMw==",
        "hasNextPage": true,
      ]
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
      ]
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }
}

extension Mocks.Hero.OffsetFriendsQuery {
  static func expectationForFirstPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.OffsetFriendsQuery>()
    query.__variables = ["id": "2001", "offset": 0, "limit": 2]
    return await server.expect(query) { _ in
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Luke Skywalker",
          "id": "1000",
        ],
        [
          "__typename": "Human",
          "name": "Han Solo",
          "id": "1002",
        ],
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friends": friends,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }

  static func expectationForLastPage(server: MockGraphQLServer) async -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.OffsetFriendsQuery>()
    query.__variables = ["id": "2001", "offset": 2, "limit": 2]
    return await server.expect(query) { _ in
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]

      let hero = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friends": friends,
      ]

      let data = [
        "hero": hero
      ]

      return [
        "data": data as JSONValue
      ]
    }
  }
}
