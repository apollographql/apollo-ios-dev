@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler
import OrderedCollections
import Utilities

extension IRBuilder {

  public static func mock(
    schema: String,
    document: String
  ) async throws -> IRBuilder {
    let frontend = try await GraphQLJSFrontend()
    let compilationResult = try await frontend.compile(
      schema: schema,
      document: document
    )
    return .mock(compilationResult: compilationResult)
  }

  public static func mock(
    schema: String,
    documents: [String]
  ) async throws -> IRBuilder {
    let frontend = try await GraphQLJSFrontend()
    let compilationResult = try await frontend.compile(
      schema: schema,
      documents: documents
    )
    return .mock(compilationResult: compilationResult)
  }

  public static func mock(
    schemaJSON: String,
    document: String
  ) async throws -> IRBuilder {
    let frontend = try await GraphQLJSFrontend()
    let compilationResult = try await frontend.compile(
      schemaJSON: schemaJSON,
      document: document
    )
    return .mock(compilationResult: compilationResult)
  }

  public static func mock(
    compilationResult: CompilationResult
  ) -> IRBuilder {
    return IRBuilder(compilationResult: compilationResult)    
  }

}

extension IR.NamedFragment {

  public static func mock(
    _ name: String,
    type: GraphQLCompositeType = .mock("MockType"),
    source: String = ""
  ) -> IR.NamedFragment {
    let definition = CompilationResult.FragmentDefinition.mock(name, type: type, source: source)
    let rootField = CompilationResult.Field.mock(name, type: .entity(type))
    let rootEntity = IR.Entity(
      location: .init(source: .namedFragment(definition), fieldPath: nil),
      rootTypePath: LinkedList(type)
    )
    let typeInfo = SelectionSet.TypeInfo(
      entity: rootEntity,
      scopePath: [
        .descriptor(
          forType: type,
          inclusionConditions: nil,
          givenAllTypesInSchema: .init([type], schemaRootTypes: .mock())
        )
      ],
      isUserDefined: true
    )
    let rootEntityField = IR.EntityField.init(
      rootField,
      inclusionConditions: nil,
      selectionSet: .init(
        typeInfo: typeInfo,
        selections: DirectSelections()
      )
    )

    return IR.NamedFragment(
      definition: definition,
      rootField: rootEntityField,
      referencedFragments: [],
      entityStorage: .init(rootEntity: rootEntity),
      containsDeferredFragment: false
    )
  }
}

extension IR.Operation {

  public static func mock(
    definition: CompilationResult.OperationDefinition? = nil,
    referencedFragments: OrderedSet<IR.NamedFragment> = [],
    containsDeferredFragment: Bool = false
  ) -> IR.Operation {
    let definition = definition ?? .mock()
    let entity = IR.Entity(
      location: .init(source: .operation(definition), fieldPath: nil),
      rootTypePath: [.mock()]
    )
    let typeInfo = SelectionSet.TypeInfo(
      entity: entity,
      scopePath: [.descriptor(
        forType: .mock(),
        inclusionConditions: nil,
        givenAllTypesInSchema: .init([], schemaRootTypes: .mock()))
      ],
      isUserDefined: true
    )
    let rootField = IR.EntityField(
      .mock(),
      inclusionConditions: nil,
      selectionSet: .init(
        typeInfo: typeInfo,
        selections: DirectSelections()
      )
    )
    return IR.Operation.init(
      definition: definition,
      rootField: rootField,
      referencedFragments: referencedFragments,
      entityStorage: .init(rootEntity: entity),
      containsDeferredFragment: containsDeferredFragment
    )
  }

  public static func mock(
    name: String,
    type: CompilationResult.OperationType,
    source: String,
    referencedFragments: OrderedSet<IR.NamedFragment> = []
  ) -> IR.Operation {
    let definition = CompilationResult.OperationDefinition.mock(
      name: name,
      type: type,
      source: source,
      referencedFragments: referencedFragments.map(\.definition)
    )

    return IR.Operation.mock(definition: definition, referencedFragments: referencedFragments)
  }
}
