import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

public protocol GraphQLRequest<Operation>: Sendable {
  associatedtype Operation: GraphQLOperation

  /// The endpoint to make a GraphQL request to
  var graphQLEndpoint: URL { get set }

  /// The GraphQL Operation to execute
  var operation: Operation { get set }

  /// Any additional headers you wish to add to this request.
  var additionalHeaders: [String: String] { get set }

  /// The `CachePolicy` to use for this request.
  var cachePolicy: CachePolicy { get }

  /// [optional] A context that is being passed through the request chain.
  var context: (any RequestContext)? { get set }

  func toURLRequest() throws -> URLRequest
}

// MARK: - Helper Functions

extension GraphQLRequest {

  /// Creates a default `URLRequest` for the receiver.
  ///
  /// This can be called within the implementation of `toURLRequest()` and the returned request
  /// can then be modified as necessary before being returned.
  ///
  /// This function creates a `URLRequest` with the following behaviors:
  /// - `url` set to the receiver's `graphQLEndpoint`
  /// - `httpMethod` set to POST
  /// - All header's from `additionalHeaders` added to `allHTTPHeaderFields`
  /// - If the `context` conforms to `RequestContextTimeoutConfigurable`, the `timeoutInterval` is
  /// set to the context's `requestTimeout`.
  ///
  /// - Returns: A `URLRequest` configured as described above.
  public func createDefaultRequest() -> URLRequest {
    var request = URLRequest(url: self.graphQLEndpoint)

    request.httpMethod = GraphQLHTTPMethod.POST.rawValue

    for (fieldName, value) in additionalHeaders {
      request.addValue(value, forHTTPHeaderField: fieldName)
    }

    if let configContext = context as? any RequestContextTimeoutConfigurable {
      request.timeoutInterval = configContext.requestTimeout
    }

    return request
  }

  public mutating func addHeader(name: String, value: String) {
    self.additionalHeaders[name] = value
  }

  public mutating func addHeaders(_ headers: [String: String]) {
    self.additionalHeaders.merge(headers) { (_, new) in new }
  }

  /// A helper method that dds the Apollo client headers to the given request
  /// These header values are used for telemetry to track the source of client requests.
  ///
  /// This should be called during setup of any implementation of `GraphQLRequest` to provide these
  /// header values.
  ///
  /// - Parameters:
  ///   - clientName: The client name. Defaults to the application's bundle identifier + "-apollo-ios".
  ///   - clientVersion: The client version. Defaults to the bundle's short version or build number.
  public mutating func addApolloClientHeaders(
    clientName: String? = Self.defaultClientName,
    clientVersion: String? = Self.defaultClientVersion
  ) {
    additionalHeaders[Self.headerFieldNameApolloClientName] = clientName
    additionalHeaders[Self.headerFieldNameApolloClientVersion] = clientVersion
  }

  /// The field name for the Apollo Client Name header
  static var headerFieldNameApolloClientName: String {
    return "apollographql-client-name"
  }

  /// The field name for the Apollo Client Version header
  static var headerFieldNameApolloClientVersion: String {
    return "apollographql-client-version"
  }

  /// The default client name to use when setting up the `clientName` property
  public static var defaultClientName: String {
    guard let identifier = Bundle.main.bundleIdentifier else {
      return "apollo-ios-client"
    }

    return "\(identifier)-apollo-ios"
  }

  /// The default client version to use when setting up the `clientVersion` property.
  public static var defaultClientVersion: String {
    var version = String()
    if let shortVersion = Bundle.main.shortVersion {
      version.append(shortVersion)
    }

    if let buildNumber = Bundle.main.buildNumber {
      if version.isEmpty {
        version.append(buildNumber)
      } else {
        version.append("-\(buildNumber)")
      }
    }

    if version.isEmpty {
      version = "(unknown)"
    }

    return version
  }

}
