import IR
import TemplateString

struct DeferredFragmentsMetadataTemplate {

  let operation: IR.Operation
  let config: ApolloCodegen.ConfigurationContext
  let renderAccessControl: () -> String

  init(
    operation: IR.Operation,
    config: ApolloCodegen.ConfigurationContext,
    renderAccessControl: @autoclosure @escaping () -> String
  ) {
    self.operation = operation
    self.config = config
    self.renderAccessControl = renderAccessControl
  }

  // MARK: Templates

  /// Renders metadata definitions for the deferred fragments of an Operation.
  ///
  /// - Returns: The `TemplateString` for the deferred fragments metadata definitions.
  func render() -> TemplateString {
    let deferredFragmentPathTypeInfo = collectDeferredFragmentPathTypeInfo(
      from: operation.rootField.selectionSet.selections
    )
    guard !deferredFragmentPathTypeInfo.isEmpty else { return "" }

    return """

    // MARK: Deferred Fragment Metadata

    \(renderAccessControl())extension \(operation.generatedDefinitionName) {
      \(DeferredFragmentIdentifiersTemplate(deferredFragmentPathTypeInfo))

      \(DeferredFragmentsPropertyTemplate(deferredFragmentPathTypeInfo))
    }
    """
  }

  fileprivate func DeferredFragmentIdentifiersTemplate(
    _ deferredFragmentPathTypeInfo: [DeferredPathTypeInfo]
  ) -> TemplateString {
    """
    enum DeferredFragmentIdentifiers {
    \(deferredFragmentPathTypeInfo.map {
      guard let label = $0.typeInfo.deferCondition?.label else {
        fatalError("Defer condition missing for metadata generation!")
      }

      return """
        static let \(label) = DeferredFragmentIdentifier(label: \"\(label)\", path: [\
      \($0.path.map { "\"\($0)\"" }, separator: ", ")\
      ])
      """
    }, separator: "\n")
    }
    """
  }

  fileprivate func DeferredFragmentsPropertyTemplate(
    _ deferredFragmentPathTypeInfo: [DeferredPathTypeInfo]
  ) -> TemplateString {
    """
    static var deferredFragments: [DeferredFragmentIdentifier: any \(config.ApolloAPITargetName).SelectionSet.Type]? {[
    \(deferredFragmentPathTypeInfo.map {
      guard let label = $0.typeInfo.deferCondition?.label else {
        fatalError("Defer condition missing for metadata generation!")
      }

      let typeName = SelectionSetNameGenerator.generatedSelectionSetName(
        for: $0.typeInfo,
        format: .omittingRoot,
        pluralizer: config.pluralizer
      )

      return """
        DeferredFragmentIdentifiers.\(label): Data.\(typeName).self,
      """
    }, separator: "\n")
    ]}
    """
  }

  // MARK: Helpers

  fileprivate struct DeferredPathTypeInfo {
    let path: [String]
    let typeInfo: SelectionSet.TypeInfo
  }

  fileprivate func collectDeferredFragmentPathTypeInfo(
    from directSelections: DirectSelections?,
    path: [String] = []
  ) -> [DeferredPathTypeInfo] {
    guard let directSelections, !directSelections.isEmpty else { return [] }

    var deferredPathTypeInfo: [DeferredPathTypeInfo] = []

    for field in directSelections.fields.values {
      if let field = field as? EntityField {
        let fieldPath = path + [(field.alias ?? field.name)]
        deferredPathTypeInfo.append(contentsOf:
          collectDeferredFragmentPathTypeInfo(from: field.selectionSet.selections, path: fieldPath)
        )
      }
    }

    for fragment in directSelections.inlineFragments.values {
      if fragment.typeInfo.isDeferred {
        deferredPathTypeInfo.append(DeferredPathTypeInfo(path: path, typeInfo: fragment.typeInfo))
      }

      deferredPathTypeInfo.append(contentsOf:
        collectDeferredFragmentPathTypeInfo(from: fragment.selectionSet.selections, path: path)
      )
    }

    for fragment in directSelections.namedFragments.values {
      deferredPathTypeInfo.append(contentsOf:
        collectDeferredFragmentPathTypeInfo(
          from: fragment.fragment.rootField.selectionSet.selections,
          path: path
        )
      )
    }

    return deferredPathTypeInfo
  }
}
