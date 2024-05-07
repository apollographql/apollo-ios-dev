import Nimble
import Apollo
import ApolloAPI

public func equalJSONValue(_ expectedValue: JSONEncodable?) -> Matcher<JSONEncodable> {
  return Matcher { actual in
    let msg = ExpectationMessage.expectedActualValueTo("equal <\(stringify(expectedValue))>")
    if let actualValue = try actual.evaluate(), let expectedValue = expectedValue {
      return MatcherResult(
          bool: actualValue._jsonValue == expectedValue._jsonValue,
          message: msg
        )
    } else {
      return MatcherResult(
        status: .fail,
        message: msg.appendedBeNilHint()
      )
    }
  }
}

extension AnyHashable: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (AnyHashable, AnyHashable)...) {
    self.init(Dictionary(elements))
  }
}

extension AnyHashable: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: AnyHashable...) {
    self.init(elements)
  }
}
