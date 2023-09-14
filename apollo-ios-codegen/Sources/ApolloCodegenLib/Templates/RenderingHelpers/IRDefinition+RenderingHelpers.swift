import TemplateString
import GraphQLCompiler

extension IR.Definition {

  func renderedSelectionSetType(_ config: ApolloCodegen.ConfigurationContext) -> TemplateString {
    "\(config.schemaNamespace.firstUppercased).\(if: isMutable, "Mutable")SelectionSet"
  }

  var isMutable: Bool {
    switch self {
    case  let .operation(operation):
      return operation.definition.isLocalCacheMutation
    case let .namedFragment(fragment):
      return fragment.definition.isLocalCacheMutation
    }
  }

  var generatedDefinitionName: String {
    switch self {
    case  let .operation(operation):
      return operation.generatedDefinitionName
    case let .namedFragment(fragment):
      return fragment.generatedDefinitionName
    }
  }

}

extension CompilationResult.OperationDefinition {
  var generatedDefinitionName: String {
    nameWithSuffix.firstUppercased
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

}

extension CompilationResult.FragmentDefinition {
  var generatedDefinitionName: String {
    name.firstUppercased
  }
}

extension IR.NamedFragment {

  var generatedDefinitionName: String {
    definition.generatedDefinitionName
  }

}
