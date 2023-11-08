import Foundation
import JavaScriptCore

public final class GraphQLJSFrontend {
  private let bridge: JavaScriptBridge
  private let library: JavaScriptObject
  private let sourceConstructor: JavaScriptObject

  public init() async throws {
    let bridge = try await JavaScriptBridge()
    self.bridge = bridge

    try await bridge.throwingJavaScriptErrorIfNeeded {
      bridge.context.evaluateScript(ApolloCodegenFrontendBundle)
    }

    self.library = await bridge
      .getReferenceOrInitialize(bridge.context.globalObject["ApolloCodegenFrontend"])

    await bridge.register(GraphQLSource.self, forJavaScriptClass: "Source", from: library)
    await bridge.register(GraphQLError.self, from: library)
    await bridge.register(GraphQLSchemaValidationError.self, from: library)
    await bridge.register(GraphQLSchema.self, from: library)
    await bridge.register(GraphQLScalarType.self, from: library)
    await bridge.register(GraphQLEnumType.self, from: library)
    await bridge.register(GraphQLInputObjectType.self, from: library)
    await bridge.register(GraphQLObjectType.self, from: library)
    await bridge.register(GraphQLInterfaceType.self, from: library)
    await bridge.register(GraphQLUnionType.self, from: library)

    self.sourceConstructor = await bridge.getReferenceOrInitialize(library["Source"])
  }

  /// Load a schema by parsing  an introspection result.
  public func loadSchema(from sources: [GraphQLSource]) async throws -> GraphQLSchema {
    return try await library.call("loadSchemaFromSources", with: sources)
  }

  /// Take a loaded GQL schema and print it as SDL.
  public func printSchemaAsSDL(schema: GraphQLSchema) async throws -> String {
      return try await library.call("printSchemaToSDL", with: schema)
    }

  /// Create a `GraphQLSource` object from a string.
  public func makeSource(_ body: String, filePath: String) async throws -> GraphQLSource {
    return try await sourceConstructor.construct(with: body, filePath)
  }

  /// Create a `GraphQLSource` object by reading from a file.
  public func makeSource(from fileURL: URL) async throws -> GraphQLSource {
    precondition(fileURL.isFileURL)

    let body = try String(contentsOf: fileURL)
    return try await makeSource(body, filePath: fileURL.path)
  }

  /// Parses a GraphQL document from a source, returning a reference to the parsed AST that can be passed on to validation and compilation.
  /// Syntax errors will result in throwing a `GraphQLError`.
  public func parseDocument(_ source: GraphQLSource) async throws -> GraphQLDocument {
    return try await library.call("parseOperationDocument", with: source)
  }

  /// Parses a GraphQL document from a file, returning a reference to the parsed AST that can be passed on to validation and compilation.
  /// Syntax errors will result in throwing a `GraphQLError`.
  public func parseDocument(from fileURL: URL) async throws -> GraphQLDocument {
    let source = try await makeSource(from: fileURL)
    return try await parseDocument(source)
  }

  /// Validation and compilation take a single document, but you can merge documents, and operations and fragments will remember their source.
  public func mergeDocuments(_ documents: [GraphQLDocument]) async throws -> GraphQLDocument {
    return try await library.call("mergeDocuments", with: documents)
  }

  /// Validate a GraphQL document and return any validation errors as `GraphQLError`s.
  public func validateDocument(
    schema: GraphQLSchema,
    document: GraphQLDocument,
    validationOptions: ValidationOptions
  ) async throws -> [GraphQLError] {
    return try await library.call(
      "validateDocument",
      with: schema,
      document,
      ValidationOptions.Bridged(from: validationOptions, bridge: self.bridge)
    )
  }

  /// Compiles a GraphQL document into an intermediate representation that is more suitable for analysis and code generation.
  public func compile(
    schema: GraphQLSchema,
    document: GraphQLDocument,
    experimentalLegacySafelistingCompatibleOperations: Bool = false,
    validationOptions: ValidationOptions
  ) async throws -> CompilationResult {
    return try await library.call(
      "compileDocument",
      with: schema,
      document,
      experimentalLegacySafelistingCompatibleOperations,
      ValidationOptions.Bridged(from: validationOptions, bridge: self.bridge)
    )
  }
}
