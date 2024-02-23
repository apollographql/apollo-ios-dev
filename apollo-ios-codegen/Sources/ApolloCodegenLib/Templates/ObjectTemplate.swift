import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Object](https://spec.graphql.org/draft/#sec-Objects)
/// into Swift code.
struct ObjectTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Object](https://spec.graphql.org/draft/#sec-Objects).
  let irObject: IR.ObjectType

  let config: ApolloCodegen.ConfigurationContext

  let target: TemplateTarget = .schemaFile(type: .object)

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {    
    """
    \(documentation: irObject.documentation, config: config)
    static let \(irObject.render(as: .typename, config: config)) = \(config.ApolloAPITargetName).Object(
      typename: "\(irObject.name.schemaName)\",
      implementedInterfaces: \(ImplementedInterfacesTemplate())
    )
    """
  }

  private func ImplementedInterfacesTemplate() -> TemplateString {
    return """
    [\(list: irObject.interfaces.map({ interface in
          TemplateString("""
          \(if: !config.output.schemaTypes.isInModule, "\(config.schemaNamespace.firstUppercased).")\
          Interfaces.\(interface.formattedme).self
          """)
      }))]
    """
  }
}
