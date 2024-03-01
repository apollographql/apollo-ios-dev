import Foundation
import IR

extension IR.NamedItem {
  
  func render(
    as context: IR.Name.RenderContext,
    config: ApolloCodegen.ConfigurationContext
  ) -> String {
    //If the name has been customized and its not for .enumRawValue, return it unchanged
    if let customName = name.customName, context != .enumRawValue {
      return customName
    }
    
    switch context {
    case .enumCase:
      return renderEnumCase(config.config)
    case .enumRawValue:
      return self.name.schemaName
    case .filename:
      return self.name.schemaName
    case .typename:
      return renderTypeName()
    }
  }
  
  private func renderTypeName() -> String {
    switch self {
    case let type as IR.ScalarType:
      if !type.isCustomScalar {
        return self.name.swiftName
      }
      fallthrough
    case is IR.EnumType: fallthrough
    case is IR.InputObjectType: fallthrough
    case is IR.InterfaceType: fallthrough
    case is IR.UnionType:fallthrough
    case is IR.ObjectType:
      let uppercasedName = self.name.swiftName.firstUppercased
      return SwiftKeywords.TypeNamesToSuffix.contains(uppercasedName) ?
      "\(uppercasedName)\(self.name.typenameSuffix)" : uppercasedName
    default:
      break
    }
    
    return self.name.swiftName
  }
  
  private func renderEnumCase(_ config: ApolloCodegenConfiguration) -> String {
    switch config.options.conversionStrategies.enumCases {
    case .none:
      return self.name.schemaName.asEnumCaseName
    case .camelCase:
      return self.name.schemaName.convertToCamelCase().asEnumCaseName
    }
  }
  
}
