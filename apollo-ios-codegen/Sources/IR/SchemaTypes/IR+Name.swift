import Foundation

public protocol NamedItem {
  var name: Name { get }
}

public struct Name: Hashable {
  public let schemaName: String
  
  public let typenameSuffix: String
  
  public var customName: String?
  
  public var swiftName: String {
    switch schemaName {
    case "Boolean": return "Bool"
    case "Float": return "Double"
    default: return schemaName
    }
  }
  
  public init(
    schemaName: String,
    typenameSuffix: String = "GraphQL"
  ) {
    self.schemaName = schemaName
    self.typenameSuffix = typenameSuffix
  }
  
  // MARK: - Render Context
  
  public enum RenderContext {
    case enumCase
    case enumRawValue
    case filename
    case typename
  }
  
}
