import Foundation
import GraphQLCompiler
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers

extension GraphQLJSFrontend {

  public func compile(
    schema: String,
    document: String,
    config: ApolloCodegen.ConfigurationContext
  ) async throws -> CompilationResult {
    async let schemaSource = try makeSource(schema, filePath: "")
    async let documentSource = try makeSource(document, filePath: "")

    let schema = try await loadSchema(from: [schemaSource])
    let document = try await parseDocument(documentSource)

    return try await compile(
      schema: schema,
      document: document,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schema: String,
    document: String
  ) async throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try await compile(
      schema: schema,
      document: document,
      config: config
    )
  }

  public func compile(
    schema: String,
    documents: [String],
    config: ApolloCodegen.ConfigurationContext
  ) async throws -> CompilationResult {
    async let schemaSource = try makeSource(schema, filePath: "")

    let sources: [GraphQLSource] = try await documents.enumerated().asyncMap {
      try await makeSource($0.element, filePath: "Doc_\($0.offset)")
    }

    return try await compile(
      schema: schemaSource,
      definitions: sources,
      config: config
    )
  }

  public func compile(
    schema schemaSource: GraphQLSource,
    definitions: [GraphQLSource],
    config: ApolloCodegen.ConfigurationContext
  ) async throws -> CompilationResult {
    let schema = try await loadSchema(from: [schemaSource])

    let documents: [GraphQLDocument] = try await definitions.asyncMap {
      return try await parseDocument($0)
    }

    let mergedDocument = try await mergeDocuments(documents)
    return try await compile(
      schema: schema,
      document: mergedDocument,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schema: String,
    documents: [String]
  ) async throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try await compile(
      schema: schema,
      documents: documents,
      config: config
    )
  }

  public func compile(
    schemaJSON: String,
    document: String,
    config: ApolloCodegen.ConfigurationContext
  ) async throws -> CompilationResult {
    async let documentSource = try makeSource(document, filePath: "")
    async let schemaSource = try makeSource(schemaJSON, filePath: "schema.json")

    let schema = try await loadSchema(from: [schemaSource])
    let document = try await parseDocument(documentSource)

    return try await compile(
      schema: schema,
      document: document,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schemaJSON: String,
    document: String
  ) async throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try await compile(
      schemaJSON: schemaJSON,
      document: document,
      config: config
    )
  }

}
