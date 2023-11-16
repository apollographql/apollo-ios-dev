import ApolloInternalTestHelpers
import XCTest

extension Mocks.Hero.FriendsQuery {
  
  static func expectationForFirstPage(server: MockGraphQLServer) -> XCTestExpectation {
    server.expect(MockQuery<Mocks.Hero.FriendsQuery>.self) { _ in
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
    server.expect(MockQuery<Mocks.Hero.FriendsQuery>.self) { _ in
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
}
