import Foundation
import ApolloAPI

open class MockLocalCacheMutation<SelectionSet: MutableRootSelectionSet>: LocalCacheMutation, @unchecked Sendable {
  open class var operationType: GraphQLOperationType { .query }

  public typealias Data = SelectionSet

  open var __variables: GraphQLOperation.Variables?

  public init() {}

}

open class MockLocalCacheMutationFromMutation<SelectionSet: MutableRootSelectionSet>:
  MockLocalCacheMutation<SelectionSet>, @unchecked Sendable {
  override open class var operationType: GraphQLOperationType { .mutation }
}

open class MockLocalCacheMutationFromSubscription<SelectionSet: MutableRootSelectionSet>:
  MockLocalCacheMutation<SelectionSet>, @unchecked Sendable {
  override open class var operationType: GraphQLOperationType { .subscription }
}

public protocol MockMutableRootSelectionSet: MutableRootSelectionSet
where Schema == MockSchemaMetadata {}

public extension MockMutableRootSelectionSet {
  static var __parentType: any ParentType { Object.mock }
  static var __fulfilledFragments: [any SelectionSet.Type] { [] }

  init() {
    self.init(_dataDict: DataDict(
      data: [:],
      fulfilledFragments: [ObjectIdentifier(Self.self)]
    ))
  }
}

public protocol MockMutableInlineFragment: MutableSelectionSet, InlineFragment
where Schema == MockSchemaMetadata {}

public extension MockMutableInlineFragment {
  static var __fulfilledFragments: [any SelectionSet.Type] { [] }
}
