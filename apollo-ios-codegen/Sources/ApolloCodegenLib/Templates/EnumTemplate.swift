import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Enum](https://spec.graphql.org/draft/#sec-Enums) into
/// Swift code.
struct EnumTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Enum](https://spec.graphql.org/draft/#sec-Enums).
  let graphqlEnum: GraphQLEnumType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .enum)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
    """
    \(documentation: graphqlEnum.documentation, config: config)
    \(accessControlModifier(for: .parent))\
    enum \(graphqlEnum.render(as: .typename)): String, EnumType {
      \(graphqlEnum.values.compactMap({
        enumCase(for: $0)
      }), separator: "\n")
    }
    
    """
    )
  }

  private func enumCase(for graphqlEnumValue: GraphQLEnumValue) -> TemplateString? {
    if config.options.deprecatedEnumCases == .exclude && graphqlEnumValue.isDeprecated {
      return nil
    }

    let shouldRenderDocumentation = graphqlEnumValue.documentation != nil &&
    config.options.schemaDocumentation == .include

    return """
    \(if: shouldRenderDocumentation, "\(documentation: graphqlEnumValue.documentation)")
    \(ifLet: graphqlEnumValue.deprecationReason, { """
      \(if: shouldRenderDocumentation, "///")
      \(documentation: "**Deprecated**: \($0.escapedSwiftStringSpecialCharacters())")
      """ })
    \(caseDefinition(for: graphqlEnumValue))
    """
  }

  private func caseDefinition(for graphqlEnumValue: GraphQLEnumValue) -> TemplateString {
    """
    case \(graphqlEnumValue.render(as: .enumCase, config: config))\
    \(if: config.options.conversionStrategies.enumCases != .none, """
       = "\(graphqlEnumValue.render(as: .enumRawValue, config: config))"
      """)
    """
  }

}
