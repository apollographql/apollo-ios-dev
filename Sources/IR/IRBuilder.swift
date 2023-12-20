import OrderedCollections
import GraphQLCompiler

public class IRBuilder {

  public let compilationResult: CompilationResult

  public let schema: Schema

  public let fieldCollector = FieldCollector()

  let builtFragmentStorage = BuiltFragmentStorage()

  public init(compilationResult: CompilationResult) {
    self.compilationResult = compilationResult
    self.schema = Schema(
      referencedTypes: .init(
        compilationResult.referencedTypes,
        schemaRootTypes: compilationResult.schemaRootTypes
      ),
      documentation: compilationResult.schemaDocumentation
    )
  }

  public func build(
    operation operationDefinition: CompilationResult.OperationDefinition
  ) async -> Operation {
    let rootField = CompilationResult.Field(
      name: operationDefinition.operationType.rawValue,
      type: .nonNull(.entity(operationDefinition.rootType)),
      selectionSet: operationDefinition.selectionSet
    )

    let rootEntity = Entity(
      source: .operation(operationDefinition)
    )

    let result = await RootFieldBuilder.buildRootEntityField(
      forRootField: rootField,
      onRootEntity: rootEntity,
      inIR: self
    )

    return Operation(
      definition: operationDefinition,
      rootField: result.rootField,
      referencedFragments: result.referencedFragments,
      entityStorage: result.entityStorage,
      containsDeferredFragment: result.containsDeferredFragment
    )
  }

  actor BuiltFragmentStorage {
    enum CacheEntry {
      case inProgress(Task<NamedFragment, Never>)
      case ready(NamedFragment)
    }

    var fragmentCache: [String: CacheEntry] = [:]

    func getFragment(named name: String, builder: @escaping () async -> NamedFragment) async -> NamedFragment {
      if let cachedFragment = fragmentCache[name] {
        switch cachedFragment {
        case let .ready(fragment): return fragment
        case let .inProgress(task): return await task.value
        }
      }

      let task = Task {
        await builder()
      }

      fragmentCache[name] = .inProgress(task)

      let fragment = await task.value
      fragmentCache[name] = .ready(fragment)
      return fragment
    }

    func getFragmentIfBuilt(named name: String) -> NamedFragment? {
      guard case let .ready(cachedFragment) = fragmentCache[name] else {
        return nil
      }
      return cachedFragment
    }
  }

  public func build(
    fragment fragmentDefinition: CompilationResult.FragmentDefinition
  ) async -> NamedFragment {
    await builtFragmentStorage.getFragment(named: fragmentDefinition.name) {
      let rootField = CompilationResult.Field(
        name: fragmentDefinition.name,
        type: .nonNull(.entity(fragmentDefinition.type)),
        selectionSet: fragmentDefinition.selectionSet
      )

      let rootEntity = Entity(
        source: .namedFragment(fragmentDefinition)
      )

      let result = await RootFieldBuilder.buildRootEntityField(
        forRootField: rootField,
        onRootEntity: rootEntity,
        inIR: self
      )

      return NamedFragment(
        definition: fragmentDefinition,
        rootField: result.rootField,
        referencedFragments: result.referencedFragments,
        entityStorage: result.entityStorage,
        containsDeferredFragment: result.containsDeferredFragment
      )
    }
  }

}
