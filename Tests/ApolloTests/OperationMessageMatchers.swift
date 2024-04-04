import Foundation
import Nimble
import Apollo
@testable import ApolloWebSocket
import ApolloAPI

public func equalMessage(payload: JSONEncodableDictionary? = nil, id: String? = nil, type: OperationMessage.Types) -> Nimble.Matcher<String> {
  return Nimble.Matcher.define { actualExpression in
    guard let actualValue = try actualExpression.evaluate() else {
      return MatcherResult(
        status: .fail,
        message: .fail("Message cannot be nil - type is a required parameter.")
      )
    }

    let expected = OperationMessage(payload: payload, id: id, type: type)
    guard actualValue == expected.rawMessage! else {
      return MatcherResult(
        status: .fail,
        message: .expectedActualValueTo("equal \(expected)"))
    }

    return MatcherResult(
      status: .matches,
      message: .expectedTo("be equal")
    )
  }
}
