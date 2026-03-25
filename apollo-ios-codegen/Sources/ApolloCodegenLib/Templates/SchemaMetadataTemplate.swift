import Foundation
import IR
import TemplateString

/// Provides the format to define a schema in Swift code. The schema represents metadata used by
/// the GraphQL executor at runtime to convert response data into corresponding Swift types.
struct SchemaMetadataTemplate: TemplateRenderer {
  // IR representation of source GraphQL schema.
  let schema: IR.Schema

  let config: ApolloCodegen.ConfigurationContext

  let schemaNamespace: String

  let target: TemplateTarget = .schemaFile(type: .schemaMetadata)

  /// Swift code that can be embedded within a namespace.
  func renderBodyTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString {
    let parentAccessLevel = accessControlRenderer(for: .parent).render()

    return TemplateString(
    """
    \(if: !config.output.schemaTypes.isInModule,
      TemplateString("""
      \(parentAccessLevel)typealias SelectionSet = \(schemaNamespace)_SelectionSet

      \(parentAccessLevel)typealias InlineFragment = \(schemaNamespace)_InlineFragment

      \(parentAccessLevel)typealias MutableSelectionSet = \(schemaNamespace)_MutableSelectionSet

      \(parentAccessLevel)typealias MutableInlineFragment = \(schemaNamespace)_MutableInlineFragment
      """),
    else: protocolDefinition(prefix: nil, schemaNamespace: schemaNamespace))

    \(documentation: schema.documentation, config: config)
    \(config.nonisolatedModifier)\(parentAccessLevel)enum SchemaMetadata: \(TemplateConstants.ApolloAPITargetName).SchemaMetadata {
      \(accessControlRenderer(for: .member).render())\
    static let configuration: any \(TemplateConstants.ApolloAPITargetName).SchemaConfiguration.Type = SchemaConfiguration.self

      \(objectTypeFunction)
    }

    \(config.nonisolatedModifier)\(parentAccessLevel)enum Objects {}
    \(config.nonisolatedModifier)\(parentAccessLevel)enum Interfaces {}
    \(config.nonisolatedModifier)\(parentAccessLevel)enum Unions {}

    """
    )
  }

  var objectTypeFunction: TemplateString {
    let spiAccessLevel = accessControlRenderer(for: .member).render(withSPIs: [.Execution])

    return """
    private static let objectTypeMap: [String: \(TemplateConstants.ApolloAPITargetName).Object] = [
      \(schema.referencedTypes.objects.map {
        "\"\($0.name.schemaName)\": \(schemaNamespace).Objects.\($0.render(as: .typename()))"
      }, separator: ",\n")
    ]

    \(spiAccessLevel)\
    static func objectType(forTypename typename: String) -> \(TemplateConstants.ApolloAPITargetName).Object? {
      objectTypeMap[typename]
    }
    """
  }
  /// Swift code that must be rendered outside of any namespace.
  func renderDetachedTemplate(
    nonFatalErrorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) -> TemplateString? {
    guard !config.output.schemaTypes.isInModule else { return nil }

    return protocolDefinition(prefix: "\(schemaNamespace)_", schemaNamespace: schemaNamespace)
  }

  init(schema: IR.Schema, config: ApolloCodegen.ConfigurationContext) {
    self.schema = schema
    self.schemaNamespace = config.schemaNamespace.firstUppercased
    self.config = config
  }

  private func protocolDefinition(prefix: String?, schemaNamespace: String) -> TemplateString {
    let accessLevel = accessControlRenderer(for: .member).render()

    let nonisolated = config.nonisolatedModifier

    return TemplateString("""
      \(nonisolated)\(accessLevel)protocol \(prefix ?? "")SelectionSet: \(TemplateConstants.ApolloAPITargetName).SelectionSet & \(TemplateConstants.ApolloAPITargetName).RootSelectionSet
      where Schema == \(schemaNamespace).SchemaMetadata {}

      \(nonisolated)\(accessLevel)protocol \(prefix ?? "")InlineFragment: \(TemplateConstants.ApolloAPITargetName).SelectionSet & \(TemplateConstants.ApolloAPITargetName).InlineFragment
      where Schema == \(schemaNamespace).SchemaMetadata {}

      \(nonisolated)\(accessLevel)protocol \(prefix ?? "")MutableSelectionSet: \(TemplateConstants.ApolloAPITargetName).MutableRootSelectionSet
      where Schema == \(schemaNamespace).SchemaMetadata {}

      \(nonisolated)\(accessLevel)protocol \(prefix ?? "")MutableInlineFragment: \(TemplateConstants.ApolloAPITargetName).MutableSelectionSet & \(TemplateConstants.ApolloAPITargetName).InlineFragment
      where Schema == \(schemaNamespace).SchemaMetadata {}
      """
    )
  }
}
