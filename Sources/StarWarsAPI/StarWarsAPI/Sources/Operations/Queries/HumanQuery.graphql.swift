// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct HumanQuery: GraphQLQuery {
  public static let operationName: String = "Human"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "22b975c180932a926f48bfec1e002b9d1389e0ee1d84b3cdfa337d80fb036a26",
    definition: .init(
      #"query Human($id: ID!) { human(id: $id) { __typename name mass } }"#
    ))

  public var id: ID

  public init(id: ID) {
    self.id = id
  }

  public var __variables: Variables? { ["id": id] }

  public struct Data: StarWarsAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("human", Human?.self, arguments: ["id": .variable("id")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      HumanQuery.Data.self
    ] }

    public var human: Human? { __data["human"] }

    public init(
      human: Human? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Query.typename,
        "human": human._fieldData,
      ])
    }

    /// Human
    ///
    /// Parent Type: `Human`
    public struct Human: StarWarsAPI.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Human }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .field("mass", Double?.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HumanQuery.Data.Human.self
      ] }

      /// What this human calls themselves
      public var name: String { __data["name"] }
      /// Mass in kilograms, or null if unknown
      public var mass: Double? { __data["mass"] }

      public init(
        name: String,
        mass: Double? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": StarWarsAPI.Objects.Human.typename,
          "name": name,
          "mass": mass,
        ])
      }
    }
  }
}
