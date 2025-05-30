@testable import ApolloCodegenLib
@testable import GraphQLCompiler

public extension CompilationResult {

  class func mock(
    rootTypes: RootTypeDefinition = RootTypeDefinition.mock(),
    referencedTypes: [GraphQLNamedType] = [],
    fragments: [CompilationResult.FragmentDefinition] = []
  ) -> CompilationResult {
    CompilationResult(
      schemaRootTypes: rootTypes,
      referencedTypes: referencedTypes + rootTypes.allRootTypes,
      operations: [],
      fragments: fragments,
      schemaDocumentation: nil
    )
  }

}

public extension CompilationResult.RootTypeDefinition {

  class func mock(
    queryName: String = "Query",
    mutationName: String = "Mutation",
    subscriptionName: String = "Subscription"
  ) -> CompilationResult.RootTypeDefinition {
    CompilationResult.RootTypeDefinition(
      queryType: GraphQLObjectType.mock(queryName),
      mutationType: GraphQLObjectType.mock(mutationName),
      subscriptionType: GraphQLObjectType.mock(subscriptionName)
    )
  }
  
}

public extension CompilationResult.OperationDefinition {

  class func mock(
    name: String = "",
    type: CompilationResult.OperationType = .query,
    selections: [CompilationResult.Selection] = [],
    source: String = "",
    referencedFragments: [CompilationResult.FragmentDefinition] = [],
    path: String = ""
  ) -> CompilationResult.OperationDefinition {
    let rootType = type.mockRootType()
    return CompilationResult.OperationDefinition(
      name: name,
      operationType: type,
      variables: [],
      rootType: rootType,
      selectionSet: CompilationResult.SelectionSet(
        parentType: rootType,
        selections: selections
      ),
      directives: nil,
      referencedFragments: referencedFragments,
      source: source,
      filePath: path
    )
  }

}

public extension CompilationResult.OperationType {
  func mockRootType() -> GraphQLCompositeType {
    GraphQLObjectType.mock(rawValue.uppercased())
  }
}

public extension CompilationResult.InlineFragment {

  class func mock(
    parentType: GraphQLCompositeType = GraphQLObjectType.mock(),
    inclusionConditions: [CompilationResult.InclusionCondition]? = nil,
    selections: [CompilationResult.Selection] = [],
    directives: [CompilationResult.Directive] = []
  ) -> CompilationResult.InlineFragment {
    CompilationResult.InlineFragment(
      selectionSet: CompilationResult.SelectionSet(
        parentType: parentType,
        selections: selections
      ),
      inclusionConditions: inclusionConditions,
      directives: directives
    )
  }
}

public extension CompilationResult.SelectionSet {

  class func mock(
    parentType: GraphQLCompositeType = GraphQLObjectType.mock(),
    selections: [CompilationResult.Selection] = []
  ) -> Self {
    Self(
      parentType: parentType,
      selections: selections
    )
  }
}

public extension CompilationResult.Field {

  class func mock(
    _ name: String = "",
    alias: String? = nil,
    arguments: [CompilationResult.Argument]? = nil,
    type: GraphQLType = .entity(GraphQLObjectType.mock("MOCK")),
    selectionSet: CompilationResult.SelectionSet = .mock(),
    deprecationReason: String? = nil
  ) -> Self {
    Self(
      name: name,
      alias: alias,
      arguments: arguments,
      inclusionConditions: nil,
      directives: nil,
      type: type,
      selectionSet: selectionSet,
      deprecationReason: deprecationReason,
      documentation: nil
    )
  }
}

public extension CompilationResult.FragmentDefinition {
  private class func mockDefinition(name: String) -> String {
    return """
    fragment \(name) on Person {
      name
    }
    """
  }

  class func mock(
    _ name: String = "NameFragment",
    type: GraphQLCompositeType = GraphQLObjectType.mock("MOCK"),
    selections: [CompilationResult.Selection] = [],
    source: String = "",
    path: String = ""
  ) -> Self {
    Self(
      name: name,
      type: type,
      selectionSet: .mock(parentType: type, selections: selections),
      directives: nil,
      referencedFragments: [],
      source: source,
      filePath: path,
      overrideAsLocalCacheMutation: false
    )
  }
}

public extension CompilationResult.FragmentSpread {
  class func mock(
    _ fragment: CompilationResult.FragmentDefinition = .mock(),
    inclusionConditions: [CompilationResult.InclusionCondition]? = nil
  ) -> Self {
    Self(
      fragment: fragment,
      inclusionConditions: inclusionConditions,
      directives: nil
    )
  }
}

public extension CompilationResult.Selection {
  static func fragmentSpread(
  _ fragment: CompilationResult.FragmentDefinition,
  inclusionConditions: [CompilationResult.InclusionCondition]? = nil
  ) -> CompilationResult.Selection {
    .fragmentSpread(CompilationResult.FragmentSpread.mock(
      fragment,
      inclusionConditions: inclusionConditions
    ))
  }
}


public extension CompilationResult.VariableDefinition {
  static func mock(
    _ name: String,
    type: GraphQLType,
    defaultValue: GraphQLValue?
  ) -> Self {
    Self(
      name: name,
      type: type,
      defaultValue: defaultValue
    )
  }
}

public extension CompilationResult.Directive {
  static func mock(
    _ name: String,
    arguments: [CompilationResult.Argument]? = nil
  ) -> Self {
    Self(
      name: name,
      arguments: arguments
    )    
  }
}

public extension CompilationResult.Argument {
  static func mock(
    _ name: String,
    value: GraphQLValue
  ) -> Self {
    Self(
      name: name,
      type: .nonNull(.string()),
      value: value,
      deprecationReason: nil
    )
  }
}
