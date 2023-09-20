import IR
import GraphQLCompiler

public struct OperationDescriptor {
  public enum OperationType: String, Hashable {
    case query
    case mutation
    case subscription
  }

  let underlyingDefinition: CompilationResult.OperationDefinition

  public var name: String { underlyingDefinition.name }

  public var filePath: String { underlyingDefinition.filePath }

  public var type: OperationType {
    guard let type = OperationType(rawValue: underlyingDefinition.operationType.rawValue) else {
      preconditionFailure("Unknown GraphQL operation type: \(underlyingDefinition.operationType.rawValue)")
    }
    return type
  }

#warning("TODO: Document")
  public var rawSourceText: String {
    var source = underlyingDefinition.source.convertedToSingleLine()
    for fragment in underlyingDefinition.referencedFragments {
      source += #"\n\#(fragment.source.convertedToSingleLine())"#
    }
    return source
  }

  init(_ operation: CompilationResult.OperationDefinition) {
    self.underlyingDefinition = operation
  }

}
