import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers
import GraphQLCompiler

class GraphQLNamedType_SwiftTests: XCTestCase {
  func test_swiftName_givenGraphQLScalar_boolean_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.boolean())

    expect(graphqlNamedType.namedType.name.swiftName).to(equal("Bool"))
  }

  func test_swiftName_givenGraphQLScalar_int_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.integer())

    expect(graphqlNamedType.namedType.name.swiftName).to(equal("Int32"))
  }

  func test_swiftName_givenGraphQLScalar_float_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.float())

    expect(graphqlNamedType.namedType.name.swiftName).to(equal("Double"))
  }

  func test_swiftName_givenGraphQLScalar_string_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.string())

    expect(graphqlNamedType.namedType.name.swiftName).to(equal("String"))
  }
}
