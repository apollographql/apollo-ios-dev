// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public extension MyAPI {
  struct CrocodileFragment: MyAPI.SelectionSet, Fragment {
    public static var fragmentDefinition: StaticString {
      #"fragment CrocodileFragment on Crocodile { __typename species age tag(id: "albino") }"#
    }

    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MyAPI.Objects.Crocodile }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("species", String.self),
      .field("age", Int.self),
      .field("tag", String?.self, arguments: ["id": "albino"]),
    ] }

    public var species: String { __data["species"] }
    public var age: Int { __data["age"] }
    public var tag: String? { __data["tag"] }
  }

}