import Apollo
import ApolloAPI
import XCTest

/// A `MockGraphQLServer` can be used during tests to check whether expected GraphQL requests are received, and to respond with appropriate test data for a particular request.
///
/// You usually create a  mock server in the test's `setUpWithError`, and use it to initialize a `MockNetworkTransport` that is in turn used  to initialize an `ApolloClient`:
///  ```
/// let server = MockGraphQLServer()
/// let networkTransport = MockNetworkTransport(server: server, store: store)
/// let client = ApolloClient(networkTransport: networkTransport, store: store)
///  ```
/// A mock server should be configured to expect particular operation types, and invokes the passed in request handler when a request of that type comes in. Because the request allows access to `operation`, you can return different responses based on query variables for example:

/// ```
/// let serverExpectation = await server.expect(HeroNameQuery.self) { request in
///   [
///     "data": [
///       "hero": [
///         "name": request.operation.episode == .empire ? "Luke Skywalker" : "R2-D2",
///         "__typename": "Droid"
///       ]
///     ]
///   ]
/// }
/// ```
/// By default, expectations returned from `MockGraphQLServer` only expect to be called once, which is similar to how other built-in expectations work. Unexpected fulfillments will result in test failures. But if multiple fulfillments  are expected, you can use the standard `expectedFulfillmentCount` property to change that. For example, some of the concurrent tests expect the server to receive the same number of request as the number of invoked fetch operations, so in that case we can use:

/// ```
/// serverExpectation.expectedFulfillmentCount = numberOfFetches
/// ```
public actor MockGraphQLServer {
  enum ServerError: Error, CustomStringConvertible {
    case unexpectedRequest(String)

    public var description: String {
      switch self {
      case .unexpectedRequest(let requestDescription):
        return "Mock GraphQL server received an unexpected request: \(requestDescription)"
      }
    }
  }

  public typealias RequestHandler<Operation: GraphQLOperation> = (any GraphQLRequest<Operation>) ->
    JSONObject

  private class RequestExpectation<Operation: GraphQLOperation>: XCTestExpectation, @unchecked Sendable {
    let file: StaticString
    let line: UInt
    let handler: RequestHandler<Operation>

    init(
      description: String,
      file: StaticString = #filePath,
      line: UInt = #line,
      handler: @escaping RequestHandler<Operation>
    ) {
      self.file = file
      self.line = line
      self.handler = handler

      super.init(description: description)
    }
  }

  public init() {}

  // Since RequestExpectation is generic over a specific GraphQLOperation, we can't store these in the dictionary
  // directly. Moreover, there is no way to specify the type relationship that holds between the key and value.
  // To work around this, we store values as Any and use a generic subscript as a type-safe way to access them.
  private var requestExpectations: [AnyHashable: Any] = [:]

  private subscript<Operation: GraphQLOperation>(_ operationType: Operation.Type)
    -> RequestExpectation<Operation>?
  {
    get {
      requestExpectations[ObjectIdentifier(operationType)] as! RequestExpectation<Operation>?
    }

    set {
      requestExpectations[ObjectIdentifier(operationType)] = newValue
    }
  }

  private subscript<Operation: GraphQLOperation>(_ operationType: Operation) -> RequestExpectation<
    Operation
  >? {
    get {
      requestExpectations[operationType] as! RequestExpectation<Operation>?
    }

    set {
      requestExpectations[operationType] = newValue
    }
  }

  public func expect<Operation: GraphQLOperation>(
    _ operationType: Operation.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    requestHandler: @escaping @Sendable RequestHandler<Operation>
  ) -> XCTestExpectation {
    let expectation = RequestExpectation<Operation>(
      description: "Served request for \(String(describing: operationType))",
      file: file,
      line: line,
      handler: requestHandler
    )
    expectation.assertForOverFulfill = true

    self[operationType] = expectation

    return expectation
  }

  public func expect<Operation: GraphQLOperation>(
    _ operation: Operation,
    file: StaticString = #filePath,
    line: UInt = #line,
    requestHandler: @escaping RequestHandler<Operation>
  ) -> XCTestExpectation {
    let expectation = RequestExpectation<Operation>(
      description: "Served request for \(String(describing: operation.self))",
      file: file,
      line: line,
      handler: requestHandler
    )
    expectation.assertForOverFulfill = true

    self[operation] = expectation

    return expectation
  }

  func serve<Operation: GraphQLOperation>(
    request: some GraphQLRequest<Operation>
  ) async throws -> JSONObject {
    if let expectation = self[request.operation] ?? self[type(of: request.operation)] {
      // Dispatch after a small random delay to spread out concurrent requests and simulate somewhat real-world conditions.
      try await Task.sleep(nanoseconds: UInt64.random(in: 10...50) * 1_000_000)
      expectation.fulfill()
      return expectation.handler(request)

    } else {
      throw ServerError.unexpectedRequest(String(describing: type(of: request.operation)))
    }
  }
}
