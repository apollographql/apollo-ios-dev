import Foundation
import Testing

extension Data {
  public func jsonString(ignoring ignoredKeys: [String] = []) -> String {
    do {
      var object = try JSONSerialization.jsonObject(with: self, options: [])
      if !ignoredKeys.isEmpty {
        object = (object as? [String: Any?])?
          .filter { !ignoredKeys.contains($0.key) } as Any
      }
      let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
      guard let string = String(data: data, encoding: .utf8) else {
        throw TestError("Invalid JSON data")
      }
      return string
    } catch {
      Issue.record(error)
      return ""
    }
  }

  public func expectToMatch(_ expected: String, ignoring ignoredKeys: [String] = []) {
    let received = jsonString(ignoring: ignoredKeys)
    let expected = expected.utf8Data.jsonString(ignoring: ignoredKeys)
    #expect(expected == received)
  }

  public func expectToMatch(_ expected: String, ignoring ignoredKey: String) {
    expectToMatch(expected, ignoring: [ignoredKey])
  }
}

/// Test decoding the Json data to the given type, encoding it back to Json, and comparing the results.
public func testDecodingEncodingOf<T: Codable>(_ json: String, with _: T.Type) throws {
  let jsonData = json.utf8Data
  let jsonDecoder = JSONDecoder()
  let decoded = try jsonDecoder.decode(T.self, from: jsonData)

  let encoder = JSONEncoder()
  let encoded = try encoder.encode(decoded)

  let value = encoded.jsonString()
  let expected = jsonData.jsonString()

  #expect(expected == value)
}

/// Test that encoding the value gives the expected json, and that decoding the json and re-encoding it doesn't change the value.
public func testDecodingEncoding<T: Codable>(
  of value: T,
  _ json: String,
  decoder: JSONDecoder = JSONDecoder(),
  encoder: JSONEncoder = JSONEncoder())
  throws
{
  // Validate that encoding the value gives the expected json
  try testEncoding(value, json, encoder: encoder)

  // Validate that decoding the json and re-encoding it gives the same json
  let decoded = try decoder.decode(T.self, from: json.utf8Data)
  let encoded = try encoder.encode(decoded)

  let value = encoded.jsonString()
  let expected = json.utf8Data.jsonString()

  #expect(expected == value)
}

/// Test that encoding the value gives the expected json.
public func testEncoding(_ value: some Encodable, _ json: String, encoder: JSONEncoder = JSONEncoder()) throws {
  let encoded = try encoder.encode(value)
  let encodedString = encoded.jsonString()

  // Reformat the json expectation (pretty print, sort keys)
  let jsonData = json.utf8Data
  let expected = jsonData.jsonString()

  #expect(expected == encodedString)
}

/// Test that decoding the json gives the expected value.
public func testDecoding<T: Decodable & Equatable>(_ value: T, _ json: String) throws {
  let decoded = try JSONDecoder().decode(T.self, from: json.utf8Data)
  #expect(decoded == value)
}

/// Test that encoding the value gives the expected json, and that decoding the json gives the expected value.
public func testEncodingDecoding(_ value: some Codable & Equatable, _ json: String) throws {
  try testEncoding(value, json)
  try testDecoding(value, json)
}

public struct TestError: Error {
  public init(_ message: String) {
    self.message = message
  }

  public let message: String
}

extension String {
  public var utf8Data: Data {
    Data(utf8)
  }
}
