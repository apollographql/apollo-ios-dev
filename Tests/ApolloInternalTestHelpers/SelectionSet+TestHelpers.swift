import ApolloAPI
import Apollo

public extension SelectionSet {

  var _rawData: [String: AnyHashable] { self.__data._data }

  func hasNullValue(forKey key: String) -> Bool {
    guard let value = self.__data._data[key] else {
      return false
    }
    return value == DataDict._NullValue
  }

}
