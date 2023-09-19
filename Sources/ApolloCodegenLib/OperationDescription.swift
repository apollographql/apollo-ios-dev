import IR
import GraphQLCompiler

public struct OperationDescription {
  public enum OperationType: String, Hashable {
    case query
    case mutation
    case subscription
  }

  public let rawSourceText: String
  public let type: OperationType

  public var name: String { underlyingOperation.definition.name }
  public var filePath: String { underlyingOperation.definition.filePath }

  let underlyingOperation: IR.Operation

  init(operation: IR.Operation) throws {
    guard let type = OperationType(rawValue: operation.definition.operationType.rawValue) else {
      preconditionFailure("Unknown GraphQL operation type: \(operation.definition.operationType.rawValue)")
    }
    self.underlyingOperation = operation
    self.type = type

    var source = operation.definition.source.convertedToSingleLine()
    for fragment in operation.referencedFragments {
      source += #"\n\#(fragment.definition.source.convertedToSingleLine())"#
    }
    self.rawSourceText = source
  }
}
