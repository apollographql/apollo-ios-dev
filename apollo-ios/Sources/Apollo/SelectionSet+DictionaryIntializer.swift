@_spi(Internal) import ApolloAPI

public enum RootSelectionSetInitializeError: Error {
  case hasNonHashableValue
}

extension RootSelectionSet {
  /// Initializes a `SelectionSet` with a raw JSON response object.
  ///
  /// The process of converting a JSON response into `SelectionSetData` is done by using a
  /// `GraphQLExecutor` with a`GraphQLSelectionSetMapper` to parse, validate, and transform
  /// the JSON response data into the format expected by `SelectionSet`.
  ///
  /// - Parameters:
  ///   - data: A dictionary representing a JSON response object for a GraphQL object.
  ///   - variables: [Optional] The operation variables that would be used to obtain
  ///                the given JSON response data.
  @_disfavoredOverload
  public init(
    data: [String: Any],
    variables: GraphQLOperation.Variables? = nil
  ) async throws {
    let jsonObject = try Self.convertToJSONValueDict(dict: data)
    try await self.init(data: jsonObject, variables: variables)
  }
  
  /// Convert dictionary type [String: Any] to JSONObject.
  /// - Parameter dict: [String: Any] type dictionary
  /// - Returns: converted JSONObject
  private static func convertToJSONValueDict(dict: [String: Any]) throws -> JSONObject {
    var result = JSONObject()

    for (key, value) in dict {
      result[key] = try convertToJSONValue(value)
    }
    return result
  }

  /// Convert Any type Array to a JSONValue array.
  /// - Parameter array: Any type Array
  /// - Returns: JSONValue array
  private static func convertToJSONValueArray(array: [Any]) throws -> [JSONValue] {
    var result: [JSONValue] = []
    for value in array {
      result.append(try convertToJSONValue(value))
    }
    return result
  }

  private static func convertToJSONValue(_ value: Any) throws -> JSONValue {
    if let array = value as? [Any] {
      return try convertToJSONValueArray(array: array) as JSONValue
    } else if let dict = value as? [String: Any] {
      return try convertToJSONValueDict(dict: dict) as JSONValue
    } else if let jsonEncodable = value as? any JSONEncodable {
      return jsonEncodable._jsonValue
    } else {
      throw RootSelectionSetInitializeError.hasNonHashableValue
    }
  }
}
