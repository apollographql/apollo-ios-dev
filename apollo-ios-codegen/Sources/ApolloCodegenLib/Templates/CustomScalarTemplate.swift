import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Custom Scalar](https://spec.graphql.org/draft/#sec-Scalars.Custom-Scalars)
/// into Swift code.
struct CustomScalarTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Custom Scalar](https://spec.graphql.org/draft/#sec-Scalars.Custom-Scalars).
  let graphqlScalar: GraphQLScalarType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .customScalar)

  func renderHeaderTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    HeaderCommentTemplate.editableFileHeader(
      fileCanBeEditedTo: "implement advanced custom scalar functionality."
    )    
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    TemplateString(
    """
    \(documentation: documentationTemplate, config: config)
    \(accessControlModifier(for: .parent))\
    typealias \(graphqlScalar.formattedName) = String
    
    """
    )
  }

  private var documentationTemplate: String? {
    var string = graphqlScalar.documentation
    if let specifiedByURL = graphqlScalar.specifiedByURL {
      let specifiedByDocs = "Specified by: [](\(specifiedByURL))"
      string = string?.appending("\n\n\(specifiedByDocs)") ?? specifiedByDocs
    }
    return string
  }
}
