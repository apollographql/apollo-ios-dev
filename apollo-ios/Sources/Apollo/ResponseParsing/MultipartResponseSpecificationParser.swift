import Foundation

/// A protocol that multipart response parsers must conform to in order to be added to the list of
/// available response specification parsers.
protocol MultipartResponseSpecificationParser {
  /// The specification string matching what is expected to be received in the `Content-Type` header
  /// in an HTTP response.
  static var protocolSpec: String { get }

  /// Called to process each chunk in a multipart response.
  ///
  /// The return value is a `Result` type that indicates whether the chunk was successfully parsed
  /// or not. It is possible to return `.success` with a `nil` data value. This should only happen
  /// when the chunk was successfully parsed but there is no action to take on the message, such as
  /// a heartbeat message. Successful results with a `nil` data value will not be returned to the
  /// user.
  static func parse(_ chunk: String) -> Result<Data?, any Error>
}

extension MultipartResponseSpecificationParser {
  static var dataLineSeparator: StaticString { "\r\n\r\n" }
}
