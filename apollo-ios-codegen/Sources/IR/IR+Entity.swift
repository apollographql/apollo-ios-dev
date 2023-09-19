import GraphQLCompiler
import Utilities

/// Represents a concrete entity in an operation or fragment that fields are selected upon.
///
/// Multiple `SelectionSet`s may select fields on the same `Entity`. All `SelectionSet`s that will
/// be selected on the same object share the same `Entity`.
public class Entity {

  /// Represents the location within a GraphQL definition (operation or fragment) of an `Entity`.
  public struct Location: Hashable {
    public enum SourceDefinition: Hashable {
      case operation(CompilationResult.OperationDefinition)
      case namedFragment(CompilationResult.FragmentDefinition)

      var rootType: GraphQLCompositeType {
        switch self {
        case let .operation(definition): return definition.rootType
        case let .namedFragment(definition): return definition.type
        }
      }
    }

    public struct FieldComponent: Hashable {
      public let name: String
      public let type: GraphQLType

      public init(name: String, type: GraphQLType) {
        self.name = name
        self.type = type
      }
    }

    public typealias FieldPath = LinkedList<FieldComponent>

    /// The operation or fragment definition that the entity belongs to.
    public let source: SourceDefinition

    /// The path of fields from the root of the ``source`` definition to the entity.
    ///
    /// Example:
    /// For an operation:
    /// ```graphql
    /// query MyQuery {
    ///   allAnimals {
    ///     predators {
    ///       height {
    ///         ...
    ///       }
    ///     }
    ///   }
    /// }
    /// ```
    /// The `Height` entity would have a field path of [allAnimals, predators, height].
    public let fieldPath: FieldPath?

    func appending(_ fieldComponent: FieldComponent) -> Location {
      let fieldPath = self.fieldPath?.appending(fieldComponent) ?? LinkedList(fieldComponent)
      return Location(source: self.source, fieldPath: fieldPath)
    }

    func appending<C: Collection<FieldComponent>>(_ fieldComponents: C) -> Location {
      let fieldPath = self.fieldPath?.appending(fieldComponents) ?? LinkedList(fieldComponents)
      return Location(source: self.source, fieldPath: fieldPath)
    }

    static func +(lhs: Entity.Location, rhs: FieldComponent) -> Location {
      lhs.appending(rhs)
    }
  }

  /// The selections that are selected for the entity across all type scopes in the operation.
  /// Represented as a tree.
  let selectionTree: EntitySelectionTree

  /// The location within a GraphQL definition (operation or fragment) where the `Entity` is
  /// located.
  public let location: Location

  var rootTypePath: LinkedList<GraphQLCompositeType> { selectionTree.rootTypePath }

  var rootType: GraphQLCompositeType { rootTypePath.last.value }

  init(source: Location.SourceDefinition) {
    self.location = .init(source: source, fieldPath: nil)
    self.selectionTree = EntitySelectionTree(rootTypePath: LinkedList(source.rootType))
  }

  init(
    location: Location,
    rootTypePath: LinkedList<GraphQLCompositeType>
  ) {
    self.location = location
    self.selectionTree = EntitySelectionTree(rootTypePath: rootTypePath)
  }
}
