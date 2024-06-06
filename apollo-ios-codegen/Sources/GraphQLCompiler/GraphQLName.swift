import Foundation
import TemplateString

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
  
  private var shouldRenderDocumentation: Bool {
    if let customName, !customName.isEmpty {
      return true
    }
    return false
  }
  
  public var typeNameDocumentation: TemplateString? {
    guard shouldRenderDocumentation else { return nil }
    return """
    // Renamed from GraphQL schema value: '\(schemaName)'
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
