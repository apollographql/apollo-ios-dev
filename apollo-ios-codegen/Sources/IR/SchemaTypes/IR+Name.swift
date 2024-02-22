import Foundation

public struct Name: Hashable {
  public let schemaName: String
  
  public var customName: String?
  
  public init(schemaName: String) {
    self.schemaName = schemaName
  }
  
}
