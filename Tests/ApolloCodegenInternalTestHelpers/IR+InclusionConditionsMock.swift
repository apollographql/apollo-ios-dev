@testable import ApolloCodegenLib
@testable import IR
import OrderedCollections

extension InclusionConditions {

  public static func mock(
    _ conditions: OrderedSet<IR.InclusionCondition>
  ) -> IR.InclusionConditions? {
    let result = IR.InclusionConditions.allOf(conditions)
    return result.conditions
  }

}

extension InclusionCondition: @retroactive ExpressibleByExtendedGraphemeClusterLiteral {}
extension InclusionCondition: @retroactive ExpressibleByUnicodeScalarLiteral {}
extension InclusionCondition: @retroactive ExpressibleByStringLiteral {

  public init(stringLiteral: String) {
    self.init(stringLiteral, isInverted: false)
  }

  public static prefix func !(value: IR.InclusionCondition) -> IR.InclusionCondition {
    value.inverted()
  }

  public static func &&(_ lhs: Self, rhs: Self) -> IR.InclusionConditions.Result {
    IR.InclusionConditions.allOf([lhs, rhs])
  }

}
