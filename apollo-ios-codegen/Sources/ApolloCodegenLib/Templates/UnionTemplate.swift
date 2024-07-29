import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Union](https://spec.graphql.org/draft/#sec-Unions)
/// into Swift code.
struct UnionTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Union](https://spec.graphql.org/draft/#sec-Unions).
  let graphqlUnion: GraphQLUnionType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .union)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
    """
    \(documentation: graphqlUnion.documentation, config: config)
    \(graphqlUnion.name.typeNameDocumentation)
    static let \(graphqlUnion.render(as: .typename)) = Union(
      name: "\(graphqlUnion.name.schemaName)",
      possibleTypes: \(PossibleTypesTemplate())
    )
    """
    )
  }

  private func PossibleTypesTemplate() -> TemplateString {
    "[\(list: graphqlUnion.types.map(PossibleTypeTemplate))]"
  }

  private func PossibleTypeTemplate(
    _ type: GraphQLObjectType
  ) -> TemplateString {
    """
    \(if: !config.output.schemaTypes.isInModule, "\(config.schemaNamespace.firstUppercased).")\
    Objects.\(type.render(as: .typename)).self
    """
  }

}
