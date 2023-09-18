import Foundation
import IR
import CryptoKit

class OperationIdentifierFactory {

  private var computedIdentifiers: [ObjectIdentifier: String] = [:]

  func identifier(for operation: IR.Operation) -> String {
    let operationObjectID = ObjectIdentifier(operation)
    if let identifier = computedIdentifiers[operationObjectID] {
      return identifier
    }

    let identifier = computeIdentifier(for: operation)
    computedIdentifiers[operationObjectID] = identifier
    return identifier
  }

  private func computeIdentifier(for operation: IR.Operation) -> String {
    var hasher = SHA256()
    func updateHash(with source: inout String) {
      source.withUTF8({ buffer in
        hasher.update(bufferPointer: UnsafeRawBufferPointer(buffer))
      })
    }
    var definitionSource = operation.definition.source.convertedToSingleLine()
    updateHash(with: &definitionSource)

    var newline: String
    for fragment in operation.referencedFragments {
      newline = "\n"
      updateHash(with: &newline)
      var fragmentSource = fragment.definition.source.convertedToSingleLine()
      updateHash(with: &fragmentSource)
    }

    let digest = hasher.finalize()
    return digest.compactMap { String(format: "%02x", $0) }.joined()

  }
}
