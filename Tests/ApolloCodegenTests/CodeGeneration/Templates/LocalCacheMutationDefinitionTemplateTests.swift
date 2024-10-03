import XCTest
import Nimble
import OrderedCollections
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class LocalCacheMutationDefinitionTemplateTests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: IRTestWrapper<IR.Operation>!
  var config: ApolloCodegenConfiguration!
  var subject: LocalCacheMutationDefinitionTemplate!

  override func setUp() {
    super.setUp()
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    query TestOperation @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
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

  // MARK: - Helpers

  private func buildSubjectAndOperation(named operationName: String = "TestOperation") async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)
    subject = LocalCacheMutationDefinitionTemplate(
      operation: operation.irObject,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: - Target Configuration Tests

  func test__target__givenModuleImports_targetHasModuleImports() async throws {
    // given
    document = """
    query TestOperation @apollo_client_ios_localCacheMutation @import(module: "ModuleA") {
      allAnimals {
        species
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    guard case let .operationFile(actual) = subject.target else {
      fail("expected operationFile target")
      return
    }

    // then
    expect(actual).to(equal(["ModuleA"]))
  }

  // MARK: - Access Level Tests

  func test__generate__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsInSchemaModule_generatesWithPublicAccess() async throws {
    // given
    let expected =
    """
    public class TestOperationLocalCacheMutation: LocalCacheMutation {
      public static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .swiftPackageManager,
      operations: .inSchemaModule
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsEmbeddedInTargetWithPublicAccessModifier_andOperationsInSchemaModule_generatesWithPublicAccess() async throws {
    // given
    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      public static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public),
      operations: .inSchemaModule
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsEmbeddedInTargetWithInternalAccessModifier_andOperationsInSchemaModule_generatesWithInternalAccess() async throws {
    // given
    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal),
      operations: .inSchemaModule
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsRelativeWithPublicAccessModifier_generatesWithPublicAccess() async throws {
    // given
    let expected =
    """
    public class TestOperationLocalCacheMutation: LocalCacheMutation {
      public static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .swiftPackageManager,
      operations: .relative(subpath: nil, accessModifier: .public)
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsRelativeWithInternalAccessModifier_generatesWithInternalAccess() async throws {
    // given
    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .swiftPackageManager,
      operations: .relative(subpath: nil, accessModifier: .internal)
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsAbsoluteWithPublicAccessModifier_generatesWithPublicAccess() async throws {
    // given
    let expected =
    """
    public class TestOperationLocalCacheMutation: LocalCacheMutation {
      public static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .swiftPackageManager,
      operations: .absolute(path: "", accessModifier: .public)
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_whenModuleTypeIsSwiftPackageManager_andOperationsAbsoluteWithInternalAccessModifier_generatesWithInternalAccess() async throws {
    // given
    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    config = .mock(output: .mock(
      moduleType: .swiftPackageManager,
      operations: .absolute(path: "", accessModifier: .internal)
    ))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Operation Definition

  func test__generate__givenQuery_generatesLocalCacheMutation() async throws {
    // given
    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate_givenQuery_configIncludesMarkOperationDefinitionsAsFinal_generatesFinalLocalCacheMutation() async throws {
    // given
    let expected =
    """
    final class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query
    """

    config = .mock(options: .init(markOperationDefinitionsAsFinal: true))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }


  func test__generate__givenQueryWithLowercasing_generatesCorrectlyCasedLocalCacheMutation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    query lowercaseOperation($variable: String = "TestVar") @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    class LowercaseOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    // when
    try await buildSubjectAndOperation(named: "lowercaseOperation")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithNameEndingInLocalCacheMutation_generatesLocalCacheMutationWithoutDoubledTypeSuffix() async throws {
    // given
    document = """
    query TestOperationLocalCacheMutation @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .query

    """

    // when
    try await buildSubjectAndOperation(named: "TestOperationLocalCacheMutation")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenMutation_generatesLocalCacheMutation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Mutation {
      addAnimal: Animal!
    }

    type Animal {
      species: String!
    }
    """

    document = """
    mutation TestOperation @apollo_client_ios_localCacheMutation {
      addAnimal {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .mutation

    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenSubscription_generatesSubscriptionOperation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Subscription {
      streamAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    subscription TestOperation @apollo_client_ios_localCacheMutation {
      streamAnimals {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
      static let operationType: GraphQLOperationType = .subscription

    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQuery_generatesSelectionSetsAsMutable() async throws {
    // given
    let expected =
    """
      struct Data: TestSchema.MutableSelectionSet {
        var __data: DataDict
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__generate__givenLowercasedSchemaName_generatesSelectionSetsWithFirstUppercasedNamespace() async throws {
    // given
    let expected =
    """
      struct Data: Myschema.MutableSelectionSet {
        var __data: DataDict
    """

    // when
    config = .mock(schemaNamespace: "myschema")
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__generate__givenUppercasedSchemaName_generatesSelectionSetsWithUppercasedNamespace() async throws {
    // given
    let expected =
    """
      struct Data: MYSCHEMA.MutableSelectionSet {
        var __data: DataDict
    """

    // when
    config = .mock(schemaNamespace: "MYSCHEMA")
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_swiftPackageManager_generatesClassDefinition_withPublicModifier() async throws {
    // given
    config = .mock(.swiftPackageManager)
    try await buildSubjectAndOperation()

    let expected = """
    public class TestOperationLocalCacheMutation: LocalCacheMutation {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_other_generatesClassDefinition_withPublicModifier() async throws {
    // given
    config  = .mock(.other)
    try await buildSubjectAndOperation()

    let expected = """
    public class TestOperationLocalCacheMutation: LocalCacheMutation {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_embeddedInTarget_generatesClassDefinition_noPublicModifier() async throws {
    // given
    config = .mock(.embeddedInTarget(name: "MyOtherProject"))
    try await buildSubjectAndOperation()

    let expected = """
    class TestOperationLocalCacheMutation: LocalCacheMutation {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Variables

  func test__generate__givenQueryWithScalarVariable_generatesQueryOperationWithVariable() async throws {
     // given
     schemaSDL = """
     type Query {
       allAnimals: [Animal!]
     }

     type Animal {
       species: String!
     }
     """

     document = """
     query TestOperation($variable: String!) @apollo_client_ios_localCacheMutation {
       allAnimals {
         species
       }
     }
     """

     let expected =
     """
       public var variable: String

       public init(variable: String) {
         self.variable = variable
       }

       public var __variables: GraphQLOperation.Variables? { ["variable": variable] }
     """

     // when
    try await buildSubjectAndOperation()

     let actual = renderSubject()

     // then
     expect(actual).to(equalLineByLine(expected, atLine: 4, ignoringExtraLines: true))
   }

  func test__generate__givenQueryWithMutlipleScalarVariables_generatesQueryOperationWithVariables() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
      intField: Int!
    }
    """

    document = """
    query TestOperation($variable1: String!, $variable2: Boolean!, $variable3: Int!) @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable1: String
      public var variable2: Bool
      public var variable3: Int

      public init(
        variable1: String,
        variable2: Bool,
        variable3: Int
      ) {
        self.variable1 = variable1
        self.variable2 = variable2
        self.variable3 = variable3
      }

      public var __variables: GraphQLOperation.Variables? { [
        "variable1": variable1,
        "variable2": variable2,
        "variable3": variable3
      ] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 4, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithNullableScalarVariable_generatesQueryOperationWithVariable() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    query TestOperation($variable: String = "TestVar") @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable: GraphQLNullable<String>

      public init(variable: GraphQLNullable<String> = "TestVar") {
        self.variable = variable
      }

      public var __variables: GraphQLOperation.Variables? { ["variable": variable] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 4, ignoringExtraLines: true))
  }

  // MARK: Initializer Rendering Config - Tests

  func test__render_givenLocalCacheMutation_rendersInitializer() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    query TestOperation @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
        }

        init(
    """

    config = ApolloCodegenConfiguration.mock(
      schemaNamespace: "TestSchema",
      options: .init(
        selectionSetInitializers: []
      )
    )

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 18, ignoringExtraLines: true))
  }

}
