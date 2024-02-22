import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public class NamedType: Hashable, CustomDebugStringConvertible, @unchecked Sendable {
  public let graphqlNamedType: GraphQLNamedType
  
  public let name: Name
  
  public init(_ graphqlNamedType: GraphQLNamedType) {
    self.graphqlNamedType = graphqlNamedType
    self.name = Name(schemaName: graphqlNamedType.name)
  }
  
  // MARK: - Hashable
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }
  
  public static func == (lhs: NamedType, rhs: NamedType) -> Bool {
    return lhs.name == rhs.name
  }
  
  // MARK: - Dynamic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLNamedType, T>) -> T {
    graphqlNamedType[keyPath: keyPath]
  }

  // MARK: - CustomDebugStringConvertible
  
  public var debugDescription: String {
    "Type - \(name.schemaName)"
  }
}
