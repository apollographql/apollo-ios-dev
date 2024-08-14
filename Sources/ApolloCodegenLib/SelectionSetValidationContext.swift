import IR

/// A struct that validates that there are no type name conflicts while generating SelectionSet
/// objects.
///
/// This holds onto the names of current referenced types and ensures that no conflicting names
/// will be generated.
///
/// A context is copied and then has new types added to it for each individual child selection set.
struct SelectionSetValidationContext {
  private var referencedTypeNames: [String: String] = [:]
  private let config: ApolloCodegen.ConfigurationContext

  init(config: ApolloCodegen.ConfigurationContext) {
    self.config = config
  }

  mutating func runTypeValidationFor(
    _ selections: IR.ComputedSelectionSet,
    recordingErrorsTo errorRecorder: ApolloCodegen.NonFatalError.Recorder
  ) {
    var locationName: String {
      SelectionSetNameGenerator.generatedSelectionSetName(
        for: selections.typeInfo,
        format: .fullyQualified,
        pluralizer: config.pluralizer
      )
    }

    // Check for type conflicts resulting from singularization/pluralization of fields
    var typeNamesForEntityFields = [String: String]()

    let entityFields = selections.makeFieldIterator() { field in
      field is IR.EntityField
    }

    IteratorSequence(entityFields)
      .lazy.map { unsafeDowncast($0, to: IR.EntityField.self) }
      .forEach { field in
        let formattedTypeName = field.formattedSelectionSetName(with: config.pluralizer)
        if let existingFieldName = typeNamesForEntityFields[formattedTypeName] {
          errorRecorder.record(error:
            ApolloCodegen.NonFatalError.typeNameConflict(
              name: existingFieldName,
              conflictingName: field.name,
              containingObject: locationName
            )
          )
        }
        typeNamesForEntityFields[formattedTypeName] = field.name
      }

    // Combine `parentTypes` and `typeNamesByFormattedTypeName` to check against fragment names and
    // pass into recursive function calls
    referencedTypeNames.merge(typeNamesForEntityFields) { (current, _) in current }

    IteratorSequence(selections.makeNamedFragmentIterator()).forEach { fragmentSpread in
      if let existingTypeName = referencedTypeNames[fragmentSpread.fragment.generatedDefinitionName] {
        errorRecorder.record(error:
          ApolloCodegen.NonFatalError.typeNameConflict(
            name: existingTypeName,
            conflictingName: fragmentSpread.fragment.name,
            containingObject: locationName
          )
        )
      }
    }
  }
}
