import Foundation
import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
import IR
import Utilities
@testable import ApolloCodegenLib

class IRInputObjectTests: XCTestCase {

  var subject: GraphQLInputObjectType!
  var schemaSDL: String!
  var document: String!

  override func tearDown() {
    subject = nil
    schemaSDL = nil
    document = nil

    super.tearDown()
  }

  // MARK: - Helpers

  func buildSubject() async throws {
    let ir: IRBuilder = try await .mock(schema: schemaSDL, document: document)
    subject = ir.schema.referencedTypes.inputObjects[1]
  }

  // MARK: - Tests

  func test__compileInputObject__givenNestedInputObjectParameterWithDefaultValue_compilesInputTypeWithDefaultValue() async throws {
    // given
    schemaSDL = """
    type Query {
      exampleQuery(input: Input!): String!
    }

    input ChildInput {
        a: String
        b: String
        c: String
      }

    input Input {
      child: ChildInput = { a: "a", b: "b", c: "c" }
    }
    """

    document = """
    query TestOperation($input: Input!) {
      exampleQuery(input: $input)
    }
    """

    // when
    try await buildSubject()
    let childField = subject.fields["child"]

    let expectedDefaultValue = GraphQLValue.object([
      "a": .string("a"),
      "b": .string("b"),
      "c": .string("c")
    ])

    // then
    expect(childField?.defaultValue).to(equal(expectedDefaultValue))
  }

}
