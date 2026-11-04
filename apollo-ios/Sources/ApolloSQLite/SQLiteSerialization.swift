import Foundation
@_spi(Internal) @_spi(Execution) import Apollo
import ApolloAPI

private let serializedReferenceKey = "$reference"

enum SQLiteSerialization {
  static func serialize(fields: Record.Fields) throws -> Data {
    // Serializes only the field value; the row schema does not carry a
    // per-field `writtenAt` column, so `CachedField.writtenAt` is omitted.
    let jsonObject = try fields.compactMapValues { try serialize(fieldValue: $0.value) }
    return try JSONSerialization.data(withJSONObject: jsonObject, options: [])
  }

  private static func serialize(fieldValue: Record.Value) throws -> Any {
    switch fieldValue {
    case let reference as CacheReference:
      return [serializedReferenceKey: reference.key]
    case let array as [Record.Value]:
      return try array.map { try serialize(fieldValue: $0) }
    default:
      return fieldValue
    }
  }

  static func deserialize(data: Data) throws -> Record.Fields {
    let jsonObject = try JSONSerializationFormat.deserialize(data: data) as JSONObject
    var fields = Record.Fields()
    for (key, value) in jsonObject {
      // The row schema does not carry a per-field `writtenAt`; each
      // value is wrapped in a `CachedField` stamped with `0`.
      let parsed = try deserialize(fieldJSONValue: value)
      fields[key] = CachedField(value: parsed, writtenAt: 0)
    }
    return fields
  }

  private static func deserialize(fieldJSONValue: JSONValue) throws -> Record.Value {
    switch fieldJSONValue {
    case let dictionary as JSONObject:
      guard let reference = dictionary[serializedReferenceKey] as? String else {
        return fieldJSONValue
      }
      return CacheReference(reference)
    case let array as [JSONValue]:
      return try array.map { try deserialize(fieldJSONValue: $0) } as Record.Value
    default:
      return fieldJSONValue
    }
  }
}
