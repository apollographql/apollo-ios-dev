import Foundation
import TemplateString

public extension ApolloCodegen {
  /// Errors that can occur during code generation. These are fatal errors that prevent the code
  /// generation from continuing execution.
  enum Error: Swift.Error, LocalizedError {
    /// An error occured during validation of the GraphQL schema or operations.
    case graphQLSourceValidationFailure(atLines: [String])
    case testMocksInvalidSwiftPackageConfiguration
    case inputSearchPathInvalid(path: String)
    case schemaNameConflict(name: String)
    case cannotLoadSchema
    case cannotLoadOperations
    case invalidConfiguration(message: String)
    case invalidSchemaName(_ name: String, message: String)
    case targetNameConflict(name: String)
//    case multipleErrors([ApolloCodegen.Error])

    public var errorDescription: String? {
      switch self {
      case let .graphQLSourceValidationFailure(lines):
        return """
          An error occured during validation of the GraphQL schema or operations! Check \(lines)
          """
      case .testMocksInvalidSwiftPackageConfiguration:
        return """
          Schema Types must be generated with module type 'swiftPackageManager' to generate a \
          swift package for test mocks.
          """
      case let .inputSearchPathInvalid(path):
        return """
          Input search path '\(path)' is invalid. Input search paths must include a file \
          extension component. (eg. '.graphql')
          """
      case let .schemaNameConflict(name):
        return """
          Schema namespace '\(name)' conflicts with name of a type in the generated code. Please \
          choose a different schema name. Suggestions: \(name)Schema, \(name)GraphQL, \(name)API.
          """
      case .cannotLoadSchema:
        return "A GraphQL schema could not be found. Please verify the schema search paths."
      case .cannotLoadOperations:
        return "No GraphQL operations could be found. Please verify the operation search paths."
      case let .invalidConfiguration(message):
        return "The codegen configuration has conflicting values: \(message)"
      case let .invalidSchemaName(name, message):
        return "The schema namespace `\(name)` is invalid: \(message)"
      case let .targetNameConflict(name):
        return """
        Target name '\(name)' conflicts with a reserved library name. Please choose a different \
        target name.
        """
//      case let .multipleErrors(errors):
//        return TemplateString("""
//        \(errors.compactMap(\.errorDescription), separator: "\n------\n")
//        """).description
      }
    }
  }

  /// Errors that may occur during code generation that are not fatal. If these errors are present,
  /// the generated files will likely not compile correctly. Code generation execution can continue,
  /// but these errors should be surfaced to the user.
  enum NonFatalError: Swift.Error, LocalizedError {
    case typeNameConflict(name: String, conflictingName: String, containingObject: String)

    public var errorDescription: String? {
      switch self {
      case let .typeNameConflict(name, conflictingName, containingObject):
        return """
        TypeNameConflict - \
        Field '\(conflictingName)' conflicts with field '\(name)' in GraphQL definition `\(containingObject)`. \
        Recommend using a field alias for one of these fields to resolve this conflict. \
        For more info see: https://www.apollographql.com/docs/ios/troubleshooting/codegen-troubleshooting#typenameconflict
        """
      }
    }

    class Recorder {
      var recordedErrors: [NonFatalError] = []

      func record(error: NonFatalError) {
        recordedErrors.append(error)
      }

  //    func checkForErrors() throws {
  //      guard !recordedErrors.isEmpty else { return }
  //
  //      if recordedErrors.count == 1 {
  //        throw recordedErrors.first.unsafelyUnwrapped
  //      }
  //
  //      throw ApolloCodegen.NonFatalError.multipleErrors(recordedErrors)
  //    }
    }
  }
}
