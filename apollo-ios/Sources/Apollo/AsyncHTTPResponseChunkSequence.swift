import Foundation

extension URLSession.AsyncBytes {

  var chunks: AsyncHTTPResponseChunkSequence {
    return AsyncHTTPResponseChunkSequence(self)
  }

}

public protocol AsyncChunkSequence: AsyncSequence where Element == Data {
  
}

/// An `AsyncSequence` of multipart reponse chunks. This sequence wraps a `URLSession.AsyncBytes`
/// sequence. It uses the multipart boundary specified by the `HTTPURLResponse` to split the data
/// into chunks as it is received.
public struct AsyncHTTPResponseChunkSequence: AsyncChunkSequence {
  public typealias Element = Data

  private let bytes: URLSession.AsyncBytes

  init(_ bytes: URLSession.AsyncBytes) {
    self.bytes = bytes
  }

  public func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(bytes.makeAsyncIterator(), boundary: chunkBoundary)
  }

  private var chunkBoundary: String? {
    guard let response = bytes.task.response as? HTTPURLResponse else {
      return nil
    }

    return response.multipartHeaderComponents.boundary
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = Data

    private var underlyingIterator: URLSession.AsyncBytes.AsyncIterator

    private let boundary: Data?

    /// Carriage Return Line Feed
    private static let CRLF: Data = Data([0x0D, 0x0A]) // "\r\n"

    private static let Delimeter: Data = CRLF + [0x2D, 0x2D] // "\r\n--"

    private static let CloseDelimeter: Data = Data([0x2D, 0x2D]) // "--"

    init(
      _ underlyingIterator: URLSession.AsyncBytes.AsyncIterator,
      boundary: String?
    ) {
      self.underlyingIterator = underlyingIterator

      if let boundaryString = boundary?.data(using: .utf8) {
        self.boundary = Self.Delimeter + boundaryString
      } else {
        self.boundary = nil
      }
    }

    public mutating func next() async throws -> Data? {
      var buffer = Data()

      while let next = try await self.underlyingIterator.next() {
        buffer.append(next)

        if let boundary,
           let boundaryRange = buffer.range(of: boundary, options: [.anchored, .backwards]) {
          buffer.removeSubrange(boundaryRange)

          formatAsChunk(&buffer)

          if !buffer.isEmpty {
            return buffer
          }
        }
      }

      formatAsChunk(&buffer)

      return buffer.isEmpty ? nil : buffer
    }

    private func formatAsChunk(_ buffer: inout Data) {
//      for _ in 0..<2 {
//        if buffer.suffix(Self.CRLF.count) == Self.CRLF {
//          buffer.removeLast(Self.CRLF.count)
//        } else {
//          break
//        }
//      }

      if buffer.prefix(Self.CRLF.count) == Self.CRLF {
        buffer.removeFirst(Self.CRLF.count)
      }

      if buffer == Self.CloseDelimeter {
        buffer.removeAll()
      }
    }
  }
}
