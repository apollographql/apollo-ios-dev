import Foundation
@testable import Apollo

extension MultipartFormData {
  
  func toTestString() throws -> String {
    let encodedData = try self.encode()
    let string = String(bytes: encodedData, encoding: .utf8)!

    let crlf = String(data: MultipartResponseParsing.CRLF, encoding: .utf8)!
    // Replacing CRLF with new line as string literals uses new lines
    return string.replacingOccurrences(of: crlf, with: "\n")
  }
}

