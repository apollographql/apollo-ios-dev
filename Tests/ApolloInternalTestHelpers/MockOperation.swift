@_spi(Execution) @_spi(Unsafe) import ApolloAPI
import Foundation

open class MockQuery<SelectionSet: RootSelectionSet>: GraphQLQuery, @unchecked Sendable {

  public typealias Data = SelectionSet

  open class var operationType: GraphQLOperationType { .query }

  open class var operationName: String { "MockOperationName" }

  open class var operationDocument: OperationDocument {
    .init(definition: .init("Mock Operation Definition"))
  }

  open var __variables: Variables?

  public init() {}

  public static func mock() -> MockQuery<MockSelectionSet> where SelectionSet == MockSelectionSet {
    MockQuery<MockSelectionSet>()
  }

  public var defaultResponseData: Foundation.Data {
    return """
    {
      "data": {}
    }
    """.data(using: .utf8)!
  }
}

open class MockMutation<SelectionSet: RootSelectionSet>: GraphQLMutation, @unchecked Sendable {

  public typealias Data = SelectionSet

  open class var operationType: GraphQLOperationType { .mutation }

  open class var operationName: String { "MockOperationName" }

  open class var operationDocument: OperationDocument {
    .init(definition: .init("Mock Operation Definition"))
  }

  open var __variables: Variables?

  public init() {}

  public static func mock() -> MockMutation<MockSelectionSet> where SelectionSet == MockSelectionSet {
    MockMutation<MockSelectionSet>()
  }
}

open class MockSubscription<SelectionSet: RootSelectionSet>: GraphQLSubscription, @unchecked Sendable {
  public typealias Data = SelectionSet

  open class var operationType: GraphQLOperationType { .subscription }

  open class var operationName: String { "MockOperationName" }

  open class var operationDocument: OperationDocument {
    .init(definition: .init("Mock Operation Definition"))
  }

  open var __variables: Variables?

  public init() {}

  public typealias ResponseFormat = SubscriptionResponseFormat

  public static func mock() -> MockSubscription<MockSelectionSet> where SelectionSet == MockSelectionSet {
    MockSubscription<MockSelectionSet>()
  }
}

// MARK: - MockSelectionSets

@dynamicMemberLookup
open class AbstractMockSelectionSet<F, S: SchemaMetadata>: RootSelectionSet, Hashable, @unchecked Sendable {
  public typealias Schema = S
  public typealias Fragments = F

  @_spi(Execution) open class var __selections: [Selection] { [] }
  @_spi(Execution) open class var __parentType: any ParentType { Object.mock }
  @_spi(Execution) open class var __fulfilledFragments: [any SelectionSet.Type] { [] }

  @_spi(Unsafe)
  public var __data: DataDict = .empty()

  @_spi(Unsafe)
  public required init(_dataDict: DataDict) {
    self.__data = _dataDict
  }

  public subscript<T: AnyScalarType & Hashable>(dynamicMember key: String) -> T? {
    __data[key]
  }

  public subscript<T: MockSelectionSet>(dynamicMember key: String) -> T? {
    __data[key]
  }
    
}

public typealias MockSelectionSet = AbstractMockSelectionSet<NoFragments, MockSchemaMetadata>

open class MockFragment: MockSelectionSet, Fragment, @unchecked Sendable {
  public typealias Schema = MockSchemaMetadata

  open class var fragmentDefinition: StaticString { "" }
}

open class MockTypeCase: MockSelectionSet, InlineFragment, @unchecked Sendable {
  public typealias RootEntityType = MockSelectionSet
}

open class ConcreteMockTypeCase<T: MockSelectionSet>: MockSelectionSet, InlineFragment, @unchecked Sendable {
  public typealias RootEntityType = T
}

extension DataDict {  
  public static func empty() -> DataDict {
    DataDict(data: [:], fulfilledFragments: [])
  }
}
