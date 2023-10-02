import XCTest
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
@testable import ApolloCodegenLib
@testable import GraphQLCompiler

class SchemaIntrospectionTests: XCTestCase {

  var codegenFrontend: GraphQLJSFrontend!
  var schema: GraphQLSchema!
  
  override func setUp() async throws {
    try await super.setUp()

    codegenFrontend = try await GraphQLJSFrontend()

    let introspectionResult = try String(
      contentsOf: ApolloCodegenInternalTestHelpers.Resources.StarWars.JSONSchema
    )

    schema = try await codegenFrontend.loadSchema(
      from: [try await codegenFrontend.makeSource(introspectionResult, filePath: "schema.json")]
    )
  }

  override func tearDown() {
    codegenFrontend = nil
    schema = nil

    super.tearDown()
  }
  
  func testGetFieldsForObjectType() async throws {
    let type = try await schema.getType(named: "Droid")
    let droidType = try XCTDowncast(XCTUnwrap(type), to: GraphQLObjectType.self)
    XCTAssertEqual(droidType.name, "Droid")
    
    let fields = droidType.fields
        
    XCTAssertEqual(fields["name"]?.name, "name")
    XCTAssertEqual(fields["name"]?.type.typeReference, "String!")
    
    XCTAssertEqual(fields["friends"]?.name, "friends")
    XCTAssertEqual(fields["friends"]?.type.typeReference, "[Character]")
  }
  
  func testGetPossibleTypesForInterface() async throws {
    let type = try await schema.getType(named: "Character")
    let characterType = try XCTDowncast(XCTUnwrap(type), to: GraphQLAbstractType.self)
    XCTAssertEqual(characterType.name, "Character")
    
    let actual = try await schema.getPossibleTypes(characterType).map(\.name)
    XCTAssertEqualUnordered(actual, ["Human", "Droid"])
  }
  
  func testGetPossibleTypesForUnion() async throws {
    let type = try await schema.getType(named: "SearchResult")
    let searchResultType = try XCTDowncast(XCTUnwrap(type), to: GraphQLAbstractType.self)
    XCTAssertEqual(searchResultType.name, "SearchResult")

    let actual = try await schema.getPossibleTypes(searchResultType).map(\.name)
    XCTAssertEqualUnordered(actual, ["Human", "Droid", "Starship"])
  }
  
  func testGetTypesForUnion() async throws {
    let type = try await schema.getType(named: "SearchResult")
    let searchResultType = try XCTDowncast(XCTUnwrap(type), to: GraphQLUnionType.self)
    XCTAssertEqual(searchResultType.name, "SearchResult")
    
    XCTAssertEqualUnordered(searchResultType.types.map(\.name), ["Human", "Droid", "Starship"])
  }
  
  func testEnumType() async throws {
    let type = try await schema.getType(named: "Episode")
    let episodeType = try XCTDowncast(XCTUnwrap(type), to: GraphQLEnumType.self)
    XCTAssertEqual(episodeType.name, "Episode")
    
    XCTAssertEqual(episodeType.documentation, "The episodes in the Star Wars trilogy")
    
    XCTAssertEqual(episodeType.values.map(\.name.value), ["NEWHOPE", "EMPIRE", "JEDI"])
    XCTAssertEqual(episodeType.values.map(\.documentation), [
      "Star Wars Episode IV: A New Hope, released in 1977.",
      "Star Wars Episode V: The Empire Strikes Back, released in 1980.",
      "Star Wars Episode VI: Return of the Jedi, released in 1983."
    ])
  }
  
  func testInputObjectType() async throws {
    let type = try await schema.getType(named: "ReviewInput")
    let episodeType = try XCTDowncast(XCTUnwrap(type), to: GraphQLInputObjectType.self)
    XCTAssertEqual(episodeType.name, "ReviewInput")
    
    XCTAssertEqual(episodeType.documentation, "The input object sent when someone is creating a new review")
    
    XCTAssertEqual(episodeType.fields["stars"]?.type.typeReference, "Int!")
    XCTAssertEqual(episodeType.fields["stars"]?.documentation, "0-5 stars")
    
    XCTAssertEqual(episodeType.fields["commentary"]?.type.typeReference, "String")
    XCTAssertEqual(episodeType.fields["commentary"]?.documentation, "Comment about the movie, optional")
    
    XCTAssertEqual(episodeType.fields["favorite_color"]?.type.typeReference, "ColorInput")
    XCTAssertEqual(episodeType.fields["favorite_color"]?.documentation, "Favorite color, optional")
  }
}
