#if !COCOAPODS
import ApolloAPI
#endif

public enum RootSelectionSetInitializeError: Error {
  case hasNonHashableValue
}

extension RootSelectionSet {
  // Initializes a `SelectionSet` with a raw Dictionary.
  ///
  /// We could pass dictionary object to create a mock object for GraphQL object.
  ///
  /// - Parameters:
  ///   - dict: A dictionary representing a dictionary response for a GraphQL object.
  ///   - variables: [Optional] The operation variables that would be used to obtain
  ///                the given JSON response data.
  @_disfavoredOverload
  public init(
    dict: [String: Any],
    variables: GraphQLOperation.Variables? = nil
  ) throws {
    let jsonObject = try Self.convertDictToJSONObject(dict: dict)
    try self.init(data: jsonObject, variables: variables)
  }

  /// Convert dictionary type [String: Any] to JSONObject
  /// - Parameter dict: dictionary value
  /// - Returns: converted JSONObject
  static func convertDictToJSONObject(dict: [String: Any]) throws -> JSONObject {
    var result = JSONObject()

    for (key, value) in dict {
      if let hashableValue = value as? AnyHashable {
        result[key] = hashableValue
      } else if let dictValue = value as? [String: Any] {
        result[key] = try convertDictToJSONObject(dict: dictValue)
      } else if let dictArrayValue = value as? [[String: Any]] {
        result[key] = try dictArrayValue.map { try convertDictToJSONObject(dict: $0)}
      } else {
        throw RootSelectionSetInitializeError.hasNonHashableValue
      }
    }
    return result
  }
}
