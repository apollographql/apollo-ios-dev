import GraphQLCompiler

extension GraphQLCompositeType {
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
