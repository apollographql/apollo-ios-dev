import ApolloCodegenInternalTestHelpers
import IR
import Nimble
import XCTest

@testable import ApolloCodegenLib

class SelectionSetTemplate_Initializers_Tests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: IRTestWrapper<IR.Operation>!
  var subject: SelectionSetTemplate!

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    operation = nil
    subject = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildSubjectAndOperation(
    named operationName: String = "TestOperation",
    schemaNamespace: String = "TestSchema",
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType = .swiftPackage(),
    operations: ApolloCodegenConfiguration.OperationsFileOutput = .inSchemaModule
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: schemaNamespace,
      output: .mock(moduleType: moduleType, operations: operations),
      options: .init()
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
      nonFatalErrorRecorder: .init(),
      accessControlRenderer: mockTemplateRenderer.accessControlRenderer(for: .member)
    )
  }

  func buildSubjectAndFragment(
    named fragmentName: String = "TestFragment",
    schemaNamespace: String = "TestSchema",
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType = .swiftPackage(),
    operations: ApolloCodegenConfiguration.OperationsFileOutput = .inSchemaModule
  ) async throws -> IRTestWrapper<IR.NamedFragment> {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let fragmentDefinition = try XCTUnwrap(ir.compilationResult[fragment: fragmentName])
    let fragment = await ir.build(fragment: fragmentDefinition)
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: schemaNamespace,
      output: .mock(moduleType: moduleType, operations: operations),
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
      nonFatalErrorRecorder: .init(),
      accessControlRenderer: mockTemplateRenderer.accessControlRenderer(for: .member)
    )
    return fragment
  }

  func buildSimpleObjectSchemaAndDocument() {
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          species
        }
      }
      """
  }

  // MARK: - Access Level Tests

  func
    test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_inSchemaModule_shouldRenderWithPublicAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        public init(
      """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .inSchemaModule
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_EmbededInTargetWithPublicAccessModifier_andOperations_inSchemaModule_shouldRenderWithPublicAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        public init(
      """

    try await buildSubjectAndOperation(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .public),
      operations: .inSchemaModule
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_EmbededInTargetWithInternalAccessModifier_andOperations_inSchemaModule_shouldRenderWithInternalAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        init(
      """

    try await buildSubjectAndOperation(
      moduleType: .embeddedInTarget(name: "TestTarget", accessModifier: .internal),
      operations: .inSchemaModule
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_relativeWithPublicAccessModifier_shouldRenderWithPublicAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        public init(
      """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .public)
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_relativeWithInternalAccessModifier_shouldRenderWithInternalAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        init(
      """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .relative(subpath: nil, accessModifier: .internal)
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_absoluteWithPublicAccessModifier_shouldRenderWithPublicAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        public init(
      """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "", accessModifier: .public)
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func
    test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_absoluteWithInternalAccessModifier_shouldRenderWithInternalAccess()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected = """
        init(
      """

    try await buildSubjectAndOperation(
      moduleType: .swiftPackage(),
      operations: .absolute(path: "", accessModifier: .internal)
    )

    let basic = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: basic.computed)

    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  // MARK: Object Type Tests

  func test__render_givenSelectionSetOnObjectType_parametersDoNotIncludeTypenameFieldAndObjectTypeIsRenderedDirectly()
    async throws
  {
    // given
    buildSimpleObjectSchemaAndDocument()

    let expected =
      """
        public init(
          species: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "species": species,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_givenSelectionSetOnInterfaceType_parametersIncludeTypenameField() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          species
        }
      }
      """

    let expected =
      """
        public init(
          __typename: String,
          species: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "species": species,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  // MARK: Selection Tests

  func test__render_given_scalarFieldSelections_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        string: String!
        string_optional: String
        int: Int!
        int_optional: Int
        float: Float!
        float_optional: Float
        boolean: Boolean!
        boolean_optional: Boolean
        custom: Custom!
        custom_optional: Custom
        custom_required_list: [Custom!]!
        custom_optional_list: [Custom!]
        list_required_required: [String!]!
        list_optional_required: [String!]
        list_required_optional: [String]!
        list_optional_optional: [String]
        nestedList_required_required_required: [[String!]!]!
        nestedList_required_required_optional: [[String]!]!
        nestedList_required_optional_optional: [[String]]!
        nestedList_required_optional_required: [[String!]]!
        nestedList_optional_required_required: [[String!]!]
        nestedList_optional_required_optional: [[String]!]
        nestedList_optional_optional_required: [[String!]]
        nestedList_optional_optional_optional: [[String]]
      }

      scalar Custom
      """

    document = """
      query TestOperation {
        allAnimals {
          string
          string_optional
          int
          int_optional
          float
          float_optional
          boolean
          boolean_optional
          custom
          custom_optional
          custom_required_list
          custom_optional_list
          list_required_required
          list_optional_required
          list_required_optional
          list_optional_optional
          nestedList_required_required_required
          nestedList_required_required_optional
          nestedList_required_optional_optional
          nestedList_required_optional_required
          nestedList_optional_required_required
          nestedList_optional_required_optional
          nestedList_optional_optional_required
          nestedList_optional_optional_optional
        }
      }
      """

    let expected = """
        public init(
          string: String,
          string_optional: String? = nil,
          int: Int,
          int_optional: Int? = nil,
          float: Double,
          float_optional: Double? = nil,
          boolean: Bool,
          boolean_optional: Bool? = nil,
          custom: TestSchema.Custom,
          custom_optional: TestSchema.Custom? = nil,
          custom_required_list: [TestSchema.Custom],
          custom_optional_list: [TestSchema.Custom]? = nil,
          list_required_required: [String],
          list_optional_required: [String]? = nil,
          list_required_optional: [String?],
          list_optional_optional: [String?]? = nil,
          nestedList_required_required_required: [[String]],
          nestedList_required_required_optional: [[String?]],
          nestedList_required_optional_optional: [[String?]?],
          nestedList_required_optional_required: [[String]?],
          nestedList_optional_required_required: [[String]]? = nil,
          nestedList_optional_required_optional: [[String?]]? = nil,
          nestedList_optional_optional_required: [[String]?]? = nil,
          nestedList_optional_optional_optional: [[String?]?]? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "string": string,
            "string_optional": string_optional,
            "int": int,
            "int_optional": int_optional,
            "float": float,
            "float_optional": float_optional,
            "boolean": boolean,
            "boolean_optional": boolean_optional,
            "custom": custom,
            "custom_optional": custom_optional,
            "custom_required_list": custom_required_list,
            "custom_optional_list": custom_optional_list,
            "list_required_required": list_required_required,
            "list_optional_required": list_optional_required,
            "list_required_optional": list_required_optional,
            "list_optional_optional": list_optional_optional,
            "nestedList_required_required_required": nestedList_required_required_required,
            "nestedList_required_required_optional": nestedList_required_required_optional,
            "nestedList_required_optional_optional": nestedList_required_optional_optional,
            "nestedList_required_optional_required": nestedList_required_optional_required,
            "nestedList_optional_required_required": nestedList_optional_required_required,
            "nestedList_optional_required_optional": nestedList_optional_required_optional,
            "nestedList_optional_optional_required": nestedList_optional_optional_required,
            "nestedList_optional_optional_optional": nestedList_optional_optional_optional,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 65, ignoringExtraLines: true))
  }

  func test__render_given_differentCasedFields_rendersInitializerWithCorrectCasing() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        FIELDONE: String!
        FieldTwo: String!
        fieldthree: String!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          FIELDONE
          FieldTwo
          fieldthree
        }
      }
      """

    let expected = """
        public init(
          fieldone: String,
          fieldTwo: String,
          fieldthree: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "FIELDONE": fieldone,
            "FieldTwo": fieldTwo,
            "fieldthree": fieldthree,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 23, ignoringExtraLines: true))
  }

  func test__render_given_fieldWithAlias_rendersInitializer() async throws {
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
      query TestOperation {
        allAnimals {
          aliased: species
        }
      }
      """

    let expected = """
        public init(
          aliased: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "aliased": aliased,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_listField_rendersInitializerWithListFieldTransformedToFieldData() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friends: [Animal!]!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friends {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          friends: [Friend]
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friends": friends._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_optionalListField_rendersInitializerWithListFieldTransformedToFieldData() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friends: [Animal!]
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friends {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          friends: [Friend]? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friends": friends._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_optionalListOfOptionalsField_rendersInitializerWithListFieldTransformedToFieldData()
    async throws
  {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friends: [Animal]
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friends {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          friends: [Friend?]? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friends": friends._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_entityFieldSelection_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friend: Animal!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friend {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          friend: Friend
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friend": friend._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_abstractEntityFieldSelectionWithNoFields_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
        friend: Animal!
      }

      type Cat implements Animal {
        species: String!
        friend: Animal!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          ... on Cat {
            friend {
              species
            }
          }
        }
      }
      """

    let expected = """
        public init(
          __typename: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_entityFieldListSelection_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friends: [Animal!]!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friends {
            species
          }
        }
      }
      """

    let expected = #"""
        public init(
          friends: [Friend]
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friends": friends._fieldData,
          ])
        }
      """#

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_entityFieldSelection_nullable_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friend: Animal
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          friend {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          friend: Friend? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "friend": friend._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_mergedSelection_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
        age: Int!
      }

      interface Pet implements Animal {
        species: String!
        age: Int!
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          age
          ... on Pet {
            species
          }
        }
      }
      """

    let expected =
    """
      public init(
        __typename: String,
        species: String,
        age: Int
      ) {
        self.init(unsafelyWithData: [
          "__typename": __typename,
          "species": species,
          "age": age,
        ])
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 21, ignoringExtraLines: true))
  }

  func test__render_given_mergedOnly_SelectionSet_rendersInitializer() async throws {
    // given
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        height: Height
      }

      interface Pet implements Animal {
        height: Height
      }

      type Cat implements Animal & Pet {
        breed: String!
        height: Height
      }

      type Height {
        feet: Int
        inches: Int
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          height {
            inches
          }
          ... on Pet {
            height {
              feet
            }
          }
          ... on Cat {
            breed
          }
        }
      }
      """

    let expected =
      """
        public init(
          inches: Int? = nil,
          feet: Int? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Height.typename,
            "inches": inches,
            "feet": feet,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let asCat_height = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]?[field: "height"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: asCat_height.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 18, ignoringExtraLines: true))
  }

  // MARK: Include/Skip Tests

  func test__render_given_fieldWithInclusionCondition_rendersInitializerWithOptionalParameter() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friend: Animal!
        name: String!
      }
      """

    document = """
      query TestOperation($a: Boolean!) {
        allAnimals {
          name @include(if: $a)
        }
      }
      """

    let expected = """
        public init(
          name: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithInclusionCondition_rendersInitializerWithMergedFieldFromParent()
    async throws
  {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
        friend: Animal!
        name: String!
      }
      """

    document = """
      query TestOperation($a: Boolean!) {
        allAnimals {
          ... @include(if: $a) {
            name
          }
          friend {
            species
          }
        }
      }
      """

    let expected = """
        public init(
          name: String,
          friend: Friend
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
            "friend": friend._fieldData,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 21, ignoringExtraLines: true))
  }

  // MARK: Parameter Name Tests

  func test__render__givenReservedFieldName_shouldGenerateParameterNameWithAlias() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        name: String
        self: String # <- reserved name
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          name
          self
        }
      }
      """

    let expected =
      """
        public init(
          name: String? = nil,
          `self` _self: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
            "self": _self,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 21, ignoringExtraLines: true))
  }

  func test__render__givenFieldName_generatesParameterNameWithoutAlias() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        name: String
      }
      """

    document = """
      query TestOperation {
        allAnimals {
          name
        }
      }
      """

    let expected =
      """
        public init(
          name: String? = nil
        ) {
          self.init(unsafelyWithData: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
          ])
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  // MARK: Defer Tests

  func test__render__givenDeferredInlineFragmentWithoutTypeCase_rendersInitializerWithoutDeferredFields() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... @defer(label: "slowSpecies") {
            species
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let expected = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "id": id,
          ])
        }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 33, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnSameTypeCase_rendersInitializerWithoutDeferredFields() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Animal @defer(label: "slowSpecies") {
            species
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let expected = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(unsafelyWithData: [
            "__typename": __typename,
            "id": id,
          ])
        }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 33, ignoringExtraLines: true))
  }

}
