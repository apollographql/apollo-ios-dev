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
  /// - Parameter data: Response data for a single chunk of a multipart response.
  /// - Returns: A ``JSONObject`` for the parsed chunk.
  ///            It is possible for parsing to succeed and return a `nil` data value.
  ///            This should only happen when the chunk was successfully parsed but there is no
  ///            action to take on the message, such as a heartbeat message. Successful results
  ///            with a `nil` data value will not be returned to the user.
  static func parse(multipartChunk: Data) throws -> JSONObject?

}

// MARK: - Multipart Parsing Helpers

// In compliance with (RFC 1341 Multipart Content-Type)[https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html]
enum MultipartResponseParsing {
  /// Carriage Return Line Feed
  static let CRLF: Data = Data([0x0D, 0x0A]) // "\r\n"

  static let Delimeter: Data = CRLF + [0x2D, 0x2D] // "\r\n--"

  /// The delimeter that signifies the end of a multipart response.
  ///
  /// This should immediately follow a Delimeter + Boundary.
  static let CloseDelimeter: Data = Data([0x2D, 0x2D]) // "--"


  struct DataLineIterator: IteratorProtocol {
    /// A double carriage return. Used as the seperator between data lines within a multipart response chunk
    private static let DataLineSeparator: Data = CRLF + CRLF // "\r\n\r\n"

    var data: Data

    mutating func next() -> Data? {
      guard !data.isEmpty else { return nil }
      guard let separatorRange = data.firstRange(of: Self.DataLineSeparator) else {
        return data
      }

      let slice = data[data.startIndex..<separatorRange.startIndex]
      data.removeSubrange(data.startIndex..<separatorRange.endIndex)
      return slice
    }
  }

  enum ContentTypeDataLine {
    #warning("TODO: handle Content-Type capitalized also.")
    private static let ContentTypeHeader: Data = "content-type: ".data(using: .utf8)!

    private static let ContentTypeApplicationJSON: Data = "application/json".data(using: .utf8)!

    private static let ContentTypeSeparator: Data = Data([0x3A]) // ":"

    case applicationJSON
    case unknown(value: Data)

    /// Initializes the content type if the line is a content type line.
    ///
    /// Will return `nil` if the line is not a content type line.
    /// Will return `.unknown` if the line is the line is a content type line, but the content type is not
    /// recognized.
    init?(_ line: Data) {
      guard let keyRange = line.firstRange(of: Self.ContentTypeHeader) else {
        return nil
      }

      let value = line[keyRange.endIndex...]
      switch value {
      case Self.ContentTypeApplicationJSON:
        self = .applicationJSON
      default:
        self = .unknown(value: value)
      }
    }

    var valueString: String {
      switch self {
      case .applicationJSON:
        return String(data: Self.ContentTypeApplicationJSON, encoding: .utf8)!

      case .unknown(value: let value):
        return String(data: value, encoding: .utf8)!
      }
    }
  }

}
