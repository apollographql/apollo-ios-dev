import Foundation
import GraphQLCompiler
import OrderedCollections

public typealias InputFieldDictionary = OrderedDictionary<String, InputField>

@dynamicMemberLookup
public final class InputObjectType: NamedType {
  public let graphqlInputObjectType: GraphQLInputObjectType
  
  public private(set) var fields: InputFieldDictionary
  
  public init(_ graphqlInputObjectType: GraphQLInputObjectType) {
    self.graphqlInputObjectType = graphqlInputObjectType
    
    self.fields = [:]
    for (key, field) in graphqlInputObjectType.fields {
      self.fields[key] = InputField(graphqlInputField: field)
    }
    
    super.init(
      graphqlInputObjectType,
      typenameSuffix: "_InputObject"
    )
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInputObjectType, T>) -> T {
    graphqlInputObjectType[keyPath: keyPath]
  }
  
}

// MARK: - Input Field

@dynamicMemberLookup
public final class InputField: NamedItem {
  public let graphqlInputField: GraphQLInputField
  
  private var _name: Name
  public var name: Name {
    _name
  }
  
  public init(graphqlInputField: GraphQLInputField) {
    self.graphqlInputField = graphqlInputField
    self._name = Name(schemaName: graphqlInputField.name)
  }
  
  // MARK: - Dynamic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInputField, T>) -> T {
    graphqlInputField[keyPath: keyPath]
  }
}
