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
    
    super.init(graphqlInputObjectType)
  }
  
  // MARK: - Dyanmic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInputObjectType, T>) -> T {
    graphqlInputObjectType[keyPath: keyPath]
  }
  
}

// MARK: - Input Field

@dynamicMemberLookup
public final class InputField {
  public let graphqlInputField: GraphQLInputField
  
  public let name: Name
  
  public init(graphqlInputField: GraphQLInputField) {
    self.graphqlInputField = graphqlInputField
    self.name = Name(schemaName: graphqlInputField.name)
  }
  
  // MARK: - Dynamic Member Lookup
  
  public subscript<T>(dynamicMember keyPath: KeyPath<GraphQLInputField, T>) -> T {
    graphqlInputField[keyPath: keyPath]
  }
}
