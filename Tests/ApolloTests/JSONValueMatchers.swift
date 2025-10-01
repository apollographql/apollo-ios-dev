@testable import Nimble
import Apollo
@_spi(Internal) import ApolloAPI

public func equalJSONValue(_ expectedValue: (any JSONEncodable)?) -> Matcher<any JSONEncodable> {
  equal(expectedValue) { lhs, rhs  in
    AnySendableHashable.equatableCheck(lhs._jsonValue, rhs._jsonValue)
  }
}

@_disfavoredOverload
public func equal(
  _ expectedValue: any Sendable & Hashable
) -> Nimble.Matcher<any Sendable & Hashable> {
  return equal(expectedValue, by: AnySendableHashable.equatableCheck)
}

@_disfavoredOverload
public func equal(
  _ expectedValue: [String: any Sendable & Hashable]
) -> Nimble.Matcher<[String: any Sendable & Hashable]> {
  return equal(expectedValue, by: AnySendableHashable.equatableCheck)
}

@_disfavoredOverload
public func contain(
  _ items: [String: any Sendable & Hashable]...
) -> Matcher<[[String: any Sendable & Hashable]]> {
  contain(items)
}

@_disfavoredOverload
public func contain(
  _ items: [[String: any Sendable & Hashable]]
) -> Matcher<[[String: any Sendable & Hashable]]> {
  return Matcher.simple("contain <\(arrayAsString(items))>") { actualExpression in
    guard let actual = try actualExpression.evaluate() else { return .fail }

    let matches = items.allSatisfy { (item: [String: any Sendable & Hashable]) in
      return actual.contains(where: {
        AnySendableHashable.equatableCheck($0 as any Sendable & Hashable, item as any Sendable & Hashable)
      })
    }
    return MatcherStatus(bool: matches)
  }
}
