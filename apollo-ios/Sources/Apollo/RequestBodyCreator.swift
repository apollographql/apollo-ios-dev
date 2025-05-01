#if !COCOAPODS
import ApolloAPI
#endif

public protocol JSONRequestBodyCreator: Sendable {
  /// Creates a `JSONEncodableDictionary` out of the passed-in operation
  ///
  /// - Parameters:
  ///   - request: The `GraphQLRequest` to create the JSON body for.
  ///   - sendQueryDocument: Whether or not to send the full query document. Should default to `true`.
  ///   - autoPersistQuery: Whether to use auto-persisted query information. Should default to `false`.
  /// - Returns: The created `JSONEncodableDictionary`
  func requestBody<Request: GraphQLRequest>(
    for request: Request,
    sendQueryDocument: Bool,
    autoPersistQuery: Bool
  ) -> JSONEncodableDictionary
}

// MARK: - Default Implementation

extension JSONRequestBodyCreator {

  public func requestBody<Request: GraphQLRequest>(
    for request: Request,
    sendQueryDocument: Bool,
    autoPersistQuery: Bool
  ) -> JSONEncodableDictionary {
    var body: JSONEncodableDictionary = [
      "operationName": Request.Operation.operationName,
    ]

    if let variables = request.operation.__variables {
      body["variables"] = variables._jsonEncodableObject
    }

    if sendQueryDocument {
      guard let document = Request.Operation.definition?.queryDocument else {
        preconditionFailure("To send query documents, Apollo types must be generated with `OperationDefinition`s.")
      }
      body["query"] = document
    }

    if autoPersistQuery {
      guard let operationIdentifier = Request.Operation.operationIdentifier else {
        preconditionFailure("To enable `autoPersistQueries`, Apollo types must be generated with operationIdentifiers")
      }

      body["extensions"] = [
        "persistedQuery" : ["sha256Hash": operationIdentifier, "version": 1]
      ]
    }

    return body
  }
}

public struct DefaultRequestBodyCreator: JSONRequestBodyCreator {
  // Internal init methods cannot be used in public methods
  public init() { }
}

// MARK: - Deprecations

@available(*, deprecated, renamed: "JSONRequestBodyCreator")
public typealias RequestBodyCreator = JSONRequestBodyCreator

// Helper struct to create requests independently of HTTP operations.
@available(*, deprecated, renamed: "DefaultRequestBodyCreator")
public typealias ApolloRequestBodyCreator = DefaultRequestBodyCreator
