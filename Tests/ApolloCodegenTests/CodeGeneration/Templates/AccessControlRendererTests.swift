import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class AccessControlRendererTests: XCTestCase {

  // MARK: - Helper Methods

  private func buildConfig(
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType,
    operations: ApolloCodegenConfiguration.OperationsFileOutput = .inSchemaModule,
    testMocks: ApolloCodegenConfiguration.TestMockFileOutput = .none
  ) -> ApolloCodegenConfiguration {
    ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      input: .init(schemaPath: "MockInputPath", operationSearchPaths: []),
      output: .mock(
        moduleType: moduleType,
        operations: operations,
        testMocks: testMocks
      )
    )
  }

  // MARK: - SPI Tests

  func test__accessControl__givenPublicModifier_noSPIs_returnsPublicString() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__accessControl__givenInternalModifier_noSPIs_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__accessControl__givenPublicModifier_singleSPI_returnsSPIWithPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl(withSPIs: [.Internal])

    // then
    expect(actual).to(equal("@_spi(Internal) public "))
  }

  func test__accessControl__givenPublicModifier_multipleSPIs_returnsAllSPIsWithPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl(withSPIs: [.Unsafe, .Internal])

    // then
    expect(actual).to(equal("@_spi(Unsafe) @_spi(Internal) public "))
  }

  func test__accessControl__givenInternalModifier_withSPIs_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl(withSPIs: [.Internal, .Execution])

    // then
    expect(actual).to(equal(""))
  }

  func test__accessControl__emptySPIArray_behavesLikeNoSPIs() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl(withSPIs: [])

    // then
    expect(actual).to(equal("public "))
  }

  // MARK: - Schema File Tests

  func test__schemaFile__swiftPackage_namespace_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .namespace
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__swiftPackage_member_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__swiftPackage_parent_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .parent
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__other_namespace_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .other)
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .namespace
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__other_member_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .other)
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__other_parent_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .other)
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .parent
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__embeddedInTarget_publicAccess_namespace_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .namespace
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__embeddedInTarget_publicAccess_member_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__embeddedInTarget_publicAccess_parent_returnsNil() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .parent
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__schemaFile__embeddedInTarget_internalAccess_namespace_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .namespace
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__schemaFile__embeddedInTarget_internalAccess_member_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__schemaFile__embeddedInTarget_internalAccess_parent_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .parent
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  // MARK: - Operation File Tests

  func test__operationFile__inSchemaModule_swiftPackage_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      operations: .inSchemaModule
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__operationFile__inSchemaModule_embeddedInTarget_publicAccess_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public),
      operations: .inSchemaModule
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__operationFile__inSchemaModule_embeddedInTarget_internalAccess_returnsEmptyString() {
    // given
    let config = buildConfig(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal),
      operations: .inSchemaModule
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__operationFile__absolute_publicAccess_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "path", accessModifier: .public)
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__operationFile__absolute_internalAccess_returnsEmptyString() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "path", accessModifier: .internal)
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__operationFile__relative_publicAccess_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .public)
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__operationFile__relative_internalAccess_returnsEmptyString() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .internal)
    )
    let subject = AccessControlRenderer(
      target: .operationFile(),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  // MARK: - Test Mock File Tests

  func test__testMockFile__none_returnsEmptyString() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      testMocks: .none
    )
    let subject = AccessControlRenderer(
      target: .testMockFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  func test__testMockFile__swiftPackage_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      testMocks: .swiftPackage()
    )
    let subject = AccessControlRenderer(
      target: .testMockFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__testMockFile__absolute_publicAccess_returnsPublic() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      testMocks: .absolute(path: "path", accessModifier: .public)
    )
    let subject = AccessControlRenderer(
      target: .testMockFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__testMockFile__absolute_internalAccess_returnsEmptyString() {
    // given
    let config = buildConfig(
      moduleType: .swiftPackage(),
      testMocks: .absolute(path: "path", accessModifier: .internal)
    )
    let subject = AccessControlRenderer(
      target: .testMockFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  // MARK: - Module File Tests

  func test__moduleFile__swiftPackage_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .moduleFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__moduleFile__embeddedInTarget_publicAccess_returnsPublic() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public))
    let subject = AccessControlRenderer(
      target: .moduleFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__moduleFile__embeddedInTarget_internalAccess_returnsEmptyString() {
    // given
    let config = buildConfig(moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    let subject = AccessControlRenderer(
      target: .moduleFile,
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal(""))
  }

  // MARK: - Different SchemaFileType Tests

  func test__schemaFile__schemaMetadata_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .schemaMetadata),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__schemaConfiguration_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .schemaConfiguration),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__object_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .object),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__interface_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .interface),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__union_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .union),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__enum_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .enum),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__customScalar_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .customScalar),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }

  func test__schemaFile__inputObject_returnsCorrectAccessControl() {
    // given
    let config = buildConfig(moduleType: .swiftPackage())
    let subject = AccessControlRenderer(
      target: .schemaFile(type: .inputObject),
      config: config,
      scope: .member
    )

    // when
    let actual = subject.accessControl()

    // then
    expect(actual).to(equal("public "))
  }
}
