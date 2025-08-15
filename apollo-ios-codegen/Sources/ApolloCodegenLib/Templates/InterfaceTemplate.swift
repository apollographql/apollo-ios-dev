import Foundation
import GraphQLCompiler
import TemplateString

/// Provides the format to convert a [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces)
/// into Swift code.
struct InterfaceTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Interface](https://spec.graphql.org/draft/#sec-Interfaces).
  let graphqlInterface: GraphQLInterfaceType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .interface)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    """
    \(documentation: graphqlInterface.documentation, config: config)
    \(graphqlInterface.name.typeNameDocumentation)
    static let \(graphqlInterface.render(as: .typename())) = \(TemplateConstants.ApolloAPITargetName).Interface(
      name: "\(graphqlInterface.name.schemaName)",
      keyFields: \(KeyFieldsTemplate()),
      implementingObjects: \(ImplementingObjectsTemplate())
    )
    """
  }
  
  private func KeyFieldsTemplate() -> TemplateString {
    guard let fields = graphqlInterface.keyFields, !fields.isEmpty else { return "nil" }
    
    return """
    [\(list: fields.map { "\"\($0)\"" })]
    """
  }
  
  private func ImplementingObjectsTemplate() -> TemplateString {
    return """
    [\(list: graphqlInterface.implementingObjects.map({ object in
          TemplateString("""
          "\(object.render(as: .typename()))"
          """)
      }))]
    """
  }
}
