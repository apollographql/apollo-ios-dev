import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class ScalarType: NamedType {
  public let graphqlScalarType: GraphQLScalarType
  
  public init(_ graphqlScalarType: GraphQLScalarType) {
    self.graphqlScalarType = graphqlScalarType
    super.init(
      graphqlScalarType,
      typenameSuffix: "Scalar"
    )
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLScalarType, T>) -> T {
    graphqlScalarType[keyPath: keyPath]
  }
  
}
