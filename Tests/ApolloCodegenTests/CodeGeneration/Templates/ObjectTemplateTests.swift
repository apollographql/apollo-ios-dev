import XCTest
import Nimble
import GraphQLCompiler
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class ObjectTemplateTests: XCTestCase {

  var subject: ObjectTemplate!

  override func tearDown() {
    subject = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubject(
    name: String = "Dog",
    customName: String? = nil,
    interfaces: [GraphQLInterfaceType] = [],
    documentation: String? = nil,
    config: ApolloCodegenConfiguration = .mock()
  ) {
    let objectType = GraphQLObjectType.mock(
      name,
      interfaces: interfaces,
      documentation: documentation
    )
    objectType.name.customName = customName
    subject = ObjectTemplate(
      graphqlObject: objectType,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: Boilerplate tests

  func test_render_generatesClosingBrace() {
    // given
    buildSubject()

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(endWith("\n)"))
  }

  // MARK: Class Definition Tests

  func test_render_givenSchemaType_generatesSwiftClassDefinitionCorrectlyCased() {
    // given
    buildSubject(name: "dog")

    let expected = """
    static let Dog = ApolloAPI.Object(
      typename: "dog",
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenSchemaTypeImplementsInterfaces_schemaEmbeddedInTarget_generatesImplementedInterfacesWithSchemaNamespace() {
    // given
    buildSubject(interfaces: [
        GraphQLInterfaceType.mock("Animal", fields: ["species": GraphQLField.mock("species", type: .scalar(.string()))]),
        GraphQLInterfaceType.mock("Pet", fields: ["name": GraphQLField.mock("name", type: .scalar(.string()))])
      ]
    )

    let expected = """
      implementedInterfaces: [
        TestSchema.Interfaces.Animal.self,
        TestSchema.Interfaces.Pet.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  func test_render_givenSchemaTypeImplementsInterfaces_schemaNotEmbeddedInTarget_generatesImplementedInterfacesNotInSchemaNameSpace() {
    // given
    buildSubject(
      interfaces: [
        GraphQLInterfaceType.mock("Animal", fields: ["species": GraphQLField.mock("species", type: .scalar(.string()))]),
        GraphQLInterfaceType.mock("Pet", fields: ["name": GraphQLField.mock("name", type: .scalar(.string()))])
      ],
      config: .mock(.swiftPackageManager)
    )

    let expected = """
      implementedInterfaces: [
        Interfaces.Animal.self,
        Interfaces.Pet.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  func test_render_givenNoImplemented_generatesEmpytArray() {
    // given
    buildSubject()

    let expected = """
      implementedInterfaces: []
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
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
    static let Dog = ApolloAPI.Object(
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
    static let Dog = ApolloAPI.Object(
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Reserved Keyword Tests
  
  func test_render_usingReservedKeyword_shouldHaveSuffixedType() {
    let keywords = ["Type", "type"]
    
    keywords.forEach { keyword in
      // given
      buildSubject(name: keyword)

      let expected = """
      static let \(keyword.firstUppercased)_Object = ApolloAPI.Object(
        typename: "\(keyword)",
      """

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
  // MARK: - Schema Customization
  
  func test__render__giveObjectTypeAndInterface_withCustomNames_shouldRenderWithCustomNames() throws {
    // given
    let implementedInterface = GraphQLInterfaceType.mock("MyInterface", fields: ["myField": GraphQLField.mock("myField", type: .scalar(.string()))])
    implementedInterface.name.customName = "MyCustomInterface"
    buildSubject(
      name: "MyObject",
      customName: "MyCustomObject",
      interfaces: [
        implementedInterface
      ]
    )

    let expected = """
    // Renamed from GraphQL schema value: 'MyObject'
    static let MyCustomObject = ApolloAPI.Object(
      typename: "MyObject",
      implementedInterfaces: [TestSchema.Interfaces.MyCustomInterface.self]
    )
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
}
