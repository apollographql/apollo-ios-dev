/// A top level GraphQL definition, which can be an operation or a named fragment.
public enum Definition {
  case operation(Operation)
  case namedFragment(NamedFragment)

  var name: String {
    switch self {
    case  let .operation(operation):
      return operation.definition.name
    case let .namedFragment(fragment):
      return fragment.definition.name
    }
  }

  public var rootField: EntityField {
    switch self {
    case  let .operation(operation):
      return operation.rootField
    case let .namedFragment(fragment):
      return fragment.rootField
    }
  }
}
