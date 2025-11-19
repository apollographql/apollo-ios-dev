import Foundation
import TemplateString
import OrderedCollections
import IR

extension ApolloCodegen {
  /// Errors that can occur during code generation. These are fatal errors that prevent the code
  /// generation from continuing execution.
  public enum Error: Swift.Error, LocalizedError {
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
    case fieldMergingIncompatibility

    public var errorDescription: String? {
      switch self {
      case let .graphQLSourceValidationFailure(lines):
        return """
          An error occured during validation of the GraphQL schema or operations! Check:
              \(lines.joined(separator: "\n    "))
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
      case .fieldMergingIncompatibility:
        return """
          Options for disabling 'fieldMerging' and enabling 'selectionSetInitializers' are
          incompatible.

          Please set either 'fieldMerging' to 'all' or 'selectionSetInitializers' to be empty.
          """
      }
    }
  }

  /// Errors that may occur during code generation that are not fatal. If these errors are present,
  /// the generated files will likely not compile correctly. Code generation execution can continue,
  /// but these errors should be surfaced to the user.
  public enum NonFatalError: Equatable, Sendable {
    case typeNameConflict(name: String, conflictingName: String, containingObject: String)

    var errorTypeName: String {
      switch self {
      case .typeNameConflict(_, _, _):
        return "TypeNameConflict"
      }
    }

    public var failureReason: String {
      switch self {
      case let .typeNameConflict(name, conflictingName, containingObject):
        return "Field '\(conflictingName)' conflicts with field '\(name)' in GraphQL definition `\(containingObject)`."
      }
    }

    public var recoverySuggestion: String {
      switch self {
      case .typeNameConflict(_, _, _):
        return """
          It is recommended to use a field alias for one of these fields to resolve this conflict.
          For more info see: https://www.apollographql.com/docs/ios/troubleshooting/codegen-troubleshooting#typenameconflict
          """
      }
    }

    public var errorDescription: String? {
      return "\(errorTypeName): \(failureReason)"
    }

    class Recorder {
      var recordedErrors: [NonFatalError] = []

      func record(error: NonFatalError) { recordedErrors.append(error) }
    }    
  }

  public struct NonFatalErrors: Swift.Error, LocalizedError {
    public typealias FileName = String
    public typealias ErrorsByFile = OrderedDictionary<FileName, [NonFatalError]>
    public typealias DefinitionEntry = (FileName, [NonFatalError])

    public internal(set) var errorsByFile: ErrorsByFile

    init(
      errorsByFile: ErrorsByFile = [:]
    ) {
      self.errorsByFile = errorsByFile
    }

    mutating func merge(_ other: NonFatalErrors) {
      errorsByFile.merge(other.errorsByFile) { _, new in new }
    }

    public var isEmpty: Bool { errorsByFile.isEmpty }

    public var errorDescription: String? {
      var recoverySuggestionsByErrorType: OrderedDictionary<String, String> = [:]

      return TemplateString(
        """
        \(errorsByFile.map {
          """
          - \($0.key):
            - \($0.value.compactMap {
                recoverySuggestionsByErrorType[$0.errorTypeName] = $0.recoverySuggestion
                return $0.errorDescription
            })
          """
        }, separator: "\n")
        """
      ).description
    }
  }
}
