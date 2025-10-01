import Foundation
import GraphQLCompiler
import TemplateString

extension GraphQLNamedType {

  enum RenderContext {
    case filename
    case typename(isInputValue: Bool = false)
  }

  func render(
    as context: RenderContext
  ) -> String {
    //If the name has been customized return it unchanged
    if let customName = name.customName {
      return customName
    }

    switch context {
    case .filename:
      return self.name.schemaName
    case let .typename(isInputValue):
      return renderTypeName(isInputValue: isInputValue)
    }
  }

  private func renderTypeName(isInputValue: Bool) -> String {
    let swiftName = self.swiftName(isInputValue: isInputValue)
    switch self {
    case let type as GraphQLScalarType:
      if !type.isCustomScalar || self.name.schemaName == "ID" {
        return swiftName
      }
      fallthrough
    case is GraphQLAbstractType: fallthrough
    case is GraphQLCompositeType: fallthrough
    case is GraphQLEnumType: fallthrough
    case is GraphQLInputObjectType: fallthrough
    case is GraphQLInterfaceType: fallthrough
    case is GraphQLUnionType: fallthrough
    case is GraphQLObjectType:
      let uppercasedName = swiftName.firstUppercased
      return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
      "\(uppercasedName)\(typenameSuffix)" : uppercasedName
    default:
      break
    }

    return swiftName
  }

  func swiftName(isInputValue: Bool) -> String {
    switch self.name.schemaName {
    case "Boolean": return "Bool"
    case "Float": return "Double"
    case "Int": return isInputValue ? "Int32" : "Int"
    default: return self.name.schemaName
    }
  }

  private var typenameSuffix: String {
    switch self {
    case is GraphQLEnumType:
      return "_Enum"
    case is GraphQLInputObjectType:
      return "_InputObject"
    case is GraphQLInterfaceType:
      return "_Interface"
    case is GraphQLObjectType:
      return "_Object"
    case is GraphQLScalarType:
      return "_Scalar"
    case is GraphQLUnionType:
      return "_Union"
    default:
      return "_GraphQL"
    }
  }
}

extension GraphQLName {

  var typeNameDocumentation: TemplateString? {
    guard shouldRenderTypeNameDocumentation else { return nil }
    return """
    // Renamed from GraphQL schema value: '\(schemaName)'
    """
  }

  private var shouldRenderTypeNameDocumentation: Bool {
    if let customName, !customName.isEmpty {
      return true
    }
    return false
  }
}

extension GraphQLEnumValue {
  
  enum RenderContext {
    case enumCase
    case enumRawValue
  }
  
  func render(
    as context: RenderContext,
    config: ApolloCodegen.ConfigurationContext
  ) -> String {
    render(as: context, config: config.config)
  }
  
  func render(
    as context: RenderContext,
    config: ApolloCodegenConfiguration
  ) -> String {
    //If the name has been customized and its not for .enumRawValue, return it unchanged
    if let customName = name.customName, context != .enumRawValue {
      return customName
    }
    
    switch context {
    case .enumCase:
      return renderEnumCase(config)
    case .enumRawValue:
      return name.schemaName
    }
  }
  
  private func renderEnumCase(
    _ config: ApolloCodegenConfiguration
  ) -> String {
    switch config.options.conversionStrategies.enumCases {
    case .none:
      return self.name.schemaName.asEnumCaseName
    case .camelCase:
      return self.name.schemaName.convertToCamelCase().asEnumCaseName
    }
  }
}

extension GraphQLInputField {
  
  func render(
    config: ApolloCodegen.ConfigurationContext
  ) -> String {
    render(config: config.config)
  }
  
  func render(
    config: ApolloCodegenConfiguration
  ) -> String {
    //If the name has been customized return it unchanged
    if let customName = name.customName {
      return customName
    }
    
    return renderInputField(config)
  }
  
  private func renderInputField(
    _ config: ApolloCodegenConfiguration
  ) -> String {
    var typename = name.schemaName
    switch config.options.conversionStrategies.inputObjects {
    case .none:
      break
    case .camelCase:
      typename = typename.convertToCamelCase()
      break
    }
    
    return typename.escapeIf(in: SwiftKeywords.FieldAccessorNamesToEscape)
  }
  
}

extension GraphQLScalarType {
  
  var isSwiftType: Bool {
    switch name.schemaName {
    case "String", "Int", "Float", "Boolean":
      return true
    default:
      return false
    }
  }
}
