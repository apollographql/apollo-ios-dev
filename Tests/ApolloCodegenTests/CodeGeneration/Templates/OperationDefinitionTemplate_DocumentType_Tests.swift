import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class OperationDefinitionTemplate_DocumentType_Tests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var operation: IR.Operation!
  var config: ApolloCodegenConfiguration!
  var subject: OperationDefinitionTemplate!

  override func setUp() {
    super.setUp()
    schemaSDL = """
    type Query {
      name: String!
    }
    """

    config = .mock()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    operation = nil
    config = nil
    subject = nil
    super.tearDown()
  }

  private func buildSubjectAndOperation(
    named operationName: String = "NameQuery",
    operationIdentifier: String? = nil,
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType = .swiftPackage(),
    operations: ApolloCodegenConfiguration.OperationsFileOutput = .inSchemaModule,
    operationDocumentFormat: ApolloCodegenConfiguration.OperationDocumentFormat = .definition,
    cocoapodsCompatibleImportStatements: Bool = false
  ) async throws {
    ir = try await .mock(schema: schemaSDL, document: document)
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)

    config = .mock(
      output: .mock(moduleType: moduleType, operations: operations),
      options: .init(
        operationDocumentFormat: operationDocumentFormat,
        cocoapodsCompatibleImportStatements: cocoapodsCompatibleImportStatements
      )
    )

    subject = OperationDefinitionTemplate(
      operation: operation,
      operationIdentifier: operationIdentifier,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  func renderDocumentType() throws -> String {
    return subject.DocumentType().description
  }

  // MARK: Query string formatting tests

  func test__generate__givenSingleLineFormat_generatesWithOperationDefinition() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationDocumentFormat: .definition
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query NameQuery { name }"#
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenSingleLineFormat_withInLineQuotes_generatesWithOperationDefinition_withInLineQuotes() async throws {
    // given
    document =
    """
    query NameQuery($filter: String = "MyName") {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationDocumentFormat: .definition
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query NameQuery($filter: String = "MyName") { name }"#
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenIncludesFragment_formatSingleLine_generatesWithOperationDefinitionAndFragment() async throws {
    // given
    document =
    """
    query NameQuery {
      ...NameFragment
    }

    fragment NameFragment on Query {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationDocumentFormat: .definition
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query NameQuery { ...NameFragment }"#,
        fragments: [NameFragment.self]
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenIncludesFragment_fragmentNameStartsWithLowercase_generatesWithOperationDefinitionAndFragment_withFirstUppercased() async throws {
    // given
    document =
    """
    query NameQuery {
      ...nameFragment
    }

    fragment nameFragment on Query {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationDocumentFormat: .definition
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query NameQuery { ...nameFragment }"#,
        fragments: [NameFragment.self]
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenIncludesManyFragments_formatSingleLine_generatesWithOperationDefinitionAndFragment() async throws {
    // given
    document =
    """
    query NameQuery {
      ...Fragment1
      ...Fragment2
      ...Fragment3
      ...Fragment4
      ...FragmentWithLongName1234123412341234123412341234
    }

    fragment Fragment1 on Query {
      name
    }

    fragment Fragment2 on Query {
      name
    }

    fragment Fragment3 on Query {
      name
    }

    fragment Fragment4 on Query {
      name
    }

    fragment FragmentWithLongName1234123412341234123412341234 on Query {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationDocumentFormat: .definition
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query NameQuery { ...Fragment1 ...Fragment2 ...Fragment3 ...Fragment4 ...FragmentWithLongName1234123412341234123412341234 }"#,
        fragments: [Fragment1.self, Fragment2.self, Fragment3.self, Fragment4.self, FragmentWithLongName1234123412341234123412341234.self]
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenAPQ_automaticallyPersist_generatesWithOperationDefinitionAndIdentifier() async throws {
    // given
    let operationIdentifier = "1ec89997a185c50bacc5f62ad41f27f3070f4a950d72e4a1510a4c64160812d5"
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationIdentifier: operationIdentifier,
      operationDocumentFormat: [.definition, .operationId]
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      operationIdentifier: "1ec89997a185c50bacc5f62ad41f27f3070f4a950d72e4a1510a4c64160812d5",
      definition: .init(
        #\"query NameQuery { name }\"#
      ))
    """
    expect(actual).to(equalLineByLine(expected))
  }

  func test__generate__givenAPQ_persistedOperationsOnly_generatesWithIdentifierOnly() async throws {
    // given
    let operationIdentifier = "1ec89997a185c50bacc5f62ad41f27f3070f4a950d72e4a1510a4c64160812d5"
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      operationIdentifier: operationIdentifier,
      operationDocumentFormat: .operationId
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
      operationIdentifier: "1ec89997a185c50bacc5f62ad41f27f3070f4a950d72e4a1510a4c64160812d5"
    )
    """
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Namespacing tests

  func test__generate__givenCocoapodsCompatibleImportStatements_true_shouldUseCorrectNamespace() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      cocoapodsCompatibleImportStatements: true
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: Apollo.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenCocoapodsCompatibleImportStatements_false_shouldUseCorrectNamespace() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      cocoapodsCompatibleImportStatements: false
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: Access Level Tests

  func test__accessLevel__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsInSchemaModule_shouldRenderWithPublicAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .inSchemaModule
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsEmbeddedInTargetWithPublicAccessModifier_andOperationsInSchemaModule_shouldRenderWithPublicAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public),
      operations: .inSchemaModule
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsEmbeddedInTargetWithInternalAccessModifier_andOperationsInSchemaModule_shouldRenderWithInternalAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal),
      operations: .inSchemaModule
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsRelativeWithPublicAccessModifier_shouldRenderWithPublicAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .public)
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsRelativeWithInternalAccessModifier_shouldRenderWithInternalAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .internal)
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsAbsoluteWithPublicAccessModifier_shouldRenderWithPublicAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "", accessModifier: .public)
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    public static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__accessLevel__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsAbsoluteWithInternalAccessModifier_shouldRenderWithInternalAccess() async throws {
    // given
    document =
    """
    query NameQuery {
      name
    }
    """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "", accessModifier: .internal)
    )

    // when
    let actual = try renderDocumentType()

    // then
    let expected =
    """
    static let operationDocument: ApolloAPI.OperationDocument = .init(
    """
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
}
