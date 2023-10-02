import XCTest
import Nimble
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import GraphQLCompiler
@testable import ApolloCodegenLib

class DocumentParsingAndValidationTests: XCTestCase {
  
  var codegenFrontend: GraphQLJSFrontend!
  var schema: GraphQLSchema!
  
  override func setUp() async throws {
    try await super.setUp()

    codegenFrontend = try await GraphQLJSFrontend()

    let introspectionResult = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )

    schema = try await codegenFrontend.loadSchema(
      from: [try codegenFrontend.makeSource(introspectionResult, filePath: "schema.json")]
    )
  }

  override func tearDown() {
    codegenFrontend = nil
    schema = nil

    super.tearDown()
  }
  
  func testParseDocument() async throws {
    let source = try await codegenFrontend.makeSource("""
      query HeroAndFriendsNames($episode: Episode) {
        hero(episode: $episode) {
          name
          friends {
            name
          }
        }
      }
      """, filePath: "HeroAndFriendsNames.graphql")
    
    let document = try await codegenFrontend.parseDocument(source)
    
    XCTAssertEqual(document.filePath, "HeroAndFriendsNames.graphql")
  }
  
  func testParseDocumentWithSyntaxError() async throws {
    let source = try await codegenFrontend.makeSource("""
      query HeroAndFriendsNames($episode: Episode) {
        hero[episode: foo]
      }
      """, filePath: "HeroAndFriendsNames.graphql")
    
    await expect { try await self.codegenFrontend.parseDocument(source) }
      .to(throwError { error in
        self.whileRecordingErrors {
          let error = try XCTDowncast(error as AnyObject, to: GraphQLError.self)
          XCTAssert(try XCTUnwrap(error.message).starts(with: "Syntax Error"))
          
          let sourceLocations = try XCTUnwrap(error.sourceLocations)
          XCTAssertEqual(sourceLocations.count, 1)
          
          XCTAssertEqual(sourceLocations[0].filePath, "HeroAndFriendsNames.graphql")
          XCTAssertEqual(sourceLocations[0].lineNumber, 2)
        }
    })
  }
  
  func testValidateDocument() async throws {
    let source = try await codegenFrontend.makeSource("""
      query HeroAndFriendsNames($episode: Episode) {
        hero(episode: $episode) {
          name
          email
          ...FriendsNames
        }
      }
      """, filePath: "HeroAndFriendsNames.graphql")
    
    let document = try await codegenFrontend.parseDocument(source)
    
    let validationErrors = try await codegenFrontend.validateDocument(
      schema: schema,
      document: document,
      validationOptions: .mock()
    )
    
    XCTAssertEqual(validationErrors.map(\.message), [
      """
      Cannot query field "email" on type "Character".
      """,
      """
      Unknown fragment "FriendsNames".
      """
    ])
        
    XCTAssertEqual(document.filePath, "HeroAndFriendsNames.graphql")
  }
  
  func testParseAndValidateMultipleDocuments() async throws {
    let source1 = try await codegenFrontend.makeSource("""
      query HeroAndFriendsNames($episode: Episode) {
        hero(episode: $episode) {
          name
          ...FriendsNames
        }
      }
      """, filePath: "HeroAndFriendsNames.graphql")
    
    let source2 = try await codegenFrontend.makeSource("""
      query HeroName($episode: Episode) {
        hero(episode: $episode) {
          name
        }
      }
      """, filePath: "HeroName.graphql")
    
    let source3 = try await codegenFrontend.makeSource("""
      fragment FriendsNames on Character {
        friends {
          name
        }
      }
      """, filePath: "FriendsNames.graphql")
    
    let document1 = try await codegenFrontend.parseDocument(source1)
    let document2 = try await codegenFrontend.parseDocument(source2)
    let document3 = try await codegenFrontend.parseDocument(source3)
    
    let document = try await codegenFrontend.mergeDocuments([document1, document2, document3])
    XCTAssertEqual(document.definitions.count, 3)
    
    let validationErrors = try await codegenFrontend.validateDocument(
      schema: schema,
      document: document,
      validationOptions: .mock()
    )

    XCTAssertEqual(validationErrors.count, 0)
  }
  
  // Errors during validation may contain multiple source locations. In the case of a field conflict
  // for example, both fields would be associated with the same error. These locations
  // may even come from different source files, so we need to test for that explicitly because
  // handling that situation required a workaround (see `GraphQLError.sourceLocations`).
  func testValidationErrorThatSpansMultipleDocuments() async throws {
    let source1 = try await codegenFrontend.makeSource("""
      query HeroName($episode: Episode) {
        hero(episode: $episode) {
          foo: appearsIn
          ...HeroName
        }
      }
      """, filePath: "HeroName.graphql")
    
    let source2 = try await codegenFrontend.makeSource("""
      fragment HeroName on Character {
        foo: name
      }
      """, filePath: "HeroNameFragment.graphql")
    
    let document1 = try await codegenFrontend.parseDocument(source1)
    let document2 = try await codegenFrontend.parseDocument(source2)
    
    let document = try await codegenFrontend.mergeDocuments([document1, document2])
    XCTAssertEqual(document.definitions.count, 2)
    
    let validationErrors = try await codegenFrontend.validateDocument(
      schema: schema,
      document: document,
      validationOptions: .mock()
    )
    
    XCTAssertEqual(validationErrors.count, 1)
    let validationError = validationErrors[0]
    
    XCTAssertEqual(validationError.message, """
      Fields "foo" conflict because "appearsIn" and "name" are different fields. \
      Use different aliases on the fields to fetch both if this was intentional.
      """)
    
    let sourceLocations = try XCTUnwrap(validationError.sourceLocations)
    XCTAssertEqual(sourceLocations.count, 2)
        
    XCTAssertEqual(sourceLocations[0].filePath, "HeroName.graphql")
    XCTAssertEqual(sourceLocations[0].lineNumber, 3)
    
    XCTAssertEqual(sourceLocations[1].filePath, "HeroNameFragment.graphql")
    XCTAssertEqual(sourceLocations[1].lineNumber, 2)
  }

  func test__validateDocument__givenFieldNameDisallowed_throwsError() async throws {
    let disallowedFields = ["__data", "fragments", "Fragments"]

    for field in disallowedFields {
      let schema = try await codegenFrontend.loadSchema(
        from: [try codegenFrontend.makeSource(
      """
      type Query {
        \(field): String!
      }
      """
      , filePath: "schema.graphqls")])

      let source = try await codegenFrontend.makeSource("""
      query TestQuery {
        \(field)
      }
      """, filePath: "TestQuery.graphql")

      let document = try await codegenFrontend.parseDocument(source)

      let validationErrors = try await codegenFrontend.validateDocument(
        schema: schema,
        document: document,
        validationOptions: .mock()
      )

      XCTAssertEqual(validationErrors.map(\.message), [
      """
      Field name "\(field)" is not allowed because it conflicts with generated \
      object APIs. Please use an alias to change the field name.
      """,
      ])

      XCTAssertEqual(document.filePath, "TestQuery.graphql")
    }
  }

  func test__validateDocument__givenInputParameterNameDisallowed_throwsError() async throws {
    let disallowedName = ["self", "Self", "_"]

    for name in disallowedName {
      let schema = try await codegenFrontend.loadSchema(
        from: [try codegenFrontend.makeSource(
      """
      type Query {
        test(param: String!): String!
      }
      """
      , filePath: "schema.graphqls")])

      let source = try await codegenFrontend.makeSource("""
      query TestQuery($\(name): String!) {
        test(param: $\(name))
      }
      """, filePath: "TestQuery.graphql")

      let document = try await codegenFrontend.parseDocument(source)

      let validationErrors = try await codegenFrontend.validateDocument(
        schema: schema,
        document: document,
        validationOptions: .mock()
      )

      XCTAssertEqual(validationErrors.map(\.message), [
      """
      Input Parameter name "\(name)" is not allowed because it conflicts with generated \
      object APIs.
      """,
      ])

      XCTAssertEqual(document.filePath, "TestQuery.graphql")
    }
  }

  func test__validateDocument__givenInputParameterNameIsSchemaName_throwsError() async throws {
    let disallowedName = ["AnimalKingdomAPI", "animalKingdomAPI"]

    for name in disallowedName {
      let schema = try await codegenFrontend.loadSchema(
        from: [try codegenFrontend.makeSource(
      """
      type Query {
        test(param: String!): String!
      }
      """
      , filePath: "schema.graphqls")])

      let source = try await codegenFrontend.makeSource("""
      query TestQuery($\(name): String!) {
        test(param: $\(name))
      }
      """, filePath: "TestQuery.graphql")

      let document = try await codegenFrontend.parseDocument(source)

      let validationErrors = try await codegenFrontend.validateDocument(
        schema: schema,
        document: document,
        validationOptions: .mock(schemaNamespace: "AnimalKingdomAPI")
      )

      XCTAssertEqual(validationErrors.map(\.message), [
      """
      Input Parameter name "\(name)" is not allowed because it conflicts with generated \
      object APIs.
      """,
      ])

      XCTAssertEqual(document.filePath, "TestQuery.graphql")
    }
  }
}
