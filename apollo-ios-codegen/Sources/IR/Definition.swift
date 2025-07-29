/// A top level GraphQL definition, which can be an operation or a named fragment.
public protocol Definition {
  var name: String { get }
  var rootField: EntityField { get }
  var entityStorage: DefinitionEntityStorage { get }
  var isLocalCacheMutation: Bool { get }
}
