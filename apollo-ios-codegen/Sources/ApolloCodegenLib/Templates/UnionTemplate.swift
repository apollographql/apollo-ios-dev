import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Union](https://spec.graphql.org/draft/#sec-Unions)
/// into Swift code.
struct UnionTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Union](https://spec.graphql.org/draft/#sec-Unions).
  let irUnion: IR.UnionType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .union)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
    """
    \(documentation: irUnion.documentation, config: config)
    static let \(irUnion.render(as: .typename, config: config)) = Union(
      name: "\(irUnion.name.schemaName)",
      possibleTypes: \(PossibleTypesTemplate())
    )
    """
    )
  }

  private func PossibleTypesTemplate() -> TemplateString {
    "[\(list: irUnion.types.map(PossibleTypeTemplate))]"
  }

  private func PossibleTypeTemplate(
    _ type: IR.ObjectType
  ) -> TemplateString {
    """
    \(if: !config.output.schemaTypes.isInModule, "\(config.schemaNamespace.firstUppercased).")\
    Objects.\(type.render(as: .typename, config: config)).self
    """
  }

}
