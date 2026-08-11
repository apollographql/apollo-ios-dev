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
  /// The result always begins with a capital letter: the name is `firstUppercased` again after
  /// the rules run, so a rule that lowercases the leading word segment affects only the rest of
  /// that segment.
  ///
  /// Only the generated Swift type name is affected — the operation's ``name`` (used for the
  /// `operationName` literal and everything sent to the server) is never changed.
  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    capitalizer.apply(to: generatedDefinitionName).firstUppercased
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

  /// The generated type name with any configured capitalization rules applied.
  ///
  /// Equivalent to `asFragmentName(capitalizer:)` on ``name``: the result always begins with a
  /// capital letter, and names that collide with reserved type names are suffixed with
  /// `_Fragment`.
  func generatedDefinitionName(capitalizer: Capitalizer) -> String {
    name.asFragmentName(capitalizer: capitalizer)
  }

  /// The name of the generated file for the fragment.
  ///
  /// Matches ``generatedDefinitionName(capitalizer:)`` except that the reserved type name
  /// `_Fragment` suffix never appears in file names, mirroring schema types, whose file names
  /// also omit their reserved name suffixes (`render(as: .filename)`).
  func generatedFileName(capitalizer: Capitalizer) -> String {
    name.asNormalizedFragmentName(capitalizer: capitalizer)
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
