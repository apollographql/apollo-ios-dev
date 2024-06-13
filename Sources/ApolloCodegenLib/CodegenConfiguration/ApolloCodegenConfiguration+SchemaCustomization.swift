import Foundation

extension ApolloCodegenConfiguration {
  
  public struct SchemaCustomization: Codable, Equatable {
    
    // MARK: - Properties
    
    /// Dictionary with Keys representing the types being renamed/customized, and
    public let customTypeNames: [String: CustomSchemaTypeName]
   
    /// Default property values
    public struct Default {
      public static let customTypeNames: [String: CustomSchemaTypeName] = [:]
    }
    
    // MARK: - Initialization
    
    /// Designated initializer
    ///
    /// - Parameters:
    ///   - customTypeNames: Dictionary repsenting the types to be renamed and how to rename them.
    public init(
      customTypeNames: [String: CustomSchemaTypeName] = Default.customTypeNames
    ) {
      self.customTypeNames = customTypeNames
    }
    
    // MARK: - Codable
    
    enum CodingKeys: CodingKey, CaseIterable {
      case customTypeNames
    }
    
    public init(from decoder: any Decoder) throws {
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
    
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      
      try container.encode(self.customTypeNames, forKey: .customTypeNames)
    }
    
    // MARK: - Enums
    
    public enum CustomSchemaTypeName: Codable, ExpressibleByStringLiteral, Equatable {
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
      
      public init(from decoder: any Decoder) throws {
        guard let originalTypeName = decoder.codingPath.last?.stringValue else {
          preconditionFailure("Unable to get original type name value from JSON during decoding.")
        }
        var customTypeName: CustomSchemaTypeName?
        
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
          switch container.allKeys.first {
          case .type:
            let subContainer = try container.nestedContainer(keyedBy: TypeCodingKeys.self, forKey: .type)
            let name = try subContainer.decodeIfPresentOrEmpty(type: String.self, key: .name)
            guard let name = name else {
              throw Error.emptyCustomization(type: originalTypeName)
            }
            customTypeName = .type(name: name)
            break
          case .enum:
            let subContainer = try container.nestedContainer(keyedBy: EnumCodingKeys.self, forKey: .enum)
            let name = try subContainer.decodeIfPresentOrEmpty(type: String.self, key: .name)
            let cases = try subContainer.decodeIfPresentOrEmpty(type: [String: String].self, key: .cases)
            
            guard name != nil || cases != nil else {
              throw Error.emptyCustomization(type: originalTypeName)
            }
            
            if let name = name, cases == nil {
              customTypeName = .type(name: name)
            } else {
              customTypeName = .enum(name: name, cases: cases)
            }
            break
          case .inputObject:
            let subContainer = try container.nestedContainer(keyedBy: InputObjectCodingKeys.self, forKey: .inputObject)
            let name = try subContainer.decodeIfPresentOrEmpty(type: String.self, key: .name)
            let fields = try subContainer.decodeIfPresentOrEmpty(type: [String: String].self, key: .fields)
            
            guard name != nil || fields != nil else {
              throw Error.emptyCustomization(type: originalTypeName)
            }
            
            if let name = name, fields == nil {
              customTypeName = .type(name: name)
            } else {
              customTypeName = .inputObject(name: name, fields: fields)
            }
            break
          case .none:
            break
          }
        } else if let container = try? decoder.singleValueContainer() {
          let name = try container.decode(String.self)
          guard !name.isEmpty else {
            throw Error.emptyCustomization(type: originalTypeName)
          }
          customTypeName = .type(name: name)
        }
        
        if let customTypeName = customTypeName {
          self = customTypeName
        } else {
          throw Error.decodingFailure(type: originalTypeName)
        }
      }
      
      public func encode(to encoder: any Encoder) throws {
        guard let originalTypeName = encoder.codingPath.last?.stringValue else {
          preconditionFailure("Unable to get original type name value from type during decoding.")
        }
        switch self {
        case .type(let name):
          guard !name.isEmpty else {
            throw Error.emptyCustomization(type: originalTypeName)
          }
          var container = encoder.singleValueContainer()
          try container.encode(name)
        case .enum(let name, let cases):
          guard (name != nil && !(name ?? "").isEmpty) || (cases != nil && !(cases ?? [:]).isEmpty) else {
            throw Error.emptyCustomization(type: originalTypeName)
          }
          
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
          guard (name != nil && !(name ?? "").isEmpty) || (fields != nil && !(fields ?? [:]).isEmpty) else {
            throw Error.emptyCustomization(type: originalTypeName)
          }
          
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
    
    public enum Error: Swift.Error, LocalizedError {
      case decodingFailure(type: String)
      case emptyCustomization(type: String)
      
      public var errorDescription: String? {
        switch self {
        case let .decodingFailure(type):
          return """
          Unable to decode type '\(type)' when processing custom schema
          type names.
          """
        case let .emptyCustomization(type):
          return """
          No customization data was provided for type '\(type)', customization
          will be ignored.
          """
        }
      }
    }
    
  }
  
}

extension KeyedDecodingContainer {
  fileprivate func decodeIfPresentOrEmpty(type: String.Type, key: KeyedDecodingContainer<K>.Key) throws -> String? {
    if let value = try decodeIfPresent(type, forKey: key) {
      return value.isEmpty ? nil : value
    }
     return nil
  }
  
  fileprivate func decodeIfPresentOrEmpty(type: [String: String].Type, key: KeyedDecodingContainer<K>.Key) throws -> [String: String]? {
    if let value = try decodeIfPresent(type, forKey: key) {
      return value.isEmpty ? nil : value
    }
     return nil
  }
}

