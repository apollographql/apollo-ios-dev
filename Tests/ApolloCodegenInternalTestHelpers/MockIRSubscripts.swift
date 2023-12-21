@testable import ApolloCodegenLib
@testable import IR
import GraphQLCompiler

extension IR.Schema {
  public subscript(object name: String) -> GraphQLObjectType? {
    return referencedTypes.objects.first { $0.name == name }
  }

  public subscript(interface name: String) -> GraphQLInterfaceType? {
    return referencedTypes.interfaces.first { $0.name == name }
  }

  public subscript(union name: String) -> GraphQLUnionType? {
    return referencedTypes.unions.first { $0.name == name }
  }

  public subscript(scalar name: String) -> GraphQLScalarType? {
    return referencedTypes.scalars.first { $0.name == name }
  }

  public subscript(enum name: String) -> GraphQLEnumType? {
    return referencedTypes.enums.first { $0.name == name }
  }

  public subscript(inputObject name: String) -> GraphQLInputObjectType? {
    return referencedTypes.inputObjects.first { $0.name == name }
  }
}

extension CompilationResult {

  public subscript(type name: String) -> GraphQLNamedType? {
    return referencedTypes.first { $0.name == name }
  }

  public subscript(operation name: String) -> CompilationResult.OperationDefinition? {
    return operations.first { $0.name == name }
  }

  public subscript(fragment name: String) -> CompilationResult.FragmentDefinition? {
    return fragments.first { $0.name == name }
  }
}
