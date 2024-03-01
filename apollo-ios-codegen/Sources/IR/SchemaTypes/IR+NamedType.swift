import Foundation
import GraphQLCompiler

//@dynamicMemberLookup
public class NamedType: Hashable, CustomDebugStringConvertible, @unchecked Sendable, NamedItem {
  public let graphqlNamedType: GraphQLNamedType
  
  private var _name: Name
  public var name: Name {
    _name
  }
  
  public init(
    _ graphqlNamedType: GraphQLNamedType,
    typenameSuffix: String = "GraphQL"
  ) {
    self.graphqlNamedType = graphqlNamedType
    self._name = Name(
      schemaName: graphqlNamedType.name,
      typenameSuffix: typenameSuffix
    )
  }
  
  // MARK: - Hashable
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }
  
  public static func == (lhs: NamedType, rhs: NamedType) -> Bool {
    return lhs.name == rhs.name
  }
  
  // MARK: - Dynamic Member Lookup
  
//  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLNamedType, T>) -> T {
//    graphqlNamedType[keyPath: keyPath]
//  }

  // MARK: - CustomDebugStringConvertible
  
  public var debugDescription: String {
    name.schemaName
  }
  
}

public class CompositeType: NamedType {
  public override var debugDescription: String {
    "Type - \(name.schemaName)"
  }
}

public class AbstractType: CompositeType {
}
