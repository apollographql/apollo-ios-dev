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
  
  enum CustomSchemaTypeName: Codable, ExpressibleByStringLiteral {
    case type(name: String)
    case `enum`(name: String?, cases: [String: String]?)
    case inputObject(name: String?, fields: [String: String]?)

    public init(stringLiteral value: String) {
      self = .type(name: value)
    }
    
    enum CodingKeys: CodingKey, CaseIterable {
      case type
      case `enum`
      case inputObject
    }
    
    enum TypeCodingKeys: CodingKey, CaseIterable {
      case name
    }
    
    enum EnumCodingKeys: CodingKey, CaseIterable {
      case name
      case cases
    }
    
    enum InputObjectCodingKeys: CodingKey, CaseIterable {
      case name
      case fields
    }
    
    public init(from decoder: Decoder) throws {
      var customTypeName: CustomSchemaTypeName?
      
      if let container = try? decoder.container(keyedBy: CodingKeys.self) {
        switch container.allKeys.first {
        case .type:
          let subContainer = try container.nestedContainer(keyedBy: TypeCodingKeys.self, forKey: .type)
          let name = try subContainer.decode(String.self, forKey: .name)
          customTypeName = .type(name: name)
          break
        case .enum:
          let subContainer = try container.nestedContainer(keyedBy: EnumCodingKeys.self, forKey: .enum)
          let name = try subContainer.decodeIfPresent(String.self, forKey: .name)
          let cases = try subContainer.decodeIfPresent([String: String].self, forKey: .cases)
          customTypeName = .enum(name: name, cases: cases)
          break
        case .inputObject:
          let subContainer = try container.nestedContainer(keyedBy: InputObjectCodingKeys.self, forKey: .inputObject)
          let name = try subContainer.decodeIfPresent(String.self, forKey: .name)
          let fields = try subContainer.decodeIfPresent([String: String].self, forKey: .fields)
          customTypeName = .inputObject(name: name, fields: fields)
          break
        case .none:
          fatalError()
        }
      } else if let container = try? decoder.singleValueContainer() {
        let name = try container.decode(String.self)
        customTypeName = .type(name: name)
      }
      
      if let customTypeName = customTypeName {
        self = customTypeName
      } else {
        fatalError()
      }
    }
    
    public func encode(to encoder: Encoder) throws {
      switch self {
      case .type(let name):
        var container = encoder.singleValueContainer()
        try container.encode(name)
      case .enum(let name, let cases):
        if cases == nil {
          var container = encoder.singleValueContainer()
          try container.encode(name)
        } else {
          var container = encoder.container(keyedBy: CodingKeys.self)
          var subContainer = container.nestedContainer(keyedBy: EnumCodingKeys.self, forKey: .enum)
          try subContainer.encodeIfPresent(name, forKey: .name)
          try subContainer.encodeIfPresent(cases, forKey: .cases)
        }
      case .inputObject(let name, let fields):
        if name != nil, fields == nil {
          var container = encoder.singleValueContainer()
          try container.encode(name)
        } else {
          var container = encoder.container(keyedBy: CodingKeys.self)
          var subContainer = container.nestedContainer(keyedBy: InputObjectCodingKeys.self, forKey: .inputObject)
          try subContainer.encodeIfPresent(name, forKey: .name)
          try subContainer.encodeIfPresent(fields, forKey: .fields)
        }
      }
    }
  }
}
