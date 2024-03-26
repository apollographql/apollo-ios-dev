@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler
import OrderedCollections
import Utilities

/// This class wraps an `IRBuilder` for so that the built definitions are wrapped in
/// `IRTestWrapper` instances.
///
/// These wrappers are used to make testing `ComputedSelectionSet` easier.
@dynamicMemberLookup
public class IRBuilderTestWrapper {
  public let irBuilder: IRBuilder

  public private(set) lazy var builtFragmentStorage : BuiltFragmentStorage = {
    BuiltFragmentStorage(self.irBuilder.builtFragmentStorage)
  }()

  public init(_ irBuilder: IRBuilder) {
    self.irBuilder = irBuilder
  }

  public func build(
    operation operationDefinition: CompilationResult.OperationDefinition,
    mergingStrategy: IR.MergedSelections.MergingStrategy = .all
  ) async -> IRTestWrapper<IR.Operation> {
    let operation = await irBuilder.build(operation: operationDefinition)
    return IRTestWrapper(
      irObject: operation,
      computedSelectionSetCache: .init(
        mergingStrategy: mergingStrategy,
        entityStorage: operation.entityStorage
      )
    )
  }

  public func build(
    fragment fragmentDefinition: CompilationResult.FragmentDefinition,
    mergingStrategy: IR.MergedSelections.MergingStrategy = .all
  ) async -> IRTestWrapper<IR.NamedFragment> {
    let fragment = await irBuilder.build(fragment: fragmentDefinition)
    return IRTestWrapper(
      irObject: fragment,
      computedSelectionSetCache: .init(
        mergingStrategy: mergingStrategy,
        entityStorage: fragment.entityStorage
      )
    )
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<IRBuilder, T>) -> T {
    irBuilder[keyPath: keyPath]
  }

  public class BuiltFragmentStorage {
    private var wrappedStorage: IRBuilder.BuiltFragmentStorage    

    fileprivate init(_ wrappedStorage: IRBuilder.BuiltFragmentStorage) {
      self.wrappedStorage = wrappedStorage
    }

    public func getFragmentIfBuilt(named name: String) async -> IRTestWrapper<NamedFragment>? {
      guard let fragment = await wrappedStorage.getFragmentIfBuilt(named: name) else {
        return nil
      }

      return IRTestWrapper(
        irObject: fragment,
        computedSelectionSetCache: .init(
          mergingStrategy: .all,
          entityStorage: fragment.entityStorage
        )
      )
    }
  }
}
