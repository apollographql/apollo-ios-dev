// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct IncrementingSubscription: GraphQLSubscription {
  public static let operationName: String = "Incrementing"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"subscription Incrementing { numberIncremented }"#
    ))

  public init() {}

  public struct Data: SubscriptionAPI.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { SubscriptionAPI.Objects.Subscription }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("numberIncremented", Int32?.self),
    ] }

    public var numberIncremented: Int32? { __data["numberIncremented"] }
  }
}
