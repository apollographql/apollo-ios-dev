import Foundation

public extension String {
  func crlfFormattedData() -> Data {
    return replacingOccurrences(of: "\n", with: "\r\n").data(using: .utf8)!
  }
}
