import Foundation
import GraphQLCompiler

@dynamicMemberLookup
public final class InterfaceType: AbstractType, InterfaceImplementingType {
  public let graphqlInterfaceType: GraphQLInterfaceType
  
  public var interfaces: [InterfaceType]! = []
  
  public init(_ graphqlInterfaceType: GraphQLInterfaceType) {
    self.graphqlInterfaceType = graphqlInterfaceType
    super.init(
      graphqlInterfaceType,
      typenameSuffix: "_Interface"
    )
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInterfaceType, T>) -> T {
    graphqlInterfaceType[keyPath: keyPath]
  }
  
}

public protocol InterfaceImplementingType: CompositeType {
  var interfaces: [InterfaceType]! { get }
}

public extension InterfaceImplementingType {
  func implements(_ interface: InterfaceType) -> Bool {
    interfaces.contains(interface)
  }
}
