import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers
import GraphQLCompiler

class GraphQLNamedType_RenderContext_Tests: XCTestCase {
  func test_renderAs_typeName_givenGraphQLScalar_boolean_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.boolean()).namedType

    let rendered = graphqlNamedType.render(as: .typename())
    expect(rendered).to(equal("Bool"))
  }

  func test_renderAs_typeName_givenGraphQLScalar_float_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.float()).namedType

    let rendered = graphqlNamedType.render(as: .typename())
    expect(rendered).to(equal("Double"))
  }

  func test_renderAs_typeName_givenGraphQLScalar_string_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.string()).namedType

    let rendered = graphqlNamedType.render(as: .typename())
    expect(rendered).to(equal("String"))
  }

  func test_renderAs_typeName_givenGraphQLScalar_int_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.integer()).namedType

    let rendered = graphqlNamedType.render(as: .typename())
    expect(rendered).to(equal("Int"))
  }

  func test_renderAs_typeName_inInputValue_givenGraphQLScalar_int_providesCompatibleSwiftName() {
    let graphqlNamedType = GraphQLType.scalar(.integer()).namedType

    let rendered = graphqlNamedType.render(as: .typename(isInputValue: true))
    expect(rendered).to(equal("Int32"))
  }
}
