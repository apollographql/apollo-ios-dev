import Foundation
import IR
import GraphQLCompiler
import CryptoKit

/// An async closure used to compute the operation identifiers for operations
/// in the persisted queries manifest
public typealias OperationIdentifierProvider = @Sendable (_ operation: OperationDescriptor) async throws -> String

actor OperationIdentifierFactory {

  private enum CacheEntry {
    case inProgress(Task<String, any Error>)
    case ready(String)
  }

  let idProvider: OperationIdentifierProvider

  private var computedIdentifiersCache: [ObjectIdentifier: CacheEntry] = [:]

  init(
    idProvider: @escaping OperationIdentifierProvider = DefaultOperationIdentifierProvider) {
    self.idProvider = idProvider
  }

  func identifier(
    for operation: CompilationResult.OperationDefinition
  ) async throws -> String {
    let operationObjectID = ObjectIdentifier(operation)
    let descriptor = OperationDescriptor(operation)
    if let cached = computedIdentifiersCache[operationObjectID] {
      switch cached {
      case let .ready(identifier): return identifier
      case let .inProgress(task): return try await task.value
      }
    }

    let task = Task {      
      try await idProvider(descriptor)
    }

    computedIdentifiersCache[operationObjectID] = .inProgress(task)

    let identifier = try await task.value
    computedIdentifiersCache[operationObjectID] = .ready(identifier)
    return identifier
  }

}

let DefaultOperationIdentifierProvider =
{ @Sendable (operation: OperationDescriptor) -> String in
  var hasher = SHA256()
  func updateHash(with source: inout String) {
    source.withUTF8({ buffer in
      hasher.update(bufferPointer: UnsafeRawBufferPointer(buffer))
    })
  }
  var definitionSource = operation.sourceText(withFormat: .rawSource)
  updateHash(with: &definitionSource)

  let digest = hasher.finalize()
  return digest.compactMap { String(format: "%02x", $0) }.joined()
}
