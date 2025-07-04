import GraphQLCompiler
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
  func render() -> TemplateString? {
    let deferredFragmentPathTypeInfo = DeferredFragmentsPathTypeInfo(
      from: operation.rootField.selectionSet.selections
    )
    guard !deferredFragmentPathTypeInfo.isEmpty else { return nil }

    return """

    // MARK: - Deferred Fragment Metadata

    \(DeferredFragmentIdentifiersTemplate(deferredFragmentPathTypeInfo))

    \(DeferredFragmentsPropertyTemplate(deferredFragmentPathTypeInfo))
    """
  }

  fileprivate func DeferredFragmentIdentifiersTemplate(
    _ deferredFragmentPathTypeInfo: [DeferredPathTypeInfo]
  ) -> TemplateString {
    """
    enum DeferredFragmentIdentifiers {
    \(deferredFragmentPathTypeInfo.unique(by: { $0.pathDeferConditionHash }).map {
      return """
        static let \($0.deferCondition.label) = DeferredFragmentIdentifier(label: \"\($0.deferCondition.label)\", fieldPath: [\
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
    public static var deferredFragments: [DeferredFragmentIdentifier: any \(config.ApolloAPITargetName).SelectionSet.Type]? {[
    \(deferredFragmentPathTypeInfo.map {
      return """
        DeferredFragmentIdentifiers.\($0.deferCondition.label): \($0.typeName).self,
      """
    }, separator: "\n")
    ]}
    """
  }

  // MARK: Helpers

  fileprivate struct DeferredPathTypeInfo {
    let path: [String]
    let deferCondition: CompilationResult.DeferCondition
    let typeName: String

    /// Provides a hash value that is a combination of `path` and `deferCondition` values only, `typeName` is not
    /// included.
    ///
    /// This is intended to be used when the selection set type does not matter, such as when generating a deferred
    /// fragment identifier which is shared amongst all child selection set types within a deferred fragment.
    ///
    /// - Returns: Hash value of `path` and `deferCondition`.
    var pathDeferConditionHash: Int {
      var hasher = Hasher()

      hasher.combine(path)
      hasher.combine(deferCondition)

      return hasher.finalize()
    }
  }

  fileprivate func DeferredFragmentsPathTypeInfo(
    from directSelections: DirectSelections?,
    path: [String] = []
  ) -> [DeferredPathTypeInfo] {
    guard let directSelections, !directSelections.isEmpty else { return [] }

    var deferredPathTypeInfo: [DeferredPathTypeInfo] = []

    for field in directSelections.fields.values {
      if let field = field as? EntityField {
        let fieldPath = path + [(field.alias ?? field.name)]
        deferredPathTypeInfo.append(contentsOf:
          DeferredFragmentsPathTypeInfo(from: field.selectionSet.selections, path: fieldPath)
        )
      }
    }

    for fragment in directSelections.inlineFragments.values {
      if let deferCondition = fragment.typeInfo.deferCondition {
        let selectionSetName = SelectionSetNameGenerator.generatedSelectionSetName(
          for: fragment.typeInfo,
          format: .omittingRoot,
          pluralizer: config.pluralizer
        )

        deferredPathTypeInfo.append(DeferredPathTypeInfo(
          path: path,
          deferCondition: deferCondition,
          typeName: "Data.\(selectionSetName)"
        ))
      }

      deferredPathTypeInfo.append(contentsOf:
        DeferredFragmentsPathTypeInfo(from: fragment.selectionSet.selections, path: path)
      )
    }

    for fragment in directSelections.namedFragments.values {
      if let deferCondition = fragment.typeInfo.deferCondition {
        deferredPathTypeInfo.append(DeferredPathTypeInfo(
          path: path,
          deferCondition: deferCondition,
          typeName: fragment.definition.name.asFragmentName
        ))
      }

      deferredPathTypeInfo.append(contentsOf:
        DeferredFragmentsPathTypeInfo(
          from: fragment.fragment.rootField.selectionSet.selections,
          path: path
        )
      )
    }

    return deferredPathTypeInfo
  }
}

fileprivate extension Sequence where Element == DeferredFragmentsMetadataTemplate.DeferredPathTypeInfo {
  func unique<T: Hashable>(by keyForValue: (Iterator.Element) throws -> T) rethrows -> [Iterator.Element] {
    var seen: Set<T> = []
    return try filter { try seen.insert(keyForValue($0)).inserted }
  }
}
