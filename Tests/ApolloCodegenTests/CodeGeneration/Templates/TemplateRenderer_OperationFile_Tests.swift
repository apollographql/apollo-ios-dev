import XCTest
@testable import ApolloCodegenLib
@testable import ApolloCodegenInternalTestHelpers
import Nimble
import OrderedCollections

class TemplateRenderer_OperationFile_Tests: XCTestCase {

  // MARK: Helpers

  private func buildConfig(
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
    schemaNamespace: String = "testSchema",
    operations: ApolloCodegenConfiguration.OperationsFileOutput,
    cocoapodsCompatibleImportStatements: Bool = false
  ) -> ApolloCodegenConfiguration {
    ApolloCodegenConfiguration.mock(
      schemaNamespace: schemaNamespace,
      input: .init(schemaPath: "MockInputPath", operationSearchPaths: []),
      output: .mock(moduleType: moduleType, operations: operations),
      options: .init(cocoapodsCompatibleImportStatements: cocoapodsCompatibleImportStatements)
    )
  }

  private func buildSubject(
    config: ApolloCodegenConfiguration = .mock(),
    moduleImports: OrderedSet<String>? = nil
  ) -> MockFileTemplate {
    MockFileTemplate(
      target: .operationFile(moduleImports: moduleImports),
      config: ApolloCodegen.ConfigurationContext(config: config))
  }

  // MARK: Render Target .operationFile Tests

