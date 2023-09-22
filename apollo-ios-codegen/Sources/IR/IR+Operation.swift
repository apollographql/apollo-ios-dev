import GraphQLCompiler
import OrderedCollections

public class Operation {
  public let definition: CompilationResult.OperationDefinition

  /// The root field of the operation. This field must be the root query, mutation, or
  /// subscription field of the schema.
  public let rootField: EntityField

  /// All of the fragments that are referenced by this operation's selection set.
  public let referencedFragments: OrderedSet<NamedFragment>

  /// `True` if any selection set, or nested selection set, within the operation contains any
  /// fragment marked with the `@defer` directive.
  public let hasDeferredFragments: Bool

  init(
    definition: CompilationResult.OperationDefinition,
    rootField: EntityField,
    referencedFragments: OrderedSet<NamedFragment>,
    hasDeferredFragments: Bool
  ) {
    self.definition = definition
    self.rootField = rootField
    self.referencedFragments = referencedFragments
    self.hasDeferredFragments = hasDeferredFragments
  }
}
