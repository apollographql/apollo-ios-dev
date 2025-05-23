import XCTest
import Nimble
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

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
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
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
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
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

  func test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_inSchemaModule_shouldRenderWithPublicAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_EmbededInTargetWithPublicAccessModifier_andOperations_inSchemaModule_shouldRenderWithPublicAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_EmbededInTargetWithInternalAccessModifier_andOperations_inSchemaModule_shouldRenderWithInternalAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_relativeWithPublicAccessModifier_shouldRenderWithPublicAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_relativeWithInternalAccessModifier_shouldRenderWithInternalAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_absoluteWithPublicAccessModifier_shouldRenderWithPublicAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render__givenSelectionSet_whenModuleType_swiftPackageManager_andOperations_absoluteWithInternalAccessModifier_shouldRenderWithInternalAccess() async throws {
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

    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }
  
  // MARK: Object Type Tests
  
  func test__render_givenSelectionSetOnObjectType_parametersDoNotIncludeTypenameFieldAndObjectTypeIsRenderedDirectly() async throws {
    // given
    buildSimpleObjectSchemaAndDocument()
    
    let expected =
    """
      public init(
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Animal.typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """
    
    // when
    try await buildSubjectAndOperation()
    
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    
    let actual = subject.test_render(childEntity: allAnimals.computed)
    
    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """
    
    // when
    try await buildSubjectAndOperation()
    
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    
    let actual = subject.test_render(childEntity: allAnimals.computed)
    
    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenSelectionSetOnUnionType_parametersIncludeFulfilledFragmentsWithUnion() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    type Dog {
      name: String!
    }

    type Cat {
      species: String!
    }

    union AnimalUnion = Dog | Cat
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        ... on AnimalUnion {
          ... on Dog {
            name
          }
        }
      }
    }
    """

    let expected =
    """
      public init(
        name: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Dog.typename,
            "name": name,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsAnimalUnion.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsAnimalUnion.AsDog.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asAnimalUnion_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "AnimalUnion"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asAnimalUnion_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_givenNestedTypeCaseSelectionSetOnInterfaceTypeNotInheritingFromParentInterface_fulfilledFragmentsIncludesAllTypeCasesInScope() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }
    
    interface Animal {
      species: String!
    }
    
    interface Pet {
      species: String!
    }
    
    interface WarmBlooded {
      species: String!
    }
    """
    
    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          ... on WarmBlooded {
            species
          }
        }
      }
    }
    """
    
    let expected =
    """
      public init(
        __typename: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self)
          ]
        ))
      }
    """
    
    // when
    try await buildSubjectAndOperation()
    
    let allAnimals_asPet_asWarmBlooded = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]
    )
    
    let actual = subject.test_render(inlineFragment: allAnimals_asPet_asWarmBlooded.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenNestedTypeCasesMergedFromSibling_fulfilledFragmentsIncludesAllTypeCasesInScope() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet {
      species: String!
    }

    interface WarmBlooded {
      species: String!
    }

    type Cat implements Animal & Pet & WarmBlooded {
      species: String!
      isJellicle: Boolean!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          ... on WarmBlooded {
            species
          }
        }
        ... on Cat {
          isJellicle
        }
      }
    }
    """

    let expected =
    """
      public init(
        isJellicle: Bool,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Cat.typename,
            "isJellicle": isJellicle,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsCat.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asCat = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asCat.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
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
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """
    
    // when
    try await buildSubjectAndOperation()
    
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    
    let actual = subject.test_render(childEntity: allAnimals.computed)
    
    // then
    expect(actual).to(equalLineByLine(expected, atLine: 62, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "FIELDONE": fieldone,
              "FieldTwo": fieldTwo,
              "fieldthree": fieldthree,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """
    
    // when
    try await buildSubjectAndOperation()
    
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    
    let actual = subject.test_render(childEntity: allAnimals.computed)
    
    // then
    expect(actual).to(equalLineByLine(expected, atLine: 20, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "aliased": aliased,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friends": friends._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friends": friends._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_given_optionalListOfOptionalsField_rendersInitializerWithListFieldTransformedToFieldData() async throws {
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friends": friends._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friend": friend._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friends": friends._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """#

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "friend": friend._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
            "age": age,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Height.typename,
            "inches": inches,
            "feet": feet,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsCat.Height.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.Height.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.Height.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let asCat_height = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]?[field: "height"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: asCat_height.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: Named Fragment Tests

  func test__render_givenNamedFragmentSelection_fulfilledFragmentsIncludesNamedFragment() async throws {
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
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected =
    """
      public init(
        __typename: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(AnimalDetails.self)
          ]
        ))
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

  func test__render_givenNamedFragmentSelectionNestedInNamedFragment_fulfilledFragmentsIncludesNamedFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
      ...Fragment2
    }

    fragment Fragment2 on Animal {
      name
    }
    """

    let expected =
    """
      public init(
        __typename: String,
        species: String,
        name: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
            "name": name,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(AnimalDetails.self),
            ObjectIdentifier(Fragment2.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 25, ignoringExtraLines: true))
  }

  func test__render_givenTypeCaseWithNamedFragmentMergedFromParent_fulfilledFragmentsIncludesNamedFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet {
      species: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          ...AnimalDetails
        }
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected =
    """
      public init(
        __typename: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.self),
            ObjectIdentifier(AnimalDetails.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 23, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragmentWithNonMatchingType_fulfilledFragmentsOnlyIncludesNamedFragmentOnTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet {
      species: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Pet {
      species
    }
    """

    let allAnimals_expected =
    """
      public init(
        __typename: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """

    let allAnimals_asPet_expected =
    """
      public init(
        __typename: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsPet.self),
            ObjectIdentifier(AnimalDetails.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    let allAnimals_asPet = try XCTUnwrap(allAnimals[as: "Pet"])

    let allAnimals_actual = subject.test_render(childEntity: allAnimals.computed)
    let allAnimals_asPet_actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(allAnimals_actual).to(equalLineByLine(
      allAnimals_expected, atLine: 16, ignoringExtraLines: true))

    expect(allAnimals_asPet_actual).to(equalLineByLine(
      allAnimals_asPet_expected, atLine: 23, ignoringExtraLines: true))
  }

  /// Verifies the fix for [#2989](https://github.com/apollographql/apollo-ios/issues/2989).
  ///
  /// When a fragment merges a type case from another fragment, the initializer at that type case
  /// scope needs to include both the root and type case selection sets of the merged fragment.
  ///
  /// In this test, we are verifying that the `PredatorFragment.AsPet` selection set is included in
  /// `fulfilledFragments`.
  func test__render_givenNamedFragmentReferencingNamedFragmentInitializedAsTypeCaseFromChildFragment_fulfilledFragmentsIncludesChildFragmentTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }

    interface Pet {
      name: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...Fragment1
      }
    }

    fragment Fragment1 on Animal {
      predators {
        ...PredatorFragment
      }
    }

    fragment PredatorFragment on Animal {
      ... on Pet {
        ...PetFragment
      }
    }

    fragment PetFragment on Pet {
      name
    }
    """

    let expected =
    """
      public init(
        __typename: String,
        name: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "name": name,
          ],
          fulfilledFragments: [
            ObjectIdentifier(Fragment1.Predator.self),
            ObjectIdentifier(Fragment1.Predator.AsPet.self),
            ObjectIdentifier(PredatorFragment.self),
            ObjectIdentifier(PredatorFragment.AsPet.self),
            ObjectIdentifier(PetFragment.self)
          ]
        ))
      }
    """

    // when
    let fragment = try await buildSubjectAndFragment(named: "Fragment1")

    let predators_asPet = try XCTUnwrap(
      fragment[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 26, ignoringExtraLines: true))
  }

  /// Verifies fix for [#2989](https://github.com/apollographql/apollo-ios/issues/2989).
  ///
  /// When a fragment merges a type case from another fragment, the initializer at that type case
  /// scope needs to include both the root and type case selection sets of the merged fragment.
  ///
  /// In this test, we are verifying that the `PredatorFragment.Predator.AsPet` selection set is included in
  /// `fulfilledFragments`.
  func test__render_givenNamedFragmentWithNestedFieldMergedFromChildNamedFragmentInitializedAsTypeCaseFromChildFragment_fulfilledFragmentsIncludesChildFragmentTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }

    interface Pet {
      name: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...Fragment1
      }
    }

    fragment Fragment1 on Animal {
      ...PredatorFragment
    }

    fragment PredatorFragment on Animal {
      predators {
        ... on Pet {
          ...PetFragment
        }
      }
    }

    fragment PetFragment on Pet {
      name
    }
    """

    let expected =
    """
      public init(
        __typename: String,
        name: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "name": name,
          ],
          fulfilledFragments: [
            ObjectIdentifier(Fragment1.Predator.self),
            ObjectIdentifier(Fragment1.Predator.AsPet.self),
            ObjectIdentifier(PredatorFragment.Predator.self),
            ObjectIdentifier(PredatorFragment.Predator.AsPet.self),
            ObjectIdentifier(PetFragment.self)
          ]
        ))
      }
    """

    // when
    let fragment = try await buildSubjectAndFragment(named: "Fragment1")

    let predators_asPet = try XCTUnwrap(
      fragment[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 24, ignoringExtraLines: true))
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "name": name,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithInclusionCondition_rendersInitializerWithFulfilledFragments() async throws {
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "name": name,
              "friend": friend._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithMultipleInclusionConditions_rendersInitializerWithFulfilledFragments() async throws {
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
    query TestOperation($a: Boolean!, $b: Boolean!) {
      allAnimals {
        ... @include(if: $a) @skip(if: $b) {
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "name": name,
              "friend": friend._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfAAndNotB.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a" && !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithNestedInclusionConditions_rendersInitializerWithFulfilledFragments() async throws {
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
    query TestOperation($a: Boolean!, $b: Boolean!) {
      allAnimals {
        ... @include(if: $a) {
          ... @skip(if: $b) {
            name
          }
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "name": name,
              "friend": friend._fieldData,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.IfNotB.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]?[if: !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithInclusionConditionNestedInEntityWithOtherInclusionCondition_rendersInitializerWithFulfilledFragments() async throws {
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
    query TestOperation($a: Boolean!, $b: Boolean!) {
      allAnimals {
        ... @include(if: $a) {
          friend {
            ... @skip(if: $b) {
              name
            }
            species
          }
        }
      }
    }
    """

    let expected = """
        public init(
          name: String,
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "name": name,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.Friend.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.Friend.IfNotB.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_friend = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]?[field: "friend"]?[if: !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_friend.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  // MARK: Named Fragment & Include/Skip Tests

  func test__render_givenNamedFragmentWithInclusionCondition_fulfilledFragmentsOnlyIncludesNamedFragmentOnInlineFragmentForInclusionCondition() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet {
      species: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...AnimalDetails @include(if: $a)
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let allAnimals_expected =
    """
      public init(
        __typename: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """

    let allAnimals_ifA_expected =
    """
      public init(
        __typename: String,
        species: String
      ) {
        self.init(_dataDict: DataDict(
          data: [
            "__typename": __typename,
            "species": species,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.IfA.self),
            ObjectIdentifier(AnimalDetails.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let allAnimals_actual = subject.test_render(childEntity: allAnimals.computed)

    let allAnimals_ifA = try XCTUnwrap(allAnimals[if: "a"])

    let allAnimals_ifA_actual = subject.test_render(inlineFragment: allAnimals_ifA.computed)

    // then
    expect(allAnimals_actual).to(equalLineByLine(
      allAnimals_expected, atLine: 23, ignoringExtraLines: true))
    expect(allAnimals_ifA_actual).to(equalLineByLine(
      allAnimals_ifA_expected, atLine: 23, ignoringExtraLines: true))
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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
            "self": _self,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 18, ignoringExtraLines: true))
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
        self.init(_dataDict: DataDict(
          data: [
            "__typename": TestSchema.Objects.Animal.typename,
            "name": name,
          ],
          fulfilledFragments: [
            ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
          ]
        ))
      }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  // MARK: Defer Tests

  func test__render__givenDeferredInlineFragmentWithoutTypeCase_rendersInitializer() async throws {
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.SlowSpecies.self)
            ]
          ))
        }
      """
    
    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 27, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnSameTypeCase_rendersInitializer() async throws {
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
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.SlowSpecies.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 27, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }
      
      interface Dog {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "slowSpecies") {
            species
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let expected = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.SlowSpecies.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 26, ignoringExtraLines: true))
  }

  func test__render__givenSiblingDeferredInlineFragmentsOnSameTypeCase_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "slowSpecies") {
            species
          }
          ... on Dog @defer(label: "slowGenus") {
            genus
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let expected = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.SlowSpecies.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.SlowGenus.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 29, ignoringExtraLines: true))
  }

  func test__render__givenSiblingDeferredInlineFragmentsOnDifferentTypeCase_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Cat {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "slowSpecies") {
            species
          }
          ... on Cat @defer(label: "slowGenus") {
            genus
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )
    let allAnimals_asCat = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]
    )

    let expected_asDog = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.SlowSpecies.self)
            ]
          ))
        }
      """

    let expected_asCat = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsCat.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsCat.SlowGenus.self)
            ]
          ))
        }
      """

    let actual_asDog = subject.test_render(childEntity: allAnimals_asDog.computed)
    let actual_asCat = subject.test_render(childEntity: allAnimals_asCat.computed)

    // then
    expect(actual_asDog).to(equalLineByLine(expected_asDog, atLine: 26, ignoringExtraLines: true))
    expect(actual_asCat).to(equalLineByLine(expected_asCat, atLine: 26, ignoringExtraLines: true))
  }

  func test__render__givenNestedDeferredInlineFragments_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
        genus: String!
      }
      
      interface Dog {
        id: String!
        species: String!
        genus: String!
        friend: Animal!
      }
      
      interface Cat {
        id: String!
        species: String!
        genus: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ... on Dog @defer(label: "outer") {
            species
            friend {
              ... on Cat @defer(label: "inner") {
                genus
              }
            }
          }
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )
    let allAnimals_asDog_deferredOuter_Friend_asCat = try XCTUnwrap(
      allAnimals_asDog[deferred: .init(label: "outer")]?[field: "friend"]?[as: "Cat"]
    )

    let expected_asDog = """
        public init(
          __typename: String,
          id: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.Outer.self)
            ]
          ))
        }
      """

    let expected_asDog_deferredOuter_Friend_asCat = """
        public init(
          __typename: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.AsCat.self)
            ],
            deferredFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.AsCat.Inner.self)
            ]
          ))
        }
      """

    let actual_asDog = subject.test_render(childEntity: allAnimals_asDog.computed)
    let actual_asDog_deferredOuter_Friend_asCat = subject.test_render(
      childEntity: allAnimals_asDog_deferredOuter_Friend_asCat.computed
    )

    // then
    expect(actual_asDog).to(equalLineByLine(expected_asDog, atLine: 26, ignoringExtraLines: true))
    expect(actual_asDog_deferredOuter_Friend_asCat).to(
      equalLineByLine(expected_asDog_deferredOuter_Friend_asCat, atLine: 24, ignoringExtraLines: true)
    )
  }

  func test__render__givenDeferredNamedFragmentOnSameTypeCase_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(label: "slowSpecies")
        }
      }

      fragment AnimalFragment on Animal {
        species
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
          id: String? = nil
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": __typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
            ],
            deferredFragments: [
              ObjectIdentifier(AnimalFragment.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 27, ignoringExtraLines: true))
  }

  func test__render__givenDeferredNamedFragmentOnDifferentTypeCase_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment @defer(label: "slowSpecies")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let expected = """
        public init(
          id: String? = nil
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Dog.typename,
              "id": id,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self),
              ObjectIdentifier(TestOperationQuery.Data.AllAnimal.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(DogFragment.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 26, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragment_insideNamedFragment_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment
        }
      }

      fragment DogFragment on Dog {
        ... on Dog @defer(label: "slowSpecies") {
          species
        }
      }
      """

    // when
    let fragment = try await buildSubjectAndFragment(named: "DogFragment")
    let fragment_rootField = try XCTUnwrap(fragment.rootField.selectionSet)

    let expected = """
        public init(
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Dog.typename,
            ],
            fulfilledFragments: [
              ObjectIdentifier(DogFragment.self)
            ],
            deferredFragments: [
              ObjectIdentifier(DogFragment.SlowSpecies.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(inlineFragment: fragment_rootField.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 24, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Dog implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...DogFragment
        }
      }

      fragment DogFragment on Animal {
        ... on Dog @defer(label: "slowSpecies") {
          species
        }
      }
      """

    // when
    let fragment = try await buildSubjectAndFragment(named: "DogFragment")
    let fragment_asDog = try XCTUnwrap(fragment[as: "Dog"])

    let expected = """
        public init(
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Dog.typename,
            ],
            fulfilledFragments: [
              ObjectIdentifier(DogFragment.self),
              ObjectIdentifier(DogFragment.AsDog.self)
            ],
            deferredFragments: [
              ObjectIdentifier(DogFragment.AsDog.SlowSpecies.self)
            ]
          ))
        }
      """

    let actual = subject.test_render(inlineFragment: fragment_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 24, ignoringExtraLines: true))
  }

}
