import TemplateString
import GraphQLCompiler
import IR

extension IR.Definition {

  func renderedSelectionSetType(_ config: ApolloCodegen.ConfigurationContext) -> TemplateString {
    "\(config.schemaNamespace.firstUppercased).\(if: isMutable, "Mutable")SelectionSet"
  }

  var isMutable: Bool { self.isLocalCacheMutation }

}

extension CompilationResult.OperationDefinition {
  var generatedDefinitionName: String {
    nameWithSuffix.firstUppercased
  }

  /// The generated type name with any configured capitalization rules applied.
  ///
  /// Only the generated Swift type name is affected — the operation's ``name`` (used for the
  /// `operationName` literal and everything sent to the server) is never changed.
  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    capitalizer.apply(to: generatedDefinitionName)
  }

  private var nameWithSuffix: String {
    func getSuffix() -> String {
      if isLocalCacheMutation {
        return "LocalCacheMutation"
      }

      switch operationType {
        case .query: return "Query"
        case .mutation: return "Mutation"
        case .subscription: return "Subscription"
      }
    }

    let suffix = getSuffix()

    guard !name.hasSuffix(suffix) else {
      return name
    }

    return name+suffix
  }
}

extension IR.Operation {

  var generatedDefinitionName: String {
    definition.generatedDefinitionName
  }

  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    definition.generatedDefinitionName(capitalizer: capitalizer)
  }

}

extension CompilationResult.FragmentDefinition {
  var generatedDefinitionName: String {
    name.firstUppercased
  }

  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    capitalizer.apply(to: generatedDefinitionName)
  }
}

extension IR.NamedFragment {

  var generatedDefinitionName: String {
    definition.generatedDefinitionName
  }

  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    definition.generatedDefinitionName(capitalizer: capitalizer)
  }

}
