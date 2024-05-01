import ApolloCodegenInternalTestHelpers
import IR
import Nimble
import XCTest

@testable import ApolloCodegenLib

class SelectionSetTemplate_ErrorHandling_Tests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: IRTestWrapper<IR.Operation>!
  var subject: SelectionSetTemplate!
  var errorRecorder: ApolloCodegen.NonFatalError.Recorder!

  override func setUp() {
    super.setUp()
    errorRecorder = .init()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    operation = nil
    subject = nil
    errorRecorder = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildSubjectAndOperation(
    named operationName: String = "ConflictingQuery",
    fieldMerging: ApolloCodegenConfiguration.FieldMerging = .all
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(
      operation: operationDefinition,
      mergingStrategy: fieldMerging.options
    )
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      output: .mock(moduleType: .swiftPackageManager, operations: .inSchemaModule),
      options: .init(
        fieldMerging: fieldMerging
      )
    )
    let mockTemplateRenderer = MockTemplateRenderer(
      target: .operationFile(),
      template: "",
      config: .init(config: config)
    )
    subject = SelectionSetTemplate(
      definition: self.operation.irObject,
      generateInitializers: true,
      config: ApolloCodegen.ConfigurationContext(config: config),
      nonFatalErrorRecorder: errorRecorder,
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
    )
  }

  func buildSubjectAndFragment(named fragmentName: String) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let fragmentDefinition = try XCTUnwrap(ir.compilationResult[fragment: fragmentName])
    let fragment = await ir.build(fragment: fragmentDefinition)
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      output: .mock(moduleType: .swiftPackageManager, operations: .inSchemaModule),
      options: .init()
    )
    let mockTemplateRenderer = MockTemplateRenderer(
      target: .operationFile(),
      template: "",
      config: .init(config: config)
    )
    subject = SelectionSetTemplate(
      definition: fragment.irObject,
      generateInitializers: true,
      config: ApolloCodegen.ConfigurationContext(config: config),
      nonFatalErrorRecorder: errorRecorder,
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
    )
  }

  func test__validation__selectionSet_typeConflicts_shouldReturnNonFatalError() async throws {
    // given
    schemaSDL = """
      type Query {
        user: User
      }

      type User {
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }

      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
          user {
              containers {
                  value {
                      propertyA
                      propertyB
                      propertyC
                      propertyD
                  }

                  values {
                      propertyA
                      propertyC
                  }
              }
          }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "value",
      conflictingName: "values",
      containingObject: "ConflictingQuery.Data.User.Container"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func test__validation__selectionSet_typeWithConflictingNameOnParentEntity_shouldNotReturnError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }

      type User {
        value: Value
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }

      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
          user {
              value {
                  propertyA
                  propertyB
                  propertyC
                  propertyD
              }
              containers {
                  values {
                      propertyA
                      propertyC
                  }
              }
          }
      }
      """

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors).to(beEmpty())
  }

  func
    test__validation__selectionSet_typeConflicts_withDirectInlineFragment_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }
      type User {
        containers: [ContainerInterface]
      }
      interface ContainerInterface {
        value: Value
      }
      type Container implements ContainerInterface{
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
        user {
          containers {
            value {
              propertyA
              propertyB
              propertyC
              propertyD
            }
            ... on Container {
              values {
                propertyA
                propertyC
              }
            }
          }
        }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "values",
      conflictingName: "value",
      containingObject: "ConflictingQuery.Data.User.Container.AsContainer"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withDirectInlineFragment_withFieldMerging_notIncludingAncestors_shouldNotReturnError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }
      type User {
        containers: [ContainerInterface]
      }
      interface ContainerInterface {
        value: Value
      }
      type Container implements ContainerInterface{
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
        user {
          containers {
            value {
              propertyA
              propertyB
              propertyC
              propertyD
            }
            ... on Container {
              values {
                propertyA
                propertyC
              }
            }
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation(fieldMerging: .siblings)
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors).to(beEmpty())
  }

  func
    test__validation__selectionSet_typeConflicts_withMergedInlineFragment_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: UserInterface
      }
      type User implements UserInterface {
        containers: [ContainerInterface]
      }
      interface UserInterface {
        containers: [ContainerInterface]
      }
      interface ContainerInterface {
        value: Value
      }
      type Container implements ContainerInterface {
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
        user {
          containers {
              value {
                propertyA
                propertyB
                propertyC
                propertyD
              }
          }
          ... on User {
            containers {
              ... on Container {
                values {
                  propertyA
                  propertyC
                }
              }
            }
          }
        }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "values",
      conflictingName: "value",
      containingObject: "ConflictingQuery.Data.User.AsUser.Container.AsContainer"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withDirectNamedFragment_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }
      type User {
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
        user {
          containers {
            value {
              propertyA
              propertyB
              propertyC
              propertyD
            }
            ...ContainerFields
          }
        }
      }

      fragment ContainerFields on Container {
        values {
          propertyA
          propertyC
        }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "value",
      conflictingName: "values",
      containingObject: "ConflictingQuery.Data.User.Container"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withDirectNamedFragment_givenFieldMerging_notIncludingNamedFragments_shouldNotReturnError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }
      type User {
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
        user {
          containers {
            value {
              propertyA
              propertyB
              propertyC
              propertyD
            }
            ...ContainerFields
          }
        }
      }

      fragment ContainerFields on Container {
        values {
          propertyA
          propertyC
        }
      }
      """

    // when
    try await buildSubjectAndOperation(fieldMerging: [.ancestors, .siblings])
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors).to(beEmpty())    
  }

  func test__validation__selectionSet_typeConflicts_withNamedFragment_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
        user: User
      }
      type User {
        containers: [Container]
      }

      type Container {
        value: Value
        values: [Value]
      }
      type Value {
        propertyA: String!
        propertyB: String!
        propertyC: String!
        propertyD: String!
      }
      """

    document = """
      fragment ContainerFields on Container {
        value {
          propertyA
          propertyB
          propertyC
          propertyD
        }
        values {
          propertyA
          propertyC
        }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "value",
      conflictingName: "values",
      containingObject: "ContainerFields"
    )

    // when
    try await buildSubjectAndFragment(named: "ContainerFields")
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withNamedFragmentFieldCollisionWithinInlineFragment_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
          user: User
      }

      type User {
          containers: [ContainerInterface]
      }

      interface ContainerInterface {
          value: Value
      }

      type Container implements ContainerInterface{
          value: Value
          values: [Value]
          user: Int
      }

      type Value {
          propertyA: String!
          propertyB: String!
          propertyC: String!
          propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
          user {
            containers {
              value {
                propertyA
                propertyB
                propertyC
                propertyD
              }
              ... on Container {
                ...ValueFragment
              }
            }
          }
      }

      fragment ValueFragment on Container {
          values {
              propertyA
              propertyC
          }
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "value",
      conflictingName: "values",
      containingObject: "ConflictingQuery.Data.User.Container.AsContainer"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withNamedFragmentWithinInlineFragmentTypeCollision_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
          user: User
      }

      type User {
          containers: [ContainerInterface]
      }

      interface ContainerInterface {
          value: Value
      }

      type Container implements ContainerInterface{
          nestedContainer: NestedContainer
          value: Value
          values: [Value]
          user: Int
      }

      type Value {
          propertyA: String!
          propertyB: String!
          propertyC: String!
          propertyD: String!
      }

      type NestedContainer {
          values: [Value]
          description: String
      }
      """

    document = """
      query ConflictingQuery {
          user {
            containers {
              value {
                propertyA
                propertyB
                propertyC
                propertyD
              }
              ... on Container {
                nestedContainer {
                  ...value
                }
              }
            }
          }
      }

      fragment value on NestedContainer {
          description
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "value",
      conflictingName: "value",
      containingObject: "ConflictingQuery.Data.User.Container.AsContainer.NestedContainer"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }

  func
    test__validation__selectionSet_typeConflicts_withFieldUsingNamedFragmentCollision_shouldReturnNonFatalError()
    async throws
  {
    schemaSDL = """
      type Query {
          user: User
      }

      type User {
          containers: [Container]
      }

      type Container {
          info: Value
      }

      type Value {
          propertyA: String!
          propertyB: String!
          propertyC: String!
          propertyD: String!
      }
      """

    document = """
      query ConflictingQuery {
          user {
            containers {
              info {
                  ...Info
              }
            }
          }
      }

      fragment Info on Value {
          propertyA
          propertyB
          propertyD
      }
      """

    let expectedError = ApolloCodegen.NonFatalError.typeNameConflict(
      name: "info",
      conflictingName: "Info",
      containingObject: "ConflictingQuery.Data.User.Container.Info"
    )

    // when
    try await buildSubjectAndOperation()
    _ = subject.renderBody()

    // then
    expect(self.errorRecorder.recordedErrors.count).to(equal(1))
    expect(self.errorRecorder.recordedErrors.first).to(equal(expectedError))
  }
}
