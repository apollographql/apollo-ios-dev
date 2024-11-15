import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class OperationManifestFileGeneratorTests: XCTestCase {
  var fileManager: MockApolloFileManager!
  var subject: OperationManifestFileGenerator!

  override func setUp() {
    super.setUp()

    fileManager = MockApolloFileManager(strict: true)
  }

  override func tearDown() {
    subject = nil
    fileManager = nil
    super.tearDown()
  }

  // MARK: Test Helpers

  private func buildSubject(
    path: String? = nil,
    version: ApolloCodegenConfiguration.OperationManifestConfiguration.Version = .legacy
  ) throws {
    let manifest: ApolloCodegenConfiguration.OperationManifestConfiguration? = {
      guard let path else { return nil }
      return .init(path: path, version: version)
    }()

    subject = OperationManifestFileGenerator(
      config: ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock(
        output: .init(
          schemaTypes: .init(path: "", moduleType: .swiftPackageManager())
        ),
        operationManifest: manifest
      ))
    )
  }

  // MARK: Initializer Tests

  func test__initializer__givenPath_shouldReturnInstance() {
    // given
    let config = ApolloCodegenConfiguration.mock(
      output: .init(
        schemaTypes: .init(path: "", moduleType: .swiftPackageManager())
      ),
      operationManifest: .init(
        path: "a/file/path"
      )
    )

    // when
    let instance = OperationManifestFileGenerator(config: .init(config: config))

    // then
    expect(instance).notTo(beNil())
  }

  // MARK: Generate Tests

  func test__generate__givenOperation_shouldWriteToAbsolutePath() async throws {
    // given
    let filePath = "path/to/match"
    try buildSubject(path: filePath)

    let manifest = [
      (OperationDescriptor(.mock(
        name: "TestQuery",
        type: .query,
        source: """
          query TestQuery {
            test
          }
          """
      )),
       "identifier1"
       )
    ]

    fileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    fileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    fileManager.mock(closure: .createFile({ path, data, attributes in
      expect(path).to(equal("\(filePath).json"))

      return true
    }))

    // when
    try await subject.generate(operationManifest: manifest, fileManager: fileManager)

    expect(self.fileManager.allClosuresCalled).to(beTrue())
  }
  
  func test__generate__givenOperation_withPathExtension_shouldWriteToAbsolutePathWithSinglePathExtension() async throws {
    // given
    let filePath = "path/to/match"
    try buildSubject(path: "\(filePath).json")

    let manifest = [
      (OperationDescriptor(.mock(
        name: "TestQuery",
        type: .query,
        source: """
          query TestQuery {
            test
          }
          """
      )),
       "identifier1"
       )
    ]

    fileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    fileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    fileManager.mock(closure: .createFile({ path, data, attributes in
      expect(path).to(equal("\(filePath).json"))

      return true
    }))

    // when
    try await subject.generate(operationManifest: manifest, fileManager: fileManager)

    expect(self.fileManager.allClosuresCalled).to(beTrue())
  }
  
  func test__generate__givenOperation_shouldWriteToRelativePath() async throws {
    // given
    let filePath = "./path/to/match"
    try buildSubject(path: filePath)

    let manifest = [
      (OperationDescriptor(.mock(
        name: "TestQuery",
        type: .query,
        source: """
          query TestQuery {
            test
          }
          """
      )),
       "identifier1"
       )
    ]

    fileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    fileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    fileManager.mock(closure: .createFile({ path, data, attributes in
      let expectedPath = URL(fileURLWithPath: String(filePath.dropFirst(2)), relativeTo: self.subject.config.rootURL)
        .resolvingSymlinksInPath()
        .appendingPathExtension("json")
        .path
      expect(path).to(equal(expectedPath))

      return true
    }))

    // when
    try await subject.generate(operationManifest: manifest, fileManager: fileManager)

    expect(self.fileManager.allClosuresCalled).to(beTrue())
  }
  
  func test__generate__givenOperation_withPathExtension_shouldWriteToRelativePathWithSinglePathExtension() async throws {
    // given
    let filePath = "./path/to/match"
    try buildSubject(path: "\(filePath).json")

    let manifest = [
      (OperationDescriptor(.mock(
        name: "TestQuery",
        type: .query,
        source: """
          query TestQuery {
            test
          }
          """
      )),
       "identifier1"
       )
    ]

    fileManager.mock(closure: .fileExists({ path, isDirectory in
      return false
    }))

    fileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    fileManager.mock(closure: .createFile({ path, data, attributes in
      let expectedPath = URL(fileURLWithPath: String(filePath.dropFirst(2)), relativeTo: self.subject.config.rootURL)
        .resolvingSymlinksInPath()
        .appendingPathExtension("json")
        .path
      expect(path).to(equal(expectedPath))

      return true
    }))

    // when
    try await subject.generate(operationManifest: manifest, fileManager: fileManager)

    expect(self.fileManager.allClosuresCalled).to(beTrue())
  }
  
  func test__generate__givenOperations_whenFileExists_shouldOverwrite() async throws {
    // given
    let filePath = "path/that/exists"
    try buildSubject(path: filePath)

    let manifest = [
      (OperationDescriptor(.mock(
        name: "TestQuery",
        type: .query,
        source: """
          query TestQuery {
            test
          }
          """
      )),
       "identifier1"
       )
    ]

    fileManager.mock(closure: .fileExists({ path, isDirectory in
      return true
    }))

    fileManager.mock(closure: .createDirectory({ path, intermediateDirectories, attributes in
      // no-op
    }))

    fileManager.mock(closure: .createFile({ path, data, attributes in
      expect(path).to(equal("\(filePath).json"))

      expect(String(data: data!, encoding: .utf8)).to(equal(
        """
        {
          "identifier1" : {
            "name": "TestQuery",
            "source": "query TestQuery { test }"
          }
        }
        """
      ))

      return true
    }))

    // when
    try await subject.generate(operationManifest: manifest, fileManager: fileManager)

    expect(self.fileManager.allClosuresCalled).to(beTrue())
  }

  // MARK: - Template Type Selection Tests

  func test__template__givenOperationManifestVersion_legacy__isLegacyTemplate() throws {
    // given
    try buildSubject(path: "a/path", version: .legacy)

    // when
    let actual = subject.template

    // then
    expect(actual).to(beAKindOf(LegacyAPQOperationManifestTemplate.self))
  }

  func test__template__givenOperationManifestVersion_persistedQueries__isPersistedQueriesTemplate() throws {
    // given
    try buildSubject(path: "a/path", version: .persistedQueries)

    // when
    let actual = subject.template as? PersistedQueriesOperationManifestTemplate

    // then
    expect(actual).toNot(beNil())
    expect(actual?.config).to(beIdenticalTo(self.subject.config))
  }
}
