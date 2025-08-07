import XCTest
import Nimble
import GraphQLCompiler
@testable import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class SchemaMetadataTemplateTests: XCTestCase {
  var subject: SchemaMetadataTemplate!

  override func tearDown() {
    subject = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubject(
    referencedTypes: IR.Schema.ReferencedTypes = .init([], schemaRootTypes: .mock()),
    documentation: String? = nil,
    config: ApolloCodegenConfiguration = ApolloCodegenConfiguration.mock()
  ) {
    subject = SchemaMetadataTemplate(
      schema: IR.Schema(referencedTypes: referencedTypes, documentation: documentation),
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderTemplate() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  private func renderDetachedTemplate() -> String? {
    subject.renderDetachedTemplate(nonFatalErrorRecorder: .init())?.description
  }

  // MARK: Typealias & Protocol Tests

  func test__render__givenModuleEmbeddedInTarget_withInternalAccessModifier_shouldGenerateDetachedProtocols_withTypealias_withCorrectCasing_withInternalAccess() {
    // given
    buildSubject(
      config: .mock(
        .embeddedInTarget(name: "CustomTarget", accessModifier: .internal),
        schemaNamespace: "aName"
      )
    )

    let expectedTemplate = """
    typealias SelectionSet = AName_SelectionSet

    typealias InlineFragment = AName_InlineFragment

    typealias MutableSelectionSet = AName_MutableSelectionSet

    typealias MutableInlineFragment = AName_MutableInlineFragment

    """

    let expectedDetached = """
    protocol AName_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
    where Schema == AName.SchemaMetadata {}

    protocol AName_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}

    protocol AName_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
    where Schema == AName.SchemaMetadata {}

    protocol AName_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}
    """

    // when
    let actualTemplate = renderTemplate()
    let actualDetached = renderDetachedTemplate()

    // then
    expect(actualTemplate)
      .to(equalLineByLine(expectedTemplate, ignoringExtraLines: true))
    expect(actualDetached)
      .to(equalLineByLine(expectedDetached))
  }

  func test__render__givenModuleEmbeddedInTarget_withPublicAccessModifier_shouldGenerateDetachedProtocols_withTypealias_withCorrectCasing_withPublicAccess() {
    // given
    buildSubject(
      config: .mock(
        .embeddedInTarget(name: "CustomTarget", accessModifier: .public),
        schemaNamespace: "aName"
      )
    )

    let expectedTemplate = """
    typealias SelectionSet = AName_SelectionSet

    typealias InlineFragment = AName_InlineFragment

    typealias MutableSelectionSet = AName_MutableSelectionSet

    typealias MutableInlineFragment = AName_MutableInlineFragment

    """

    let expectedDetached = """
    public protocol AName_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol AName_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}

    public protocol AName_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol AName_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}
    """

    // when
    let actualTemplate = renderTemplate()
    let actualDetached = renderDetachedTemplate()

    // then
    expect(actualTemplate)
      .to(equalLineByLine(expectedTemplate, ignoringExtraLines: true))
    expect(actualDetached)
      .to(equalLineByLine(expectedDetached))
  }

  func test__render__givenModuleSwiftPackageManager_shouldGenerateEmbeddedProtocols_noTypealias_withCorrectCasing_withPublicModifier() {
    // given
    buildSubject(
      config: .mock(
        .swiftPackage(),
        schemaNamespace: "aName"
      )
    )

    let expectedTemplate = """
    public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}

    public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}
    """

    // when
    let actualTemplate = renderTemplate()
    let actualDetached = renderDetachedTemplate()

    // then
    expect(actualTemplate)
      .to(equalLineByLine(expectedTemplate, ignoringExtraLines: true))
    expect(actualDetached)
      .to(beNil())
  }

  func test__render__givenModuleOther_shouldGenerateEmbeddedProtocols_noTypealias_withCorrectCasing_withPublicModifier() {
    // given
    buildSubject(
      config: .mock(
        .other,
        schemaNamespace: "aName"
      )
    )

    let expectedTemplate = """
    public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}

    public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
    where Schema == AName.SchemaMetadata {}

    public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
    where Schema == AName.SchemaMetadata {}
    """

    // when
    let actualTemplate = renderTemplate()
    let actualDetached = renderDetachedTemplate()

    // then
    expect(actualTemplate)
      .to(equalLineByLine(expectedTemplate, ignoringExtraLines: true))
    expect(actualDetached)
      .to(beNil())
  }

  // MARK: Schema Tests

  func test__render__givenModuleEmbeddedInTarget_withInternalAccessModifier_shouldGenerateEnumDefinition_withInternalAccess() {
    // given
    buildSubject(config: .mock(.embeddedInTarget(name: "MockTarget", accessModifier: .internal)))

    let expected = """
    enum SchemaMetadata: ApolloAPI.SchemaMetadata {
      static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render__givenModuleEmbeddedInTarget_withPublicAccessModifier_shouldGenerateEnumDefinition_withPublicAccess() {
    // given
    buildSubject(config: .mock(.embeddedInTarget(name: "MockTarget", accessModifier: .public)))

    let expected = """
    enum SchemaMetadata: ApolloAPI.SchemaMetadata {
      public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render__givenModuleSwiftPackageManager_shouldGenerateEnumDefinition_withPublicModifier() {
    // given
    buildSubject(config: .mock(.swiftPackage()))

    let expected = """
    public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
      public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render__givenModuleOther_shouldGenerateEnumDefinition_withPublicModifier() {
    // given
    buildSubject(config: .mock(.other))

    let expected = """
    public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
      public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render__givenWithReferencedObjects_generatesObjectTypeFunctionCorrectlyCased() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("objA"),
        GraphQLObjectType.mock("objB"),
        GraphQLObjectType.mock("objC"),
      ], schemaRootTypes: .mock()),
      config: .mock(schemaNamespace: "objectSchema")
    )

    let expected = """
      static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
        switch typename {
        case "objA": return ObjectSchema.Objects.ObjA
        case "objB": return ObjectSchema.Objects.ObjB
        case "objC": return ObjectSchema.Objects.ObjC
        default: return nil
        }
      }
    }
    
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render__givenWithReferencedOtherTypes_generatesObjectTypeNotIncludingNonObjectTypesFunction() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("ObjectA"),
        GraphQLInterfaceType.mock("InterfaceB"),
        GraphQLUnionType.mock("UnionC"),
        GraphQLScalarType.mock(name: "ScalarD"),
        GraphQLEnumType.mock(name: "EnumE"),
        GraphQLInputObjectType.mock("InputObjectC"),
      ], schemaRootTypes: .mock()),
      config: .mock(schemaNamespace: "ObjectSchema")
    )

    let expected = """
      static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
        switch typename {
        case "ObjectA": return ObjectSchema.Objects.ObjectA
        default: return nil
        }
      }
    }
    
    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render__givenModuleEmbeddedInTarget_withInternalAccessModifier_rendersTypeNamespaceEnums_withInternalAccess() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("ObjectA"),
        GraphQLInterfaceType.mock("InterfaceB"),
        GraphQLUnionType.mock("UnionC"),
        GraphQLScalarType.mock(name: "ScalarD"),
        GraphQLEnumType.mock(name: "EnumE"),
        GraphQLInputObjectType.mock("InputObjectC"),
      ], schemaRootTypes: .mock()),
      config: .mock(
        .embeddedInTarget(name: "TestTarget", accessModifier: .internal),
        schemaNamespace: "ObjectSchema"
      )
    )

    let expected = """
    enum Objects {}
    enum Interfaces {}
    enum Unions {}

    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 20))
  }

  func test__render__givenModuleEmbeddedInTarget_withPublicAccessModifier_rendersTypeNamespaceEnums_withPublicAccess() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("ObjectA"),
        GraphQLInterfaceType.mock("InterfaceB"),
        GraphQLUnionType.mock("UnionC"),
        GraphQLScalarType.mock(name: "ScalarD"),
        GraphQLEnumType.mock(name: "EnumE"),
        GraphQLInputObjectType.mock("InputObjectC"),
      ], schemaRootTypes: .mock()),
      config: .mock(
        .embeddedInTarget(name: "TestTarget", accessModifier: .public),
        schemaNamespace: "ObjectSchema"
      )
    )

    let expected = """
    enum Objects {}
    enum Interfaces {}
    enum Unions {}

    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 20))
  }

  func test__render__givenModuleSwiftPackageManager_rendersTypeNamespaceEnums_withPublicAccess() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("ObjectA"),
        GraphQLInterfaceType.mock("InterfaceB"),
        GraphQLUnionType.mock("UnionC"),
        GraphQLScalarType.mock(name: "ScalarD"),
        GraphQLEnumType.mock(name: "EnumE"),
        GraphQLInputObjectType.mock("InputObjectC"),
      ], schemaRootTypes: .mock()),
      config: .mock(
        .swiftPackage(),
        schemaNamespace: "ObjectSchema"
      )
    )

    let expected = """
    public enum Objects {}
    public enum Interfaces {}
    public enum Unions {}

    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 24))
  }

  func test__render__givenModuleOther_rendersTypeNamespaceEnums_withPublicAccess() {
    // given
    buildSubject(
      referencedTypes: .init([
        GraphQLObjectType.mock("ObjectA"),
        GraphQLInterfaceType.mock("InterfaceB"),
        GraphQLUnionType.mock("UnionC"),
        GraphQLScalarType.mock(name: "ScalarD"),
        GraphQLEnumType.mock(name: "EnumE"),
        GraphQLInputObjectType.mock("InputObjectC"),
      ], schemaRootTypes: .mock()),
      config: .mock(
        .other,
        schemaNamespace: "ObjectSchema"
      )
    )

    let expected = """
    public enum Objects {}
    public enum Interfaces {}
    public enum Unions {}

    """

    // when
    let actual = renderTemplate()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 24))
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
    enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    """

    // when
    let rendered = renderTemplate()

    // then
    expect(rendered).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
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
    enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    """

    // when
    let rendered = renderTemplate()

    // then
    expect(rendered).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

}
