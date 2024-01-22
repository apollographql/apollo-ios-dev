import Foundation

struct SchemaCustomization: Codable {
  
  let customTypeNames: [String: CustomSchemaTypeName]
 
  // MARK: - Codable
  
  enum CodingKeys: CodingKey, CaseIterable {
    case customTypeNames
  }
  
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try throwIfContainsUnexpectedKey(
      container: values,
      type: Self.self,
      decoder: decoder
    )
    
    customTypeNames = try values.decode(
      [String: CustomSchemaTypeName].self,
      forKey: .customTypeNames
    )
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    try container.encode(self.customTypeNames, forKey: .customTypeNames)
  }
  
  // MARK: - Enums
  
  enum CustomSchemaTypeName: Codable {
    case object(name: String)
    case interface(name: String)
    case customScalar(name: String)
    case union(name: String)
    case `enum`(name: String, cases: [String: String])
    case inputObject(name: String, fields: [String: String])
  }
}
