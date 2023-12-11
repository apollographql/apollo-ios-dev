import IR

#warning("TODO: document")
struct SelectionSetValidationContext {
  private var referencedTypeNames: [String: String] = [:]
  private let config: ApolloCodegen.ConfigurationContext
  let errorRecorder = ErrorRecorder()

  init(config: ApolloCodegen.ConfigurationContext) {
    self.config = config
  }

  class ErrorRecorder {
    var recordedErrors: [ApolloCodegen.Error] = []

    func record(error: ApolloCodegen.Error) {
      recordedErrors.append(error)
    }

    func checkForErrors() throws {
      guard !recordedErrors.isEmpty else { return }

      if recordedErrors.count == 1 {
        throw recordedErrors.first.unsafelyUnwrapped
      }

      throw ApolloCodegen.Error.multipleErrors(recordedErrors)
    }
  }

  mutating func runTypeValidationFor(
    _ selections: IR.ComputedSelectionSet
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

    let entityFields = selections.makeFieldIterator { field in
      field is IR.EntityField
    }

    IteratorSequence(entityFields)
      .lazy.map { unsafeDowncast($0, to: IR.EntityField.self) }
      .forEach { field in
        let formattedTypeName = field.formattedSelectionSetName(with: config.pluralizer)
        if let existingFieldName = typeNamesForEntityFields[formattedTypeName] {
          errorRecorder.record(error:
            ApolloCodegen.Error.typeNameConflict(
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
          ApolloCodegen.Error.typeNameConflict(
            name: existingTypeName,
            conflictingName: fragmentSpread.fragment.name,
            containingObject: locationName
          )
        )
      }
    }
  }
}
