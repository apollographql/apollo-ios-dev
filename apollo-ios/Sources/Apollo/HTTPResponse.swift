import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

#warning("TODO: Docs Update")
/// Data about a response received by an HTTP request.
public struct HTTPResponse: Sendable {

  /// The `HTTPURLResponse` received from the URL loading system
  public let httpResponse: HTTPURLResponse

  /// The raw data received from the URL loading system.
  ///
  /// If this is an incremental response for a multi-part reponse, the data will only be the data
  /// of the current chunks to parse and return.
  internal let asyncBytes: URLSession.AsyncBytes

  /// Designated initializer
  ///
  /// - Parameters:
  ///   - response: The `HTTPURLResponse` received from the server.
  ///   - rawData: The raw, unparsed data received from the server.
  ///   - parsedResult: [optional] The response parsed into the `ParsedValue` type. Will be nil if not yet parsed,
  ///   or if parsing failed.
  init(
    response: HTTPURLResponse,
    asyncBytes: URLSession.AsyncBytes
  ) {
    self.httpResponse = response
    self.asyncBytes = asyncBytes
  }

}

//// MARK: - Equatable Conformance
//
//extension HTTPResponse: Equatable {
//  public static func == (lhs: HTTPResponse, rhs: HTTPResponse) -> Bool {
//    lhs.httpResponse == rhs.httpResponse &&
//    lhs.rawData == rhs.rawData
//  }
//}
//
//// MARK: - Hashable Conformance
//
//extension HTTPResponse: Hashable {
//  public func hash(into hasher: inout Hasher) {
//    hasher.combine(httpResponse)
//    hasher.combine(rawData)
//  }
//}
