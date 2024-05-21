import Foundation

public protocol GraphQLNamedItem {
  var name: GraphQLName { get }
}

public class GraphQLName: Hashable {
  public let schemaName: String
  
  public var customName: String?
  
  public var swiftName: String {
    switch schemaName {
    case "Boolean": return "Bool"
    case "Float": return "Double"
    default: return schemaName
    }
  }
  
  public var shouldRenderDocumentation: Bool {
    if let customName, !customName.isEmpty {
      return true
    }
    return false
  }
  
  public var typeNameDocumentation: String {
    """
    // This type has been renamed from the schema type '\(schemaName)'
    // using schema customization configuration.
    """
  }
  
  public init(
    schemaName: String
  ) {
    self.schemaName = schemaName
  }
  
  // MARK: - Hashable
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(schemaName)
  }
  
  public static func == (lhs: GraphQLName, rhs: GraphQLName) -> Bool {
    return lhs.schemaName == rhs.schemaName
  }
  
}
