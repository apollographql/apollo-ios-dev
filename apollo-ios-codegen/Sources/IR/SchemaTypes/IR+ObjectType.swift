import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class ObjectType: NamedType {
  public let graphqlObjectType: GraphQLObjectType
  
  public init(_ graphqlObjectType: GraphQLObjectType) {
    self.graphqlObjectType = graphqlObjectType
    super.init(graphqlObjectType)
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLObjectType, T>) -> T {
    graphqlObjectType[keyPath: keyPath]
  }
  
}
