import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// Data about a response received by an HTTP request.
public struct HTTPResponse<Operation: GraphQLOperation>: Sendable {
  
  /// The `HTTPURLResponse` received from the URL loading system
  public var httpResponse: HTTPURLResponse
  
  /// The raw data received from the URL loading system
  public var rawData: Data

  /// [optional] The data as parsed into a `GraphQLResult`, which can eventually be returned to the 
  /// UI. Will be nil if not yet parsed.
  public var parsedResult: GraphQLResult<Operation.Data>?
  
  /// A set of cache records from the response
  var cacheRecords: RecordSet?
  
  /// Designated initializer
  ///
  /// - Parameters:
  ///   - response: The `HTTPURLResponse` received from the server.
  ///   - rawData: The raw, unparsed data received from the server.
  ///   - parsedResult: [optional] The response parsed into the `ParsedValue` type. Will be nil if not yet parsed,
  ///   or if parsing failed.
  public init(
    response: HTTPURLResponse,
    rawData: Data,
    parsedResult: GraphQLResult<Operation.Data>?,
    cacheRecords: RecordSet?
  ) {
    self.httpResponse = response
    self.rawData = rawData
    self.parsedResult = parsedResult
    self.cacheRecords = cacheRecords
  }

}

// MARK: - Equatable Conformance

extension HTTPResponse: Equatable where Operation.Data: Equatable {
  public static func == (lhs: HTTPResponse<Operation>, rhs: HTTPResponse<Operation>) -> Bool {
    lhs.httpResponse == rhs.httpResponse &&
    lhs.rawData == rhs.rawData &&
    lhs.parsedResult == rhs.parsedResult &&
    lhs.cacheRecords == rhs.cacheRecords
  }
}

// MARK: - Hashable Conformance

extension HTTPResponse: Hashable where Operation.Data: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(httpResponse)
    hasher.combine(rawData)
    hasher.combine(parsedResult)
    hasher.combine(cacheRecords)
  }
}
