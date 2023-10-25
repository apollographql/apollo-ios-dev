public extension Dictionary {
  static func += (lhs: inout Dictionary, rhs: Dictionary) {
    lhs.merge(rhs) { (_, new) in new }
  }
}

public extension Dictionary where Key == String, Value == Any {
  var asAnyHashable: [String: AnyHashable] {
    var result = [String: AnyHashable]()

    for (key, value) in self {
      if let hashableValue = value as? AnyHashable {
        result[key] = hashableValue
      } else if let dictValue = value as? [String: Any] {
        result[key] = dictValue.asAnyHashable
      }
    }
    return result
  }
}
