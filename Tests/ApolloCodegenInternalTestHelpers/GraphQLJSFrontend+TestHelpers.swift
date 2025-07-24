import Foundation
import GraphQLCompiler
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers

extension GraphQLJSFrontend {

  public func compile(
    schema: String,
    document: String,
    config: ApolloCodegen.ConfigurationContext
  ) throws -> CompilationResult {
    let schemaSource = try makeSource(schema, filePath: "")
    let documentSource = try makeSource(document, filePath: "")

    let schema = try loadSchema(from: [schemaSource])
    let document = try parseDocument(documentSource)

    return try compile(
      schema: schema,
      document: document,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schema: String,
    document: String
  ) throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try compile(
      schema: schema,
      document: document,
      config: config
    )
  }

  public func compile(
    schema: String,
    documents: [String],
    config: ApolloCodegen.ConfigurationContext
  ) throws -> CompilationResult {
    let schemaSource = try makeSource(schema, filePath: "")

    let sources: [GraphQLSource] = try documents.enumerated().map {
      try makeSource($0.element, filePath: "Doc_\($0.offset)")
    }

    return try compile(
      schema: schemaSource,
      definitions: sources,
      config: config
    )
  }

  public func compile(
    schema schemaSource: GraphQLSource,
    definitions: [GraphQLSource],
    config: ApolloCodegen.ConfigurationContext
  ) throws -> CompilationResult {
    let schema = try loadSchema(from: [schemaSource])

    let documents: [GraphQLDocument] = try definitions.map {
      return try parseDocument($0)
    }

    let mergedDocument = try mergeDocuments(documents)
    return try compile(
      schema: schema,
      document: mergedDocument,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schema: String,
    documents: [String]
  ) throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try compile(
      schema: schema,
      documents: documents,
      config: config
    )
  }

  public func compile(
    schemaJSON: String,
    document: String,
    config: ApolloCodegen.ConfigurationContext
  ) throws -> CompilationResult {
    let documentSource = try makeSource(document, filePath: "")
    let schemaSource = try makeSource(schemaJSON, filePath: "schema.json")

    let schema = try loadSchema(from: [schemaSource])
    let document = try parseDocument(documentSource)

    return try compile(
      schema: schema,
      document: document,
      reduceGeneratedSchemaTypes: false,
      validationOptions: ValidationOptions(config: config)
    )
  }

  public func compile(
    schemaJSON: String,
    document: String
  ) throws -> CompilationResult {
    let config = ApolloCodegen.ConfigurationContext(config: .mock())

    return try compile(
      schemaJSON: schemaJSON,
      document: document,
      config: config
    )
  }

}
