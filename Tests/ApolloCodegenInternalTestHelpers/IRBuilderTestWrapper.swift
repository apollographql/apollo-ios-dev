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

  public init(_ irBuilder: IRBuilder) {
    self.irBuilder = irBuilder
  }

  public func build(
    operation operationDefinition: CompilationResult.OperationDefinition
  ) async -> IRTestWrapper<IR.Operation> {
    let operation = await irBuilder.build(operation: operationDefinition)
    return IRTestWrapper(irObject: operation, entityStorage: operation.entityStorage)
  }

  public func build(
    fragment fragmentDefinition: CompilationResult.FragmentDefinition
  ) async -> IRTestWrapper<IR.NamedFragment> {
    let fragment = await irBuilder.build(fragment: fragmentDefinition)
    return IRTestWrapper(irObject: fragment, entityStorage: fragment.entityStorage)
  }

  public subscript<T>(dynamicMember keyPath: KeyPath<IRBuilder, T>) -> T {
    irBuilder[keyPath: keyPath]
  }
}
