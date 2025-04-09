import Foundation

// MARK: Status extensions
extension HTTPURLResponse {
  var isSuccessful: Bool {
    return (200..<300).contains(statusCode)
  }
}

// MARK: Multipart extensions
extension HTTPURLResponse {
  /// Returns true if the `Content-Type` HTTP header contains the `multipart/mixed` MIME type.
  var isMultipart: Bool {
    return (allHeaderFields["Content-Type"] as? String)?.contains("multipart/mixed") ?? false
  }

  struct MultipartHeaderComponents {
    let media: String?
    let boundary: String?
    let `protocol`: String?

    init(media: String?, boundary: String?, protocol: String?) {
      self.media = media
      self.boundary = boundary
      self.protocol = `protocol`
    }
  }

  /// Components of the `Content-Type` header specifically related to the `multipart` media type.
  var multipartHeaderComponents: MultipartHeaderComponents {
    guard let contentType = allHeaderFields["Content-Type"] as? String else {
      return MultipartHeaderComponents(media: nil, boundary: nil, protocol: nil)
    }

    var media: String? = nil
    var boundary: String? = nil
    var `protocol`: String? = nil

    for component in contentType.components(separatedBy: ";") {
      let directive = component.trimmingCharacters(in: .whitespaces)

      if directive.starts(with: "multipart/") {
        media = directive.components(separatedBy: "/").last
        continue
      }

      if directive.starts(with: "boundary=") {
        if let markerEndIndex = directive.firstIndex(of: "=") {
          var startIndex = directive.index(markerEndIndex, offsetBy: 1)
          if directive[startIndex] == "\"" {
            startIndex = directive.index(after: startIndex)
          }
          var endIndex = directive.index(before: directive.endIndex)
          if directive[endIndex] == "\"" {
            endIndex = directive.index(before: endIndex)
          }

          boundary = String(directive[startIndex...endIndex])
        }
        continue
      }

      if directive.contains("Spec=") {
        `protocol` = directive
        continue
      }
    }

    return MultipartHeaderComponents(media: media, boundary: boundary, protocol: `protocol`)
  }
}

extension URLSession.AsyncBytes {

  public var chunks: AsyncHTTPResponseChunkSequence {
    return AsyncHTTPResponseChunkSequence(self)
  }

}

public struct AsyncHTTPResponseChunkSequence: AsyncSequence {
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

    return response.multipartHeaderComponents?.boundary
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = Data    

    private var underlyingIterator: URLSession.AsyncBytes.AsyncIterator

    private let boundary: Data?

    init(
      _ underlyingIterator: URLSession.AsyncBytes.AsyncIterator,
      boundary: String?
    ) {
      self.underlyingIterator = underlyingIterator
      self.boundary = boundary?.data(using: .utf8)
    }

    public mutating func next() async throws -> Data? {
      var buffer = Data()

      while let next = try await self.underlyingIterator.next() {
        buffer.append(next)

        if let boundary,
            let boundaryRange = buffer.range(of: boundary, options: [.anchored, .backwards]) {
          buffer.removeSubrange(boundaryRange)
          return buffer
        }
      }

      return buffer
    }
  }
}
