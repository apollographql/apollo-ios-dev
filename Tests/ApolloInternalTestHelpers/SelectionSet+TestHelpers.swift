import ApolloAPI
import Apollo
import Foundation

public extension SelectionSet {

  var _rawData: [String: DataDict.FieldValue] { self.__data._data }

  func hasNullValue(forKey key: String) -> Bool {
    guard let value = self.__data._data[key] else {
      return false
    }
    return value is NSNull
  }

}
