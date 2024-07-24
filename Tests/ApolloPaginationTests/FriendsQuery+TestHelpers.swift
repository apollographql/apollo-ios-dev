import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

extension Mocks.Hero.FriendsQuery {
  static func expectationForFirstPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }

  static func expectationForSecondPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": "Y3Vyc29yMg=="]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }

  static func expectationForFirstPageWithErrors(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data,
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

  static func expectationForFirstPageErrorsOnly(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": GraphQLNullable<String>.null]
    return server.expect(query) { _ in
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

  static func expectationForSecondPageErrorsOnly(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.FriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "after": "Y3Vyc29yMg=="]
    return server.expect(query) { _ in
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
  static func expectationForPreviousItem(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.ReverseFriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMg=="]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }
  static func expectationForLastItem(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.ReverseFriendsQuery>()
    query.__variables = ["id": "2001", "first": 2, "before": "Y3Vyc29yMw=="]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }
}

extension Mocks.Hero.BidirectionalFriendsQuery {
  static func expectationForFirstFetchInMiddleOfList(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "before": GraphQLNullable<String>.null, "after": "Y3Vyc29yMw=="]
    return server.expect(query) { _ in
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
      let friendsConnection: [String: AnyHashable] = [
        "__typename": "FriendsConnection",
        "totalCount": 3,
        "friends": friends,
        "pageInfo": pageInfo,
      ]

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }

  static func expectationForLastPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "after": "Y3Vyc29yMg==", "before": GraphQLNullable<String>.null]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }

  static func expectationForPreviousPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.BidirectionalFriendsQuery>()
    query.__variables = ["id": "2001", "first": 1, "before": "Y3Vyc29yMw==", "after": GraphQLNullable<String>.null]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friendsConnection": friendsConnection,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }
}

extension Mocks.Hero.OffsetFriendsQuery {
  static func expectationForFirstPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.OffsetFriendsQuery>()
    query.__variables = ["id": "2001", "offset": 0, "limit": 2]
    return server.expect(query) { _ in
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

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friends": friends,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }

  static func expectationForLastPage(server: MockGraphQLServer) -> XCTestExpectation {
    let query = MockQuery<Mocks.Hero.OffsetFriendsQuery>()
    query.__variables = ["id": "2001", "offset": 2, "limit": 2]
    return server.expect(query) { _ in
      let friends: [[String: AnyHashable]] = [
        [
          "__typename": "Human",
          "name": "Leia Organa",
          "id": "1003",
        ],
      ]

      let hero: [String: AnyHashable] = [
        "__typename": "Droid",
        "id": "2001",
        "name": "R2-D2",
        "friends": friends,
      ]

      let data: [String: AnyHashable] = [
        "hero": hero
      ]

      return [
        "data": data
      ]
    }
  }
}
