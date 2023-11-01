import Foundation
import ApolloCodegenLib

/// Generic representation of a code generation provider.
public protocol CodegenProvider {
  static func build(
    with configuration: ApolloCodegenConfiguration,
    withRootURL rootURL: URL?,
    itemsToGenerate: ApolloCodegen.ItemsToGenerate,
    operationIdentifierProvider: OperationIdentifierProvider?
  ) async throws
}

extension ApolloCodegen: CodegenProvider {
  public static func build(
    with configuration: ApolloCodegenConfiguration,
    withRootURL rootURL: URL? = nil,
    itemsToGenerate: ItemsToGenerate = [.code]
  ) async throws {
    try await Self.build(
      with: configuration,
      withRootURL: rootURL,
      itemsToGenerate: itemsToGenerate,
      operationIdentifierProvider: nil
    )
  }
}
