import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest

enum Mocks {
  enum Hero {
    class BidirectionalFriendsQuery: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero?.self, arguments: ["id": .variable("id")])
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friendsConnection", FriendsConnection.self, arguments: [
            "first": .variable("first"),
            "before": .variable("before"),
            "after": .variable("after"),
          ]),
        ]}

        var name: String { __data["name"] }
        var id: String { __data["id"] }
        var friendsConnection: FriendsConnection { __data["friendsConnection"] }

        class FriendsConnection: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("totalCount", Int.self),
            .field("friends", [Character].self),
            .field("pageInfo", PageInfo.self),
          ]}

          var totalCount: Int { __data["totalCount"] }
          var friends: [Character] { __data["friends"] }
          var pageInfo: PageInfo { __data["pageInfo"] }

          class Character: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("name", String.self),
              .field("id", String.self),
            ]}

            var name: String { __data["name"] }
            var id: String { __data["id"] }
          }

          class PageInfo: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("startCursor", Optional<String>.self),
              .field("hasPreviousPage", Bool.self),
              .field("endCursor", Optional<String>.self),
              .field("hasNextPage", Bool.self),
            ]}

            var endCursor: String? { __data["endCursor"] }
            var hasNextPage: Bool { __data["hasNextPage"] }
            var startCursor: String? { __data["startCursor"] }
            var hasPreviousPage: Bool { __data["hasPreviousPage"] }
          }
        }
      }
    }
    class ReverseFriendsQuery: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero?.self, arguments: ["id": .variable("id")])
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friendsConnection", FriendsConnection.self, arguments: [
            "first": .variable("first"),
            "before": .variable("before"),
          ]),
        ]}

        var name: String { __data["name"] }
        var id: String { __data["id"] }
        var friendsConnection: FriendsConnection { __data["friendsConnection"] }

        class FriendsConnection: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("totalCount", Int.self),
            .field("friends", [Character].self),
            .field("pageInfo", PageInfo.self),
          ]}

          var totalCount: Int { __data["totalCount"] }
          var friends: [Character] { __data["friends"] }
          var pageInfo: PageInfo { __data["pageInfo"] }

          class Character: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("name", String.self),
              .field("id", String.self),
            ]}

            var name: String { __data["name"] }
            var id: String { __data["id"] }
          }

          class PageInfo: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("startCursor", Optional<String>.self),
              .field("hasPreviousPage", Bool.self),
            ]}

            var startCursor: String? { __data["startCursor"] }
            var hasPreviousPage: Bool { __data["hasPreviousPage"] }
          }
        }
      }
    }
    class FriendsQuery: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero?.self, arguments: ["id": .variable("id")])
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friendsConnection", FriendsConnection.self, arguments: [
            "first": .variable("first"),
            "after": .variable("after"),
          ]),
        ]}

        var name: String { __data["name"] }
        var id: String { __data["id"] }
        var friendsConnection: FriendsConnection { __data["friendsConnection"] }

        class FriendsConnection: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("totalCount", Int.self),
            .field("friends", [Character].self),
            .field("pageInfo", PageInfo.self),
          ]}

          var totalCount: Int { __data["totalCount"] }
          var friends: [Character] { __data["friends"] }
          var pageInfo: PageInfo { __data["pageInfo"] }

          class Character: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("name", String.self),
              .field("id", String.self),
            ]}

            var name: String { __data["name"] }
            var id: String { __data["id"] }
          }

          class PageInfo: MockSelectionSet, @unchecked Sendable {
            override class var __selections: [Selection] {[
              .field("__typename", String.self),
              .field("endCursor", Optional<String>.self),
              .field("hasNextPage", Bool.self),
            ]}

            var endCursor: String? { __data["endCursor"] }
            var hasNextPage: Bool { __data["hasNextPage"] }
          }
        }
      }
    }

    class OffsetFriendsQuery: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("hero", Hero?.self, arguments: ["id": .variable("id")])
      ]}

      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
          .field("friends", [Character].self, arguments: [
            "offset": .variable("offset"),
            "limit": .variable("limit"),
          ]),
        ]}

        var name: String { __data["name"] }
        var id: String { __data["id"] }
        var friends: [Character] { __data["friends"] }

        class Character: MockSelectionSet, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self),
            .field("id", String.self),
          ]}

          var name: String { __data["name"] }
          var id: String { __data["id"] }
        }
      }
    }

    struct NameCacheMutation: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }
      static var __selections: [Selection] { [
        .field("hero", Hero?.self, arguments: ["id": .variable("id")])
      ]}

      var hero: Hero? {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }
        static var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("id", String.self),
          .field("name", String.self),
        ]}

        var id: String {
          get { __data["id"] }
          set { __data["id"] = newValue }
        }

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

  }
}
