import Foundation
import TemplateString

public protocol GraphQLNamedItem {
  var name: GraphQLName { get }
}

public class GraphQLName: Hashable, CustomDebugStringConvertible {
  public let schemaName: String
  
  public var customName: String?
  
  public init(
    schemaName: String
  ) {
    self.schemaName = schemaName
  }
  
  // MARK: - Hashable
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(schemaName)
    hasher.combine(customName)
  }
  
  public static func == (lhs: GraphQLName, rhs: GraphQLName) -> Bool {
    return lhs.schemaName == rhs.schemaName &&
    lhs.customName == rhs.customName
  }

  public var debugDescription: String {
    schemaName
  }

}
