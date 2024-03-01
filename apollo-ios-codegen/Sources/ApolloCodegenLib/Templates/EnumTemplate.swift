import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Enum](https://spec.graphql.org/draft/#sec-Enums) into
/// Swift code.
struct EnumTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Enum](https://spec.graphql.org/draft/#sec-Enums).
  let irEnum: IR.EnumType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .enum)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
    """
    \(documentation: irEnum.documentation, config: config)
    \(accessControlModifier(for: .parent))\
    enum \(irEnum.render(as: .typename, config: config)): String, EnumType {
      \(irEnum.values.compactMap({
        enumCase(for: $0)
      }), separator: "\n")
    }
    
    """
    )
  }

  private func enumCase(for irEnumValue: IR.EnumValue) -> TemplateString? {
    if config.options.deprecatedEnumCases == .exclude && irEnumValue.isDeprecated {
      return nil
    }

    let shouldRenderDocumentation = irEnumValue.documentation != nil &&
    config.options.schemaDocumentation == .include

    return """
    \(if: shouldRenderDocumentation, "\(documentation: irEnumValue.documentation)")
    \(ifLet: irEnumValue.deprecationReason, { """
      \(if: shouldRenderDocumentation, "///")
      \(documentation: "**Deprecated**: \($0.escapedSwiftStringSpecialCharacters())")
      """ })
    \(caseDefinition(for: irEnumValue))
    """
  }

  private func caseDefinition(for irEnumValue: IR.EnumValue) -> TemplateString {
    """
    case \(irEnumValue.render(as: .enumCase, config: config))\
    \(if: config.options.conversionStrategies.enumCases != .none, """
       = "\(irEnumValue.render(as: .enumRawValue, config: config))"
      """)
    """
  }

}
