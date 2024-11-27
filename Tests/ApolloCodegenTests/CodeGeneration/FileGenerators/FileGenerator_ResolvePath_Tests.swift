import XCTest
import Nimble
import IR
@testable import ApolloCodegenLib
@testable import GraphQLCompiler
import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers

class FileGenerator_ResolvePath_Tests: XCTestCase {

  var irFragment: IR.NamedFragment!
  var irOperation: IR.Operation!
  var subject: FileTarget!
  var config: ApolloCodegenConfiguration!
  var testFilePathBuilder: TestFilePathBuilder!

  var directoryURL: URL { testFilePathBuilder.testIsolatedOutputFolder }

  override func setUp() {
    super.setUp()
    testFilePathBuilder = TestFilePathBuilder(test: self)
  }

  override func tearDown() {
    testFilePathBuilder = nil
    irOperation = nil
    irFragment = nil
    subject = nil
    config = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildIR(
    operationType: CompilationResult.OperationType = .query
  ) async throws {
    let schemaSDL = """
    type Animal {
      species: String
    }

    type Query {
      animals: [Animal]
    }

    type Mutation {
      animals: [Animal]
    }

    type Subscription {
      animals: [Animal]
    }
    """

    let operationDocument = """
    \(operationType.rawValue) AllAnimals {
      animals {
        ...AnimalDetails
      }
    }
    """

    let fragmentDocument = """
    fragment AnimalDetails on Animal {
      species
    }
    """

    let frontend = try await GraphQLJSFrontend()
    let schemaSource = try await frontend.makeSource(schemaSDL, filePath: "")

    let operationSource = try await frontend.makeSource(
      operationDocument,
      filePath: directoryURL
        .appendingPathComponent("\(UUID().uuidString)/operation.graphql").path
    )

    let fragmentSource = try await frontend.makeSource(
      fragmentDocument,
      filePath: directoryURL
        .appendingPathComponent("\(UUID().uuidString)/fragment.graphql").path
    )

    let compilationResult = try await frontend.compile(
      schema: schemaSource, definitions: [
        operationSource,
        fragmentSource
      ],
      config: .init(config: .mock())
    )

    let ir = IRBuilder(compilationResult: compilationResult)

    irFragment = await ir.build(fragment: ir.compilationResult.fragments[0])

    irOperation = await ir.build(operation: ir.compilationResult.operations[0])
  }

  private func buildConfig(
    module: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
    operations: ApolloCodegenConfiguration.OperationsFileOutput,
    testMocks: ApolloCodegenConfiguration.TestMockFileOutput = .none
  ) {
  config = .mock(output: .mock(
      moduleType: module,
      operations: operations,
      testMocks: testMocks,
      path: directoryURL.path
    ))
  }  

  private func deleteLastPathComponent(_ path: String, appending newPath: String? = nil) -> String {
    let result = URL(fileURLWithPath: path).deletingLastPathComponent()

    guard let newPath = newPath else {
      return result.path
    }

    return result.appendingPathComponent(newPath).path
  }

  private func resolvePath() -> String {
    subject.resolvePath(forConfig: ApolloCodegen.ConfigurationContext(config: config))
  }

  var currentWorkingDirectoryPath: String {
    let path = FileManager.default.currentDirectoryPath
    if path.isEmpty {
      return path
    } else {
      return path + "/"
    }
  }

  // MARK: - Resolving Schema Path Tests

  // MARK: .object

  func test__resolvePath__givenFileTargetObject_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleNone_operationsAbsolutePath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleNone_operationsRelativeSubpathNil_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleNone_operationsRelativeSubpath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleOther_operationsAbsolutePath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleOther_operationsRelativeSubpathNil_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetObject_when_moduleOther_operationsRelativeSubpath_shouldReturnObjectsSubpath() {
    // given
    subject = .object

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Objects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .enum

  func test__resolvePath__givenFileTargetEnum_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleNone_operationsAbsolutePath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleNone_operationsRelativeSubpathNil_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleNone_operationsRelativeSubpath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleOther_operationsAbsolutePath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleOther_operationsRelativeSubpathNil_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetEnum_when_moduleOther_operationsRelativeSubpath_shouldReturnEnumsSubpath() {
    // given
    subject = .enum

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Enums")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .interface

  func test__resolvePath__givenFileTargetInterface_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleNone_operationsAbsolutePath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleNone_operationsRelativeSubpathNil_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleNone_operationsRelativeSubpath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleOther_operationsAbsolutePath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleOther_operationsRelativeSubpathNil_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInterface_when_moduleOther_operationsRelativeSubpath_shouldReturnInterfacesSubpath() {
    // given
    subject = .interface

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Interfaces")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .union

  func test__resolvePath__givenFileTargetUnion_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleNone_operationsAbsolutePath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleNone_operationsRelativeSubpathNil_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleNone_operationsRelativeSubpath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleOther_operationsAbsolutePath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleOther_operationsRelativeSubpathNil_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetUnion_when_moduleOther_operationsRelativeSubpath_shouldReturnUnionsSubpath() {
    // given
    subject = .union

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Unions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .inputObjects

  func test__resolvePath__givenFileTargetInputObject_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleNone_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleNone_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleNone_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleOther_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleOther_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetInputObject_when_moduleOther_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .inputObject

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("InputObjects")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .customScalar

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleNone_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleNone_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleNone_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleOther_operationsAbsolutePath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleOther_operationsRelativeSubpathNil_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetCustomScalar_when_moduleOther_operationsRelativeSubpath_shouldReturnInputObjectsSubpath() {
    // given
    subject = .customScalar

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("CustomScalars")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .schema

  func test__resolvePath__givenFileTargetSchema_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnSchemaSubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Schema")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .swiftPackage(), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleNone_operationsInSchemaModule_shouldReturnSchemaSubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleNone_operationsAbsolutePath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleNone_operationsRelativeSubpathNil_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = directoryURL
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleNone_operationsRelativeSubpath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleOther_operationsInSchemaModule_shouldReturnSchemaSubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Schema")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleOther_operationsAbsolutePath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .other, operations: .absolute(path: "NewPath"))

    let expected = directoryURL
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleOther_operationsRelativeSubpathNil_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = directoryURL
      .standardizedFileURL.path
    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSchema_when_moduleOther_operationsRelativeSubpath_shouldReturnEmptySubpath() {
    // given
    subject = .schema

    // when
    buildConfig(module: .other, operations: .relative(subpath: "NewPath"))

    let expected = directoryURL
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .fragment

  func test__resolvePath__givenFileTargetFragment_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnFragmentsSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Fragments")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnAbsolutePathFragmentsDirectory() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .swiftPackage(), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Fragments"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irFragment.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "NewPath"
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irFragment.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleNone_operationsInSchemaModule_shouldReturnFragmentsSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Fragments")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleNone_operationsAbsolutePath_shouldReturnAbsoluteSubpathFragmentsDirectory() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Fragments"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleNone_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irFragment.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleNone_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "NewPath"

    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irFragment.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleOther_operationsInSchemaModule_shouldReturnFragmentsSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Fragments")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleOther_operationsAbsolutePath_shouldReturnAbsoluteSubpathFragmentsDirectory() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "New/Path"

    buildConfig(module: .other, operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Fragments"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleOther_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irFragment.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetFragment_when_moduleOther_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .fragment(irFragment.definition)

    // when
    let path = "NewPath"

    buildConfig(module: .other, operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irFragment.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .operation

  func test__resolvePath__givenFileTargetQuery_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnOperationsQuerySubpath() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Operations")
      .appendingPathComponent("Queries")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnOperationsMutationSubpath() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Operations")
      .appendingPathComponent("Mutations")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleSwiftPackageManager_operationsInSchemaModule_shouldReturnOperationsSubscriptionsSubpath() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Sources")
      .appendingPathComponent("Operations")
      .appendingPathComponent("Subscriptions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetQuery_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnAbsolutePathQueryDirectory() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .swiftPackage(), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Queries"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnAbsolutePathMutationDirectory() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .swiftPackage(), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Mutations"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleSwiftPackageManager_operationsAbsolutePath_shouldReturnAbsolutePathQueryDirectory() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .swiftPackage(), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Subscriptions"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleSwiftPackageManager_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irOperation.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleSwiftPackageManager_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    let path = "NewPath"
    buildConfig(module: .swiftPackage(), operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irOperation.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetQuery_when_moduleNone_operationsInSchemaModule_shouldReturnOperationsQuerySubpath() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Queries")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleNone_operationsInSchemaModule_shouldReturnOperationsMutationSubpath() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Mutations")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleNone_operationsInSchemaModule_shouldReturnOperationsSubscriptionsSubpath() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Subscriptions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetQuery_when_moduleNone_operationsAbsolutePath_shouldReturnAbsoluteSubpathQueryDirectory() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Queries"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleNone_operationsAbsolutePath_shouldReturnAbsoluteSubpathMutationDirectory() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Mutations"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleNone_operationsAbsolutePath_shouldReturnAbsoluteSubpathMutationDirectory() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Subscriptions"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleNone_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irOperation.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleNone_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    let path = "NewPath"

    buildConfig(module: .embeddedInTarget(name: "MockApplication"), operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irOperation.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetQuery_when_moduleOther_operationsInSchemaModule_shouldReturnOperationsQuerySubpath() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Queries")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleOther_operationsInSchemaModule_shouldReturnOperationsMutationSubpath() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Mutations")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleOther_operationsInSchemaModule_shouldReturnOperationsQuerySubpath() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .other, operations: .inSchemaModule)

    let expected = directoryURL
      .appendingPathComponent("Operations")
      .appendingPathComponent("Subscriptions")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetQuery_when_moduleOther_operationsAbsolutePath_shouldReturnAbsoluteSubpathQueryDirectory() async throws {
    // given
    try await buildIR(operationType: .query)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"

    buildConfig(module: .other, operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Queries"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetMutation_when_moduleOther_operationsAbsolutePath_shouldReturnAbsoluteSubpathMutationDirectory() async throws {
    // given
    try await buildIR(operationType: .mutation)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"

    buildConfig(module: .other, operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Mutations"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetSubscription_when_moduleOther_operationsAbsolutePath_shouldReturnAbsoluteSubpathSubscriptionDirectory() async throws {
    // given
    try await buildIR(operationType: .subscription)
    subject = .operation(irOperation.definition)

    // when
    let path = "New/Path"

    buildConfig(module: .other, operations: .absolute(path: path))

    let expected = currentWorkingDirectoryPath + path + "/Subscriptions"

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleOther_operationsRelativeSubpathNil_shouldReturnFilePath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    buildConfig(module: .other, operations: .relative(subpath: nil))

    let expected = deleteLastPathComponent(irOperation.definition.filePath)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetOperation_when_moduleOther_operationsRelativeSubpath_shouldReturnRelativeSubpath() async throws {
    // given
    try await buildIR()
    subject = .operation(irOperation.definition)

    // when
    let path = "NewPath"

    buildConfig(module: .other, operations: .relative(subpath: path))

    let expected = deleteLastPathComponent(irOperation.definition.filePath, appending: path)

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  // MARK: .testMock

  func test__resolvePath__givenFileTargetTestMock_when_moduleSwiftPackageManager_mocksInSwiftPackage_noTargetNane_shouldReturnTestMocksPath() {
    // given
    subject = .testMock

    // when
    buildConfig(
      module: .swiftPackage(),
      operations: .inSchemaModule,
      testMocks: .swiftPackage()
    )

    let expected = directoryURL
      .appendingPathComponent("TestMocks")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetTestMock_when_moduleSwiftPackageManager_mocksInSwiftPackage_withTargetName_shouldReturnTestMocksPathWithCustomName() {
    // given
    subject = .testMock

    // when
    buildConfig(
      module: .swiftPackage(),
      operations: .inSchemaModule,
      testMocks: .swiftPackage(targetName: "CustomMockTarget")
    )

    let expected = directoryURL
      .appendingPathComponent("CustomMockTarget")
      .standardizedFileURL.path

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

  func test__resolvePath__givenFileTargetTestMock_mocksAbsolutePath_shouldReturnPath() {
    // given
    subject = .testMock

    let expected = directoryURL
      .appendingPathComponent("AbsoluteTestMocks")
      .standardizedFileURL.path

    // when
    buildConfig(
      module: .embeddedInTarget(name: "MockApplication"),
      operations: .inSchemaModule,
      testMocks: .absolute(path: expected)
    )

    // then
    let actual = resolvePath()

    expect(actual).to(equal(expected))
  }

}
