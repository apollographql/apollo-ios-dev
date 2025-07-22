import XCTest
import Nimble
@testable import ApolloCodegenLib
@testable import ApolloCodegenInternalTestHelpers

class FileGeneratorTests: XCTestCase {

  var fileManager: MockApolloFileManager!
  var config: ApolloCodegen.ConfigurationContext!
  var fileTarget: FileTarget!
  var template: MockFileTemplate!
  var subject: MockFileGenerator!

  override func setUp() {
    super.setUp()
    fileManager = MockApolloFileManager(strict: false)
  }

  override func tearDown() {
    template = nil
    subject = nil
    fileTarget = nil
    config = nil
    fileManager = nil

    super.tearDown()
  }

  // MARK: Helpers

  private func buildConfig() {
    let mockedConfig = ApolloCodegenConfiguration.mock(output: .mock(
      moduleType: .swiftPackage(),      
      operations: .inSchemaModule
    ))

    config = ApolloCodegen.ConfigurationContext(config: mockedConfig)
  }

  private func buildSubject(extension: String = "graphql.swift") {
    template = MockFileTemplate.mock(target: .schemaFile(type: .schemaMetadata))
    fileTarget = .object
    subject = MockFileGenerator.mock(
      template: template,
      target: fileTarget,
      filename: "lowercasedType",
      extension: `extension`
    )
  }

  // MARK: - Tests

  func test__generate__shouldWriteToCorrectPath() async throws {
    // given
    buildConfig()
    buildSubject()

    let expected = self.fileTarget.resolvePath(forConfig: self.config)
    
    await fileManager.mock(closure: .createFile({ path, data, attributes in

      // then
      let actual = URL(fileURLWithPath: path).deletingLastPathComponent().path
      expect(actual).to(equal(expected))

      return true
    }))

    // when
    _ = try await subject.generate(forConfig: config, fileManager: fileManager)

    // then
    await expect{ await self.fileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__shouldFirstUppercaseFilename() async throws {
    // given
    buildConfig()
    buildSubject()

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      let expected = "LowercasedType.graphql.swift"

      // then
      let actual = URL(fileURLWithPath: path).lastPathComponent
      expect(actual).to(equal(expected))

      return true
    }))

    // when
    _ = try await subject.generate(forConfig: config, fileManager: fileManager)

    // then
    await expect{ await self.fileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__shouldAddExtensionToFilePath() async throws {
    // given
    buildConfig()
    buildSubject(extension: "test")

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      let expected = "LowercasedType.test"

      // then
      let actual = URL(fileURLWithPath: path).lastPathComponent
      expect(actual).to(equal(expected))

      return true
    }))

    // when
    _ = try await subject.generate(forConfig: config, fileManager: fileManager)

    // then
    await expect{ await self.fileManager.allClosuresCalled }.to(beTrue())
  }

  func test__generate__shouldWriteRenderedTemplate() async throws {
    // given
    buildConfig()
    buildSubject()

    let (actual, _) = template.render()
    let expectedData = actual.data(using: .utf8)

    await fileManager.mock(closure: .createFile({ path, data, attributes in
      // then
      expect(data).to(equal(expectedData))

      return true
    }))

    // when
    _ = try await subject.generate(forConfig: config, fileManager: fileManager)

    // then
    await expect{ await self.fileManager.allClosuresCalled }.to(beTrue())
  }
}
