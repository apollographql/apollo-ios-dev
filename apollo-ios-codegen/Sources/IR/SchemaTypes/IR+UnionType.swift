import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class UnionType: AbstractType {
  public let graphqlUnionType: GraphQLUnionType
  
  public var types: [ObjectType] = []
  
  public init(_ graphqlUnionType: GraphQLUnionType) {
    self.graphqlUnionType = graphqlUnionType
    super.init(
      graphqlUnionType,
      typenameSuffix: "_Union"
    )
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLUnionType, T>) -> T {
    graphqlUnionType[keyPath: keyPath]
  }
  
}
