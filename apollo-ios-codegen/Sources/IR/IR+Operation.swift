import GraphQLCompiler
import OrderedCollections

public class Operation: Definition {
  public let definition: CompilationResult.OperationDefinition

  /// The root field of the operation. This field must be the root query, mutation, or
  /// subscription field of the schema.
  public let rootField: EntityField

  /// All of the fragments that are referenced by this operation's selection set.
  public let referencedFragments: OrderedSet<NamedFragment>

  public let entityStorage: DefinitionEntityStorage

  /// `True` if any selection set, or nested selection set, within the operation contains any
  /// fragment marked with the `@defer` directive.
  public let containsDeferredFragment: Bool

  public var name: String { definition.name }

  public var isLocalCacheMutation: Bool { definition.isLocalCacheMutation }

  init(
    definition: CompilationResult.OperationDefinition,
    rootField: EntityField,
    referencedFragments: OrderedSet<NamedFragment>,
    entityStorage: DefinitionEntityStorage,
    containsDeferredFragment: Bool
  ) {
    self.definition = definition
    self.rootField = rootField
    self.referencedFragments = referencedFragments
    self.entityStorage = entityStorage
    self.containsDeferredFragment = containsDeferredFragment
  }
}

extension Operation: CustomDebugStringConvertible {
  public var debugDescription: String {
    """
    \(definition.debugDescription) {
      \(rootField.debugDescription)
    }
    """
  }
}
