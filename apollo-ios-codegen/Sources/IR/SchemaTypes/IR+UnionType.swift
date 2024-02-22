import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class UnionType: NamedType {
  public let graphqlUnionType: GraphQLUnionType
  
  public init(_ graphqlUnionType: GraphQLUnionType) {
    self.graphqlUnionType = graphqlUnionType
    super.init(graphqlUnionType)
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLUnionType, T>) -> T {
    graphqlUnionType[keyPath: keyPath]
  }
  
}
