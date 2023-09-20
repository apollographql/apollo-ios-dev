import IR
import GraphQLCompiler

public struct OperationDescription {
  public enum OperationType: String, Hashable {
    case query
    case mutation
    case subscription
  }

  #warning("TODO: Document")
  public let rawSourceText: String
  public let type: OperationType

  public var name: String { underlyingDefinition.name }
  public var filePath: String { underlyingDefinition.filePath }

  let underlyingDefinition: CompilationResult.OperationDefinition

  init(_ operation: CompilationResult.OperationDefinition) throws {
    guard let type = OperationType(rawValue: operation.operationType.rawValue) else {
      preconditionFailure("Unknown GraphQL operation type: \(operation.operationType.rawValue)")
    }
    self.underlyingDefinition = operation
    self.type = type

    var source = operation.source.convertedToSingleLine()
    for fragment in operation.referencedFragments {
      source += #"\n\#(fragment.source.convertedToSingleLine())"#
    }
    self.rawSourceText = source
  }
}
