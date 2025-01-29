import GraphQLCompiler

extension GraphQLCompositeType {
  /// Indicates if the type has a single keyField named `id`.
  var isIdentifiable: Bool {
    switch(self) {
    case let interface as GraphQLInterfaceType:
      return interface.keyFields == ["id"]

    case let object as GraphQLObjectType:
      return object.keyFields == ["id"]

    default:
      return false
    }
  }
}
