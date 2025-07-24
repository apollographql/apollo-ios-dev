import XCTest
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers
import Nimble

class SchemaModuleFileGeneratorTests: XCTestCase {
  var mockFileManager: MockApolloFileManager!

  var testFilePathBuilder: TestFilePathBuilder!

  var rootURL: URL { testFilePathBuilder.testIsolatedOutputFolder }

  override func setUp() {
    super.setUp()
    testFilePathBuilder = TestFilePathBuilder(test: self)
    mockFileManager = MockApolloFileManager(strict: false)
  }

  override func tearDown() {
    testFilePathBuilder = nil
    mockFileManager = nil
    super.tearDown()
  }

  // MARK: - Tests

  func test__generate__givenModuleType_swiftPackageManager_shouldGeneratePackageFile() async throws {
    // given
    let fileURL = rootURL.appendingPathComponent("Package.swift")

    let configuration = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      .swiftPackage(),
      to: rootURL.path
    ))

    await mockFileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      expect(path).to(equal(fileURL.path))

      return true
    }))

    // when
    _ = try await SchemaModuleFileGenerator.generate(configuration, fileManager: mockFileManager)

    // then
    await expect{ await self.mockFileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__givenModuleTypeEmbeddedInTarget_lowercaseSchemaName_shouldGenerateNamespaceFileWithCapitalizedName() async throws {
    // given
    let fileURL = rootURL.appendingPathComponent("Schema.graphql.swift")

    let configuration = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      .embeddedInTarget(name: "MockApplication"),
      schemaNamespace: "schema",
      to: rootURL.path
    ))

    await mockFileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      expect(path).to(equal(fileURL.path))

      return true
    }))

    // when
    _ = try await SchemaModuleFileGenerator.generate(configuration, fileManager: mockFileManager)

    // then
    await expect{ await self.mockFileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__givenModuleTypeEmbeddedInTarget_uppercaseSchemaName_shouldGenerateNamespaceFileWithUppercaseName() async throws {
    // given
    let fileURL = rootURL.appendingPathComponent("SCHEMA.graphql.swift")

    let configuration = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      .embeddedInTarget(name: "MockApplication"),
      schemaNamespace: "SCHEMA",
      to: rootURL.path
    ))

    await mockFileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      expect(path).to(equal(fileURL.path))

      return true
    }))

    // when
    _ = try await SchemaModuleFileGenerator.generate(configuration, fileManager: mockFileManager)

    // then
    await expect{ await self.mockFileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__givenModuleTypeEmbeddedInTarget_capitalizedSchemaName_shouldGenerateNamespaceFileWithCapitalizedName() async throws {
    // given
    let fileURL = rootURL.appendingPathComponent("MySchema.graphql.swift")

    let configuration = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      .embeddedInTarget(name: "MockApplication"),
      schemaNamespace: "MySchema",
      to: rootURL.path
    ))

    await mockFileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      expect(path).to(equal(fileURL.path))

      return true
    }))

    // when
    _ = try await SchemaModuleFileGenerator.generate(configuration, fileManager: mockFileManager)

    // then
    await expect{ await self.mockFileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__givenModuleType_other_shouldNotGenerateFile() async throws {
    // given
    mockFileManager = MockApolloFileManager(
      strict: false,
      requireAllClosuresCalled: false
    )

    let configuration = ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
      .other,
      to: rootURL.path
    ))

    await mockFileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      fail("Unexpected module file created at \(path)")

      return true
    }))

    // when
    _ = try await SchemaModuleFileGenerator.generate(configuration, fileManager: mockFileManager)

    // then
    await expect{ await self.mockFileManager.allClosuresCalled }.to(beFalse())
  }
}
