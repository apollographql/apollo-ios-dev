import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class ObjectType: CompositeType, InterfaceImplementingType {
  public let graphqlObjectType: GraphQLObjectType
  
  public var interfaces: [InterfaceType]! = []
  
  public init(_ graphqlObjectType: GraphQLObjectType) {
    self.graphqlObjectType = graphqlObjectType
    super.init(
      graphqlObjectType,
      typenameSuffix: "_Object"
    )
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLObjectType, T>) -> T {
    graphqlObjectType[keyPath: keyPath]
  }
  
}
