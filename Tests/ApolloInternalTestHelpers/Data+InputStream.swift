import Foundation

extension Data {
  /// Reads all bytes from an `InputStream` into a `Data` instance.
  /// Useful for reading `URLRequest.httpBodyStream` in tests.
  public init(reading input: InputStream) throws {
    self.init()
    input.open()
    defer { input.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while input.hasBytesAvailable {
      let read = input.read(buffer, maxLength: bufferSize)
      if read < 0 {
        throw input.streamError!
      } else if read == 0 {
        break
      }
      self.append(buffer, count: read)
    }
  }
}
