import Foundation
import ApolloAPI

/// A protocol that multipart response parsers must conform to in order to be added to the list of
/// available response specification parsers.
protocol MultipartResponseSpecificationParser {
  /// The specification string matching what is expected to be received in the `Content-Type` header
  /// in an HTTP response.
  static var protocolSpec: String { get }

  /// Called to process each chunk in a multipart response.
  ///
  /// - Parameter data: Response data for a single chunk of a multipart response as a `String`.
  /// - Returns: A ``JSONObject`` for the parsed chunk.
  ///            It is possible for parsing to succeed and return a `nil` data value.
  ///            This should only happen when the chunk was successfully parsed but there is no
  ///            action to take on the message, such as a heartbeat message. Successful results
  ///            with a `nil` data value will not be returned to the user.
  static func parse(multipartChunk: String) throws -> JSONObject?

}

extension MultipartResponseSpecificationParser {
  static var dataLineSeparator: StaticString { "\r\n\r\n" }
}

/// A `MultipartResponseSpecificationParser` for a specification that provides incremental results
/// should also conform to this protocol to parse the incremental items from the parsed response.
protocol IncrementalResponseSpecificationParser {

  static func parseIncrementalItems(from responseObject: JSONObject) throws -> IncrementalGraphQLResult

}
