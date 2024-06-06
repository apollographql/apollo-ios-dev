import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloAPI
import GraphQLCompiler

class UnionTemplateTests: XCTestCase {
  var subject: UnionTemplate!

  override func tearDown() {
    subject = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubject(
    name: String = "ClassroomPet",
    customName: String? = nil,
    types: [GraphQLObjectType] = [
      GraphQLObjectType.mock("cat"),
      GraphQLObjectType.mock("bird"),
      GraphQLObjectType.mock("rat"),
      GraphQLObjectType.mock("petRock")
    ],
    documentation: String? = nil,
    config: ApolloCodegenConfiguration = .mock()
  ) {
    let unionType = GraphQLUnionType.mock(
      name,
      types: types,
      documentation: documentation
    )
    unionType.name.customName = customName
    subject = UnionTemplate(
      graphqlUnion: unionType,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: Boilerplate tests

  func test_render_generatesClosingParen() throws {
    // given
    buildSubject()

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(endWith("\n)"))
  }

  // MARK: CasingTests

  func test_render_givenLowercaseSchemaName_generatesUsingCapitalizedSchemaName() throws {
    // given
    buildSubject(config: .mock(schemaNamespace: "lowercased"))

    let expected = """
      possibleTypes: [
        Lowercased.Objects.Cat.self,
        Lowercased.Objects.Bird.self,
        Lowercased.Objects.Rat.self,
        Lowercased.Objects.PetRock.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  func test_render_givenUppercaseSchemaName_generatesUsingUppercaseSchemaName() throws {
    // given
    buildSubject(config: .mock(schemaNamespace: "UPPER"))

    let expected = """
      possibleTypes: [
        UPPER.Objects.Cat.self,
        UPPER.Objects.Bird.self,
        UPPER.Objects.Rat.self,
        UPPER.Objects.PetRock.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  func test_render_givenCapitalizedSchemaName_generatesUsingCapitalizedSchemaName() throws {
    // given
    buildSubject(config: .mock(schemaNamespace: "MySchema"))

    let expected = """
      possibleTypes: [
        MySchema.Objects.Cat.self,
        MySchema.Objects.Bird.self,
        MySchema.Objects.Rat.self,
        MySchema.Objects.PetRock.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  // MARK: Class Generation Tests

  func test_render_generatesSwiftEnumDefinition() throws {
    // given
    buildSubject()

    let expected = """
    static let ClassroomPet = Union(
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }


  func test_render_givenSchemaUnionWithLowercaseName_generatesSwiftEnumDefinitionAsUppercase() throws {
    // given
    buildSubject(name: "classroomPet")

    let expected = """
    static let ClassroomPet = Union(
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenSchemaUnion_generatesNameProperty() throws {
    // given
    buildSubject()

    let expected = """
      name: "ClassroomPet",
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  func test_render_givenSchemaUnionWithLowercaseName_generatesNamePropertyAsLowercase() throws {
    // given
    buildSubject(name: "classroomPet")

    let expected = """
      name: "classroomPet",
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  func test_render_givenSchemaUnion_schemaTypesEmbeddedInTarget_generatesPossibleTypesPropertyWithSchameNamespace() throws {
    // given
    buildSubject()

    let expected = """
      possibleTypes: [
        TestSchema.Objects.Cat.self,
        TestSchema.Objects.Bird.self,
        TestSchema.Objects.Rat.self,
        TestSchema.Objects.PetRock.self
      ]
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 3, ignoringExtraLines: true))
  }

  func test_render_givenSchemaUnion_schemaTypesNotEmbeddedInTarget_generatesPossibleTypesPropertyWithoutSchemaNamespace() throws {
    // given
    buildSubject(config: .mock(.swiftPackageManager))

    let expected = """
      possibleTypes: [
        Objects.Cat.self,
        Objects.Bird.self,
        Objects.Rat.self,
        Objects.PetRock.self
      ]
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
    static let ClassroomPet = Union(
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
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
    static let ClassroomPet = Union(
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: - Reserved Keyword Tests
  
  func test_render_usingReservedKeyword_shouldHaveSuffixedType() throws {
    let keywords = ["Type", "type"]

    keywords.forEach { keyword in
      // given
      buildSubject(name: keyword)

      let expected = """
      static let \(keyword.firstUppercased)_Union = Union(
        name: "\(keyword)",
      """

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
  // MARK: - Schema Customization Tests
  
  func test__render__givenUnion_withCustomName_shouldRenderWithCustomName() throws {
    // given
    let customObjectType = GraphQLObjectType.mock("MyObject")
    customObjectType.name.customName = "MyCustomObject"
    
    buildSubject(
      name: "MyUnion",
      customName: "MyCustomUnion",
      types: [
        GraphQLObjectType.mock("cat"),
        customObjectType
      ]
    )
    
    
    let expected = """
    // Renamed from GraphQL schema value: 'MyUnion'
    static let MyCustomUnion = Union(
      name: "MyUnion",
      possibleTypes: [
        TestSchema.Objects.Cat.self,
        TestSchema.Objects.MyCustomObject.self
      ]
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
}
