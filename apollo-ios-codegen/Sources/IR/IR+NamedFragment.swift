import GraphQLCompiler
import OrderedCollections

public class NamedFragment: Definition, Hashable, CustomDebugStringConvertible {
  public let definition: CompilationResult.FragmentDefinition
  public let rootField: EntityField

  /// All of the fragments that are referenced by this fragment's selection set.
  public let referencedFragments: OrderedSet<NamedFragment>

  /// All of the Entities that exist in the fragment's selection set,
  /// keyed by their relative location (ie. path) within the fragment.
  ///
  /// - Note: The FieldPath for an entity within a fragment will begin with a path component
  /// with the fragment's name and type.
  public let entityStorage: DefinitionEntityStorage

  /// `True` if any selection set, or nested selection set, within the fragment contains any
  /// fragment marked with the `@defer` directive.
  public let containsDeferredFragment: Bool

  public var name: String { definition.name }
  public var type: GraphQLCompositeType { definition.type }
  public var isLocalCacheMutation: Bool { definition.isLocalCacheMutation }
  
  /// Indicates if the parent type has a single keyField named `id`.
  public var isIdentifiable: Bool {
    guard definition.selectionSet.selections.contains(where: {
      guard case .field(let field) = $0 else { return false }
      return field.name == "id"
    }) else { return false }
    
    switch(type) {
    case let interface as GraphQLInterfaceType:
      return interface.keyFields == ["id"]
    case let object as GraphQLObjectType:
      return object.keyFields == ["id"]
    default:
      return false
    }
  }

  init(
    definition: CompilationResult.FragmentDefinition,
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

  public static func == (lhs: NamedFragment, rhs: NamedFragment) -> Bool {
    lhs.definition == rhs.definition &&
    lhs.rootField === rhs.rootField
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(definition)
    hasher.combine(ObjectIdentifier(rootField))
  }

  public var debugDescription: String {
    definition.debugDescription
  }
}
