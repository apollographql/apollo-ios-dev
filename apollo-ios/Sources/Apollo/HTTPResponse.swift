import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// Data about a response received by an HTTP request.
public class HTTPResponse<Operation: GraphQLOperation> {
  
  /// The `HTTPURLResponse` received from the URL loading system
  public var httpResponse: HTTPURLResponse
  
  /// The raw data received from the URL loading system
  public var rawData: Data

  /// A list of deferred fragments, by label, that have been fulfilled.
  public var fulfilledFragments: FulfilledFragments

  /// [optional] The data as parsed into a `GraphQLResult`, which can eventually be returned to the UI. Will be nil if not yet parsed.
  public var parsedResponse: GraphQLResult<Operation.Data>?
  
  /// [optional] The data as parsed into a `GraphQLResponse` for legacy caching purposes. If you're not using the `JSONResponseParsingInterceptor`, you probably shouldn't be using this property.
  /// **NOTE:** This property will be removed when the transition to the Swift Codegen is complete.
  public var legacyResponse: GraphQLResponse<Operation.Data>? = nil
  
  /// Designated initializer
  ///
  /// - Parameters:
  ///   - response: The `HTTPURLResponse` received from the server.
  ///   - rawData: The raw, unparsed data received from the server.
  ///   - parsedResponse: [optional] The response parsed into the `ParsedValue` type. Will be nil if not yet parsed, or if parsing failed.
  public init(
    response: HTTPURLResponse,
    rawData: Data,
    fulfilledFragments: FulfilledFragments = .labels([]),
    parsedResponse: GraphQLResult<Operation.Data>?
  ) {
    self.httpResponse = response
    self.rawData = rawData
    self.fulfilledFragments = fulfilledFragments
    self.parsedResponse = parsedResponse
  }
}

// MARK: - Equatable Conformance

extension HTTPResponse: Equatable where Operation.Data: Equatable {
  public static func == (lhs: HTTPResponse<Operation>, rhs: HTTPResponse<Operation>) -> Bool {
    lhs.httpResponse == rhs.httpResponse &&
    lhs.rawData == rhs.rawData &&
    lhs.parsedResponse == rhs.parsedResponse &&
    lhs.legacyResponse == rhs.legacyResponse
  }
}

// MARK: - Hashable Conformance

extension HTTPResponse: Hashable where Operation.Data: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(httpResponse)
    hasher.combine(rawData)
    hasher.combine(parsedResponse)
    hasher.combine(legacyResponse)
  }
}