  func test__renderTargetOperationFile__givenAllSchemaTypesOperationsCombinations_shouldIncludeHeaderComment() {
    // given
    let expected = """
    // @generated
    // This file was automatically generated and should not be edited.

    """

    let tests: [(
      schemaTypes: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
      operations: ApolloCodegenConfiguration.OperationsFileOutput
    )] = [
      (schemaTypes: .swiftPackage(), operations: .relative(subpath: nil)),
      (schemaTypes: .swiftPackage(), operations: .absolute(path: "path")),
      (schemaTypes: .swiftPackage(), operations: .inSchemaModule),
      (schemaTypes: .other, operations: .relative(subpath: nil)),
      (schemaTypes: .other, operations: .absolute(path: "path")),
      (schemaTypes: .other, operations: .inSchemaModule),
      (schemaTypes: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil)),
      (schemaTypes: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "path")),
      (schemaTypes: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)
    ]

    for test in tests {
      let config = buildConfig(moduleType: test.schemaTypes, operations: test.operations)
      let subject = buildSubject(config: config)

      // when
      let (actual, _) = subject.render()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }

  func test__renderTargetOperationFile__givenAllSchemaTypesOperationsCombinations_conditionallyIncludeImportStatements() {
    // given
    let expectedAPI = """
    @_exported import ApolloAPI

    """

    let expectedAPIAndSchema = """
    @_exported import ApolloAPI
    import TestSchema

    """

    let expectedAPIAndTarget = """
    @_exported import ApolloAPI
    import MockApplication

    """

    let tests: [(
      schemaTypes: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
      operations: ApolloCodegenConfiguration.OperationsFileOutput,
      expectation: String
    )] = [
      (
        schemaTypes: .swiftPackage(),
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .inSchemaModule,
        expectation: expectedAPI
      ),
      (
        schemaTypes: .other,
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .other,
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .other,
        operations: .inSchemaModule,
        expectation: expectedAPI
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndTarget
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndTarget
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .inSchemaModule,
        expectation: expectedAPI
      )
    ]

    for test in tests {
      let config = buildConfig(moduleType: test.schemaTypes, operations: test.operations)
      let subject = buildSubject(config: config)

      // when
      let (actual, _) = subject.render()

      // then
      expect(actual).to(equalLineByLine(test.expectation, atLine: 4, ignoringExtraLines: true))
    }
  }

  func test__renderTargetOperationFile__given_cocoapodsCompatibleImportStatements_true_allSchemaTypesOperationsCombinations_conditionallyIncludeImportStatements() {
    // given
    let expectedAPI = """
    @_exported import Apollo

    """

    let expectedAPIAndSchema = """
    @_exported import Apollo
    import TestSchema

    """

    let expectedAPIAndTarget = """
    @_exported import Apollo
    import MockApplication

    """

    let tests: [(
      schemaTypes: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
      operations: ApolloCodegenConfiguration.OperationsFileOutput,
      expectation: String
    )] = [
      (
        schemaTypes: .swiftPackage(),
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .inSchemaModule,
        expectation: expectedAPI
      ),
      (
        schemaTypes: .other,
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .other,
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndSchema
      ),
      (
        schemaTypes: .other,
        operations: .inSchemaModule,
        expectation: expectedAPI
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .relative(subpath: nil),
        expectation: expectedAPIAndTarget
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .absolute(path: "path"),
        expectation: expectedAPIAndTarget
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .inSchemaModule,
        expectation: expectedAPI
      )
    ]

    for test in tests {
      let config = buildConfig(
        moduleType: test.schemaTypes,
        operations: test.operations,
        cocoapodsCompatibleImportStatements: true
      )
      let subject = buildSubject(config: config)

      // when
      let (actual, _) = subject.render()

      // then
      expect(actual).to(equalLineByLine(test.expectation, atLine: 4, ignoringExtraLines: true))
    }
  }

  func test__renderTargetOperationFile__givenAllSchemaTypesOperationsCombinations_conditionallyWrapInNamespace() {
    // given
    let expectedNoNamespace = """
    root {
      nested
    }
    """

    let expectedPublicNamespace = """
    public extension TestSchema {
      root {
        nested
      }
    }
    """

    let expectedInternalNamespace = """
    extension TestSchema {
      root {
        nested
      }
    }
    """

    let tests: [(
      schemaTypes: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
      operations: ApolloCodegenConfiguration.OperationsFileOutput,
      expectation: String,
      atLine: Int
    )] = [
      (
        schemaTypes: .swiftPackage(),
        operations: .relative(subpath: nil),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .absolute(path: "path"),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .swiftPackage(),
        operations: .inSchemaModule,
        expectation: expectedNoNamespace,
        atLine: 6
      ),
      (
        schemaTypes: .other,
        operations: .relative(subpath: nil),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .other,
        operations: .absolute(path: "path"),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .other,
        operations: .inSchemaModule,
        expectation: expectedNoNamespace,
        atLine: 6
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .relative(subpath: nil),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication"),
        operations: .absolute(path: "path"),
        expectation: expectedNoNamespace,
        atLine: 7
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication", accessModifier: .internal),
        operations: .inSchemaModule,
        expectation: expectedInternalNamespace,
        atLine: 6
      ),
      (
        schemaTypes: .embeddedInTarget(name: "MockApplication", accessModifier: .public),
        operations: .inSchemaModule,
        expectation: expectedPublicNamespace,
        atLine: 6
      )
    ]

    for test in tests {
      let config = buildConfig(moduleType: test.schemaTypes, operations: test.operations)
      let subject = buildSubject(config: config)

      // when
      let (actual, _) = subject.render()

      // then
      expect(actual).to(equalLineByLine(test.expectation, atLine: test.atLine))
    }
  }

  // MARK: Casing Tests

  func test__casing__givenLowercasedSchemaName_shouldGenerateFirstUppercasedNamespace() {
    // given

    let config = buildConfig(
      moduleType: .embeddedInTarget(name: "MockApplication", accessModifier: .public),
      schemaNamespace: "testschema",
      operations: .inSchemaModule)

    let subject = buildSubject(config: config)

    let expected = """
    public extension Testschema {
    """

    // when
    let (actual, _) = subject.render()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__moduleImports__givenValues_shouldGenerateImportStatements() {
    // given
    let config = buildConfig(
      moduleType: 
          .embeddedInTarget(
            name: "MockApplication",
            accessModifier: .public),
      operations: .inSchemaModule
    )

    let moduleImports = OrderedSet(["TestA", "TestB"])

    let subject = buildSubject(config: config, moduleImports: moduleImports)

    let expected = """
    import TestA
    import TestB
    """

    // when
    let (actual, _) = subject.render()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 5, ignoringExtraLines: true))
  }

  func test__casing__givenUppercasedSchemaName_shouldGenerateUppercasedNamespace() {
    // given

    let config = buildConfig(
      moduleType: .embeddedInTarget(name: "MockApplication", accessModifier: .public),
      schemaNamespace: "TESTSCHEMA",
      operations: .inSchemaModule)

    let subject = buildSubject(config: config)

    let expected = """
    public extension TESTSCHEMA {
    """

    // when
    let (actual, _) = subject.render()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__casing__givenCapitalizedSchemaName_shouldGenerateCapitalizedNamespace() {
    // given

    let config = buildConfig(
      moduleType: .embeddedInTarget(name: "MockApplication", accessModifier: .public),
      schemaNamespace: "TestSchema",
      operations: .inSchemaModule)

    let subject = buildSubject(config: config)

    let expected = """
    public extension TestSchema {
    """

    // when
    let (actual, _) = subject.render()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }
}
