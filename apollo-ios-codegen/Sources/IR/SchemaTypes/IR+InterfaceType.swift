import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class InterfaceType: NamedType {
  public let graphqlInterfaceType: GraphQLInterfaceType
  
  public init(_ graphqlInterfaceType: GraphQLInterfaceType) {
    self.graphqlInterfaceType = graphqlInterfaceType
    super.init(graphqlInterfaceType)
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInterfaceType, T>) -> T {
    graphqlInterfaceType[keyPath: keyPath]
  }
  
}
