import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

public enum JSONConvert {
  
  /// Converts a ``SelectionSet`` into a basic JSON dictionary for use.
  ///
  /// - Returns: A `[String: Any]` JSON dictionary representing the ``SelectionSet``.
  public static func selectionSetToJSONObject(_ selectionSet: some SelectionSet) -> [String: Any] {
    selectionSet.__data.asJSONDictionary()
  }
  
  /// Converts a ``GraphQLResult`` into a basic JSON dictionary for use.
  ///
  /// - Returns: A `[String: Any]` JSON dictionary representing the ``GraphQLResult``.
  public static func graphQLResultToJSONObject<T>(_ result: GraphQLResult<T>) -> [String: Any] {
    result.asJSONDictionary()
  }
}
