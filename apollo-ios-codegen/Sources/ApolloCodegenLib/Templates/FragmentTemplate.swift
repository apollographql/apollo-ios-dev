import Foundation
import IR
import TemplateString

/// Provides the format to convert a [GraphQL Fragment](https://spec.graphql.org/draft/#sec-Language.Fragments)
/// into Swift code.
struct FragmentTemplate: TemplateRenderer {
  /// IR representation of source [GraphQL Fragment](https://spec.graphql.org/draft/#sec-Language.Fragments).
  let fragment: IR.NamedFragment

  let config: ApolloCodegen.ConfigurationContext

  var target: TemplateTarget {
    .operationFile(moduleImports: fragment.definition.moduleImports)
  }

  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let includeDefinition = config.options.operationDocumentFormat.contains(.definition)
    let memberAccessControlRenderer = accessControlRenderer(for: .member)
    return TemplateString(
    """
    \(accessControlModifier(for: .parent))\
    struct \(fragment.generatedDefinitionName.asFragmentName): \
    \(fragment.renderedSelectionSetType(config)), Fragment\
    \(if: fragment.isIdentifiable, ", Identifiable")\
     {
    \(if: includeDefinition, """
      \(memberAccessControlRenderer.accessControl())\
    static var fragmentDefinition: StaticString {
        #"\(fragment.definition.source.convertedToSingleLine())"#
      }
    
    """)
      \(SelectionSetTemplate(
        definition: fragment,
        generateInitializers: config.config.shouldGenerateSelectionSetInitializers(for: fragment),
        config: config,
        nonFatalErrorRecorder: nonFatalErrorRecorder,
        accessControlRenderer: memberAccessControlRenderer
      ).renderBody())
    }

    """)
  }

}
