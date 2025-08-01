import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers
import GraphQLCompiler

class InterfaceTemplateTests: XCTestCase {
  var subject: InterfaceTemplate!

  override func tearDown() {
    subject = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubject(
    name: String = "Dog",
    customName: String? = nil,
    documentation: String? = nil,
    keyFields: [String] = [],
    implementingObjects: [GraphQLObjectType] = [],
    config: ApolloCodegenConfiguration = .mock()
  ) {
    let interfaceType = GraphQLInterfaceType.mock(
      name,
      fields: [:],
      keyFields: keyFields,
      interfaces: [],
      implementingObjects: implementingObjects,
      documentation: documentation
    )
    interfaceType.name.customName = customName
    
    subject = InterfaceTemplate(
      graphqlInterface: interfaceType,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: Casing Tests

  func test_render_givenSchemaInterface_generatesSwiftClassDefinitionCorrectlyCased() throws {
    // given
    buildSubject(name: "aDog")

    let expected = """
    static let ADog = ApolloAPI.Interface(
      name: "aDog",
      keyFields: nil,
      implementingObjects: []
    )
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Documentation Tests

  func test__render__givenSchemaDocumentation_include_hasDocumentation_shouldGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      documentation: documentation,
      config: .mock(options: .init(schemaDocumentation: .include))
    )

    let expected = """
    /// \(documentation)
    static let Dog = ApolloAPI.Interface(
      name: "Dog",
      keyFields: nil,
      implementingObjects: []
    )
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenSchemaDocumentation_exclude_hasDocumentation_shouldNotGenerateDocumentationComment() throws {
    // given
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      documentation: documentation,
      config: .mock(options: .init(schemaDocumentation: .exclude))
    )

    let expected = """
    static let Dog = ApolloAPI.Interface(
      name: "Dog",
      keyFields: nil,
      implementingObjects: []
    )
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Reserved Keyword Tests
  
  func test_render_givenSchemaInterfaceUsingReservedKeyword_generatesWithEscapedType() throws {
    let keywords = ["Type", "type"]
    
    keywords.forEach { keyword in
      // given
      buildSubject(name: keyword)

      let expected = """
      static let \(keyword.firstUppercased)_Interface = ApolloAPI.Interface(
        name: "\(keyword)",
        keyFields: nil,
        implementingObjects: []
      )
      """

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected))
    }
  }
  
  // MARK: Schema Customization Tests
  
  func test__render__givenInterface_withCustomName_shouldRenderWithCustomName() throws {
    // given
    buildSubject(
      name: "MyInterface",
      customName: "MyCustomInterface"
    )
    
    let expected = """
    // Renamed from GraphQL schema value: 'MyInterface'
    static let MyCustomInterface = ApolloAPI.Interface(
      name: "MyInterface",
      keyFields: nil,
      implementingObjects: []
    )
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__render__givenInterface_withKeyFields_shouldRenderKeyFields() throws {
    // given
    buildSubject(
      name: "IndexedNode",
      keyFields: ["parentID", "index"]
    )
    
    let expected = """
    static let IndexedNode = ApolloAPI.Interface(
      name: "IndexedNode",
      keyFields: [
        "parentID",
        "index"
      ],
      implementingObjects: []
    )
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
  // MARK: - Implementing Objects Tests
  
  func test__render__givenInterface_withOneImplementingObject_shouldRenderSingleLineArray() throws {
    // given
    let obj = GraphQLObjectType.mock("MyObject")
    buildSubject(
      name: "MyInterface",
      implementingObjects: [obj]
    )
    
    let expected = """
    static let MyInterface = ApolloAPI.Interface(
      name: "MyInterface",
      keyFields: nil,
      implementingObjects: ["MyObject"]
    )
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__render__givenInterface_withMultipleImplementingObjects_shouldRenderMultiLineArray() throws {
    // given
    let obj = GraphQLObjectType.mock("MyObject")
    let secondObj = GraphQLObjectType.mock("SecondObject")
    buildSubject(
      name: "MyInterface",
      implementingObjects: [obj, secondObj]
    )
    
    let expected = """
    static let MyInterface = ApolloAPI.Interface(
      name: "MyInterface",
      keyFields: nil,
      implementingObjects: [
        "MyObject",
        "SecondObject"
      ]
    )
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
}
