import XCTest
import Nimble
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class SelectionSetTemplateTests: XCTestCase {

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
    configOutput: ApolloCodegenConfiguration.FileOutput = .mock(),
    inflectionRules: [ApolloCodegenLib.InflectionRule] = [],
    schemaDocumentation: ApolloCodegenConfiguration.Composition = .exclude,
    warningsOnDeprecatedUsage: ApolloCodegenConfiguration.Composition = .exclude,
    conversionStrategies: ApolloCodegenConfiguration.ConversionStrategies = .init(),
    cocoapodsImportStatements: Bool = false
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)
    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      schemaNamespace: "TestSchema",
      output: configOutput,
      options: .init(
        additionalInflectionRules: inflectionRules,
        schemaDocumentation: schemaDocumentation,
        cocoapodsCompatibleImportStatements: cocoapodsImportStatements,
        warningsOnDeprecatedUsage: warningsOnDeprecatedUsage,
        conversionStrategies: conversionStrategies
      )
    ))
    let mockTemplateRenderer = MockTemplateRenderer(
      target: .operationFile(),
      template: "",
      config: config
    )
    subject = SelectionSetTemplate(
      definition: self.operation.irObject,
      generateInitializers: false,
      config: config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
    )
  }
  
  func buildFragment(
    named fragmentName: String,
    in ir: IRBuilderTestWrapper,
    configOutput: ApolloCodegenConfiguration.FileOutput = .mock(),
    inflectionRules: [ApolloCodegenLib.InflectionRule] = [],
    schemaDocumentation: ApolloCodegenConfiguration.Composition = .exclude,
    warningsOnDeprecatedUsage: ApolloCodegenConfiguration.Composition = .exclude,
    conversionStrategies: ApolloCodegenConfiguration.ConversionStrategies = .init(),
    cocoapodsImportStatements: Bool = false
  ) async throws -> FragmentTemplate {
    let fragmentDefinition = try XCTUnwrap(ir.compilationResult[fragment: fragmentName])
    let fragment = await ir.build(fragment: fragmentDefinition)
    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      schemaNamespace: "TestSchema",
      output: configOutput,
      options: .init(
        additionalInflectionRules: inflectionRules,
        schemaDocumentation: schemaDocumentation,
        cocoapodsCompatibleImportStatements: cocoapodsImportStatements,
        warningsOnDeprecatedUsage: warningsOnDeprecatedUsage,
        conversionStrategies: conversionStrategies
      )
    ))
    
    return FragmentTemplate(fragment: fragment.irObject, config: config)
  }

  // MARK: - Tests

  func test__render_rendersClosingBracket() async throws {
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
        species
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = try XCTUnwrap(subject.test_render(childEntity: allAnimals.computed))

    // then
    expect(String(actual.reversed())).to(equalLineByLine("}", ignoringExtraLines: true))
  }

  // MARK: Parent Type

  func test__render_parentType__givenParentTypeAs_Object_rendersParentType() async throws {
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
        species
      }
    }
    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Animal }
    """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_parentType__givenParentTypeAs_Interface_rendersParentType() async throws {
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

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_parentType__givenParentTypeAs_Union_rendersParentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Dog {
      species: String!
    }

    union Animal = Dog
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Unions.Animal }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_parentType__givenCocoapodsImportStatements_true_rendersParentTypeWithApolloNamespace() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Dog {
      species: String!
    }

    union Animal = Dog
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public static var __parentType: any Apollo.ParentType { TestSchema.Unions.Animal }
    """

    // when
    try await buildSubjectAndOperation(cocoapodsImportStatements: true)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  // MARK: - Selections

  func test__render_selections__givenCocoapodsImportStatements_true_rendersSelectionsWithApolloNamespace() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      FieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        FieldName
      }
    }
    """

    let expected = """
      public static var __selections: [Apollo.Selection] { [
        .field("__typename", String.self),
        .field("FieldName", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation(cocoapodsImportStatements: true)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenNilDirectSelections_mergedFromMultipleSources_doesNotRenderSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Dog implements Pet {
      species: String!
      nested: Nested!
    }

    interface Pet {
      nested: Nested!
    }

    type Nested {
      a: Int!
      b: Int!
    }

    interface Animal {
      nested: Nested!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        nested {
          a
        }
        ... on Dog {
          species
        }
        ... on Pet {
          nested {
            b
          }
        }
      }
    }
    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Nested }

      public var a: Int { __data["a"] }
    """

    // when
    try await buildSubjectAndOperation()
    let asDog_Nested = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "nested"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: asDog_Nested.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_selections__givenCustomRootTypes_doesNotGenerateTypenameField() async throws {
    // given
    schemaSDL = """
    schema {
      query: RootQueryType
      mutation: RootMutationType
    }

    type RootQueryType {
      allAnimals: [Animal!]
    }

    type RootMutationType {
      feedAnimal: Animal!
    }

    type Animal {
      FieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        FieldName
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("allAnimals", [AllAnimal]?.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Selections - Fields

  func test__render_selections__givenScalarFieldSelections_rendersAllFieldSelections() async throws {
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
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", String.self),
        .field("string_optional", String?.self),
        .field("int", Int.self),
        .field("int_optional", Int?.self),
        .field("float", Double.self),
        .field("float_optional", Double?.self),
        .field("boolean", Bool.self),
        .field("boolean_optional", Bool?.self),
        .field("custom", TestSchema.Custom.self),
        .field("custom_optional", TestSchema.Custom?.self),
        .field("custom_required_list", [TestSchema.Custom].self),
        .field("custom_optional_list", [TestSchema.Custom]?.self),
        .field("list_required_required", [String].self),
        .field("list_optional_required", [String]?.self),
        .field("list_required_optional", [String?].self),
        .field("list_optional_optional", [String?]?.self),
        .field("nestedList_required_required_required", [[String]].self),
        .field("nestedList_required_required_optional", [[String?]].self),
        .field("nestedList_required_optional_optional", [[String?]?].self),
        .field("nestedList_required_optional_required", [[String]?].self),
        .field("nestedList_optional_required_required", [[String]]?.self),
        .field("nestedList_optional_required_optional", [[String?]]?.self),
        .field("nestedList_optional_optional_required", [[String]?]?.self),
        .field("nestedList_optional_optional_optional", [[String?]?]?.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenAllUppercase_generatesCorrectCasing() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      FIELDNAME: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        FIELDNAME
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("FIELDNAME", String?.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenCustomScalar_rendersFieldSelectionsWithNamespaceInAllConfigurations() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      custom: Custom!
      custom_optional: Custom
      custom_required_list: [Custom!]!
      custom_optional_list: [Custom!]
      lowercaseCustom: lowercaseCustom!
    }

    scalar Custom
    scalar lowercaseCustom
    """

    document = """
    query TestOperation {
      allAnimals {
        custom
        custom_optional
        custom_required_list
        custom_optional_list
        lowercaseCustom
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("custom", TestSchema.Custom.self),
        .field("custom_optional", TestSchema.Custom?.self),
        .field("custom_required_list", [TestSchema.Custom].self),
        .field("custom_optional_list", [TestSchema.Custom]?.self),
        .field("lowercaseCustom", TestSchema.LowercaseCustom.self),
      ] }
    """

    let tests: [ApolloCodegenConfiguration.FileOutput] = [
      .mock(moduleType: .swiftPackageManager(), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .inSchemaModule),
      .mock(moduleType: .other, operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .other, operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .other, operations: .inSchemaModule),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .inSchemaModule)
    ]

    for test in tests {
      // when
      try await buildSubjectAndOperation(configOutput: test)
      let allAnimals = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?.selectionSet
      )

      let actual = subject.test_render(childEntity: allAnimals.computed)

      // then
      expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
    }
  }

  func test__render_selections__givenEnumField_rendersFieldSelectionsWithNamespaceInAllConfigurations() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      testEnum: TestEnum!
      testEnumOptional: TestEnumOptional
      lowercaseEnum: lowercaseEnum!
    }

    enum TestEnum {
      CASE_ONE
    }

    enum TestEnumOptional {
      CASE_ONE
    }

    enum lowercaseEnum {
      CASE_ONE
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        testEnum
        testEnumOptional
        lowercaseEnum
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("testEnum", GraphQLEnum<TestSchema.TestEnum>.self),
        .field("testEnumOptional", GraphQLEnum<TestSchema.TestEnumOptional>?.self),
        .field("lowercaseEnum", GraphQLEnum<TestSchema.LowercaseEnum>.self),
      ] }
    """

    let tests: [ApolloCodegenConfiguration.FileOutput] = [
      .mock(moduleType: .swiftPackageManager(), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .inSchemaModule),
      .mock(moduleType: .other, operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .other, operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .other, operations: .inSchemaModule),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .inSchemaModule)
    ]

    for test in tests {
      // when
      try await buildSubjectAndOperation(configOutput: test)
      let allAnimals = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?.selectionSet
      )

      let actual = subject.test_render(childEntity: allAnimals.computed)

      // then
      expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
    }
  }

  func test__render_selections__givenCustomScalar_ID_rendersFieldSelectionWithoutSuffix() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      id: ID!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        id
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", TestSchema.ID.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithUppercasedName_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      FieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        FieldName
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("FieldName", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithAlias_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        aliased: string
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", alias: "aliased", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenEntityFieldWithNameNotMatchingType_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      predator: Animal!
      lowercaseType: lowercaseType!
      species: String!
    }

    type lowercaseType {
      a: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        lowercaseType {
          a
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("predator", Predator.self),
        .field("lowercaseType", LowercaseType.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Selections - Fields - Reserved Keywords & Special Names

  func test__render_selections__givenFieldsWithSwiftReservedKeywordNames_rendersFieldsNotBacktickEscaped() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      associatedtype: String!
      class: String!
      deinit: String!
      enum: String!
      extension: String!
      fileprivate: String!
      func: String!
      import: String!
      init: String!
      inout: String!
      internal: String!
      let: String!
      operator: String!
      private: String!
      precedencegroup: String!
      protocol: String!
      Protocol: String!
      public: String!
      rethrows: String!
      static: String!
      struct: String!
      subscript: String!
      typealias: String!
      var: String!
      break: String!
      case: String!
      catch: String!
      continue: String!
      default: String!
      defer: String!
      do: String!
      else: String!
      fallthrough: String!
      for: String!
      guard: String!
      if: String!
      in: String!
      repeat: String!
      return: String!
      throw: String!
      switch: String!
      where: String!
      while: String!
      as: String!
      false: String!
      is: String!
      nil: String!
      self: String!
      Self: String!
      super: String!
      throws: String!
      true: String!
      try: String!
      _: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        associatedtype
        class
        deinit
        enum
        extension
        fileprivate
        func
        import
        init
        inout
        internal
        let
        operator
        private
        precedencegroup
        protocol
        Protocol
        public
        rethrows
        static
        struct
        subscript
        typealias
        var
        break
        case
        catch
        continue
        default
        defer
        do
        else
        fallthrough
        for
        guard
        if
        in
        repeat
        return
        throw
        switch
        where
        while
        as
        false
        is
        nil
        self
        Self
        super
        throws
        true
        try
        _
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("associatedtype", String.self),
        .field("class", String.self),
        .field("deinit", String.self),
        .field("enum", String.self),
        .field("extension", String.self),
        .field("fileprivate", String.self),
        .field("func", String.self),
        .field("import", String.self),
        .field("init", String.self),
        .field("inout", String.self),
        .field("internal", String.self),
        .field("let", String.self),
        .field("operator", String.self),
        .field("private", String.self),
        .field("precedencegroup", String.self),
        .field("protocol", String.self),
        .field("Protocol", String.self),
        .field("public", String.self),
        .field("rethrows", String.self),
        .field("static", String.self),
        .field("struct", String.self),
        .field("subscript", String.self),
        .field("typealias", String.self),
        .field("var", String.self),
        .field("break", String.self),
        .field("case", String.self),
        .field("catch", String.self),
        .field("continue", String.self),
        .field("default", String.self),
        .field("defer", String.self),
        .field("do", String.self),
        .field("else", String.self),
        .field("fallthrough", String.self),
        .field("for", String.self),
        .field("guard", String.self),
        .field("if", String.self),
        .field("in", String.self),
        .field("repeat", String.self),
        .field("return", String.self),
        .field("throw", String.self),
        .field("switch", String.self),
        .field("where", String.self),
        .field("while", String.self),
        .field("as", String.self),
        .field("false", String.self),
        .field("is", String.self),
        .field("nil", String.self),
        .field("self", String.self),
        .field("Self", String.self),
        .field("super", String.self),
        .field("throws", String.self),
        .field("true", String.self),
        .field("try", String.self),
        .field("_", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenEntityFieldWithUnderscorePrefixedName_rendersFieldSelectionsWithTypeFirstUppercased() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      _oneUnderscore: Animal!
      __twoUnderscore: Animal!
      species: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        _oneUnderscore {
          species
        }
        __twoUnderscore {
          species
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("_oneUnderscore", _OneUnderscore.self),
        .field("__twoUnderscore", __TwoUnderscore.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenEntityFieldWithSwiftKeywordAndApolloReservedTypeNames_rendersFieldSelectionsWithTypeNameSuffixed() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      self: Animal!
      parentType: Animal!
      dataDict: Animal!
      documentType: Animal!
      selection: Animal!
      schema: Animal!
      fragmentContainer: Animal!
      string: Animal!
      bool: Animal!
      int: Animal!
      float: Animal!
      double: Animal!
      iD: Animal!
      any: Animal!
      protocol: Animal!
      type: Animal!
      species: String!
      _: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        self {
          species
        }
        parentType {
          species
        }
        dataDict {
          species
        }
        documentType {
          species
        }
        selection {
          species
        }
        schema {
          species
        }
        fragmentContainer {
          species
        }
        string {
          species
        }
        bool {
          species
        }
        int {
          species
        }
        float {
          species
        }
        double {
          species
        }
        iD {
          species
        }
        any {
          species
        }
        protocol {
          species
        }
        type {
          species
        }
        _ {
          species
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("self", Self_SelectionSet.self),
        .field("parentType", ParentType_SelectionSet.self),
        .field("dataDict", DataDict_SelectionSet.self),
        .field("documentType", DocumentType_SelectionSet.self),
        .field("selection", Selection_SelectionSet.self),
        .field("schema", Schema_SelectionSet.self),
        .field("fragmentContainer", FragmentContainer_SelectionSet.self),
        .field("string", String_SelectionSet.self),
        .field("bool", Bool_SelectionSet.self),
        .field("int", Int_SelectionSet.self),
        .field("float", Float_SelectionSet.self),
        .field("double", Double_SelectionSet.self),
        .field("iD", ID_SelectionSet.self),
        .field("any", Any_SelectionSet.self),
        .field("protocol", Protocol_SelectionSet.self),
        .field("type", Type_SelectionSet.self),
        .field("_", __SelectionSet.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Selections - Fields - Arguments

  func test__render_selections__givenFieldWithArgumentWithConstantValue_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string(variable: Int): String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        aliased: string(variable: 3)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", alias: "aliased", String.self, arguments: ["variable": 3]),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithArgumentWithNullConstantValue_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string(variable: Int): String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        aliased: string(variable: null)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", alias: "aliased", String.self, arguments: ["variable": .null]),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithArgumentWithVariableValue_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string(variable: Int): String!
    }
    """

    document = """
    query TestOperation($var: Int) {
      allAnimals {
        aliased: string(variable: $var)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", alias: "aliased", String.self, arguments: ["variable": .variable("var")]),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithArgumentOfInputObjectTypeWithNullableFields_withConstantValues_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string(input: TestInput): String!
    }

    input TestInput {
      string: String
      int: Int
      float: Float
      bool: Boolean
      list: [String]
      enum: TestEnum
      innerInput: InnerInput
    }

    input InnerInput {
      string: String
      enumList: [TestEnum]
    }

    enum TestEnum {
      CaseOne
      CaseTwo
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        aliased: string(input: {
          string: "ABCD",
          int: 3,
          float: 123.456,
          bool: true,
          list: ["A", "B"],
          enum: CaseOne,
          innerInput: {
            string: "EFGH",
            enumList: [CaseOne, CaseTwo]
          }
        })
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("string", alias: "aliased", String.self, arguments: ["input": [
          "string": "ABCD",
          "int": 3,
          "float": 123.456,
          "bool": true,
          "list": ["A", "B"],
          "enum": "CaseOne",
          "innerInput": [
            "string": "EFGH",
            "enumList": ["CaseOne", "CaseTwo"]
          ]
        ]]),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Selections - Type Cases

  func test__render_selections__givenTypeCases_rendersTypeCaseSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
    }

    interface Pet {
      int: Int!
    }

    interface lowercaseInterface {
      int: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          int
        }
        ... on lowercaseInterface {
          int
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .inlineFragment(AsPet.self),
        .inlineFragment(AsLowercaseInterface.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // Related to https://github.com/apollographql/apollo-ios/issues/3326
  func test__render_selections__givenTypeCaseWithOnlyReservedField_doesNotRenderSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal]
    }

    union Animal = AnimalObject | AnimalError

    type AnimalObject {
      species: String!
    }

    type AnimalError {
      code: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on AnimalObject {
          __typename
        }
      }
    }
    """

    let expected = """
    public struct AsAnimalObject: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.AnimalObject }
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asAnimalObject = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "AnimalObject"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asAnimalObject.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  // MARK: Selections - Fragments

  func test__render_selections__givenFragments_rendersFragmentSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...FragmentA
        ...lowercaseFragment
      }
    }

    fragment FragmentA on Animal {
      int
    }

    fragment lowercaseFragment on Animal {
      string
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(FragmentA.self),
        .fragment(LowercaseFragment.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Selections - Deferred Inline Fragment

  func test__render_selections__givenDeferredInlineFragmentWithoutTypeCase_rendersDeferredSelection() async throws {
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
        ... @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_deferredAsRoot = try XCTUnwrap(allAnimals[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_deferredAsRoot = subject.test_render(inlineFragment: allAnimals_deferredAsRoot.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }

  func test__render_selections__givenDeferredInlineFragmentOnSameTypeCase_rendersDeferredSelection() async throws {
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
        ... on Animal @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_deferredAsRoot = try XCTUnwrap(allAnimals[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_deferredAsRoot = subject.test_render(inlineFragment: allAnimals_deferredAsRoot.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }

  func test__render_selections__givenDeferredInlineFragmentOnDifferentTypeCase_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredInlineFragmentWithVariableCondition_rendersDeferredSelectionWithVariable() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: "a", label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root", variable: "a")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(if: "a", Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredInlineFragmentWithTrueCondition_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: true, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredInlineFragmentWithFalseCondition_doesNotRenderDeferredSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: false, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(allAnimals_asDog.containsDeferredChildFragment).to(beFalse())
  }
  
  func test__render_selections__givenSiblingDeferredInlineFragmentOnSameTypeCase_rendersDeferredSelections() async throws {
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

    type Dog implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Dog @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asDog_deferredAsTwo = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "two")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asDog_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsTwo.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(One.self, label: "one"),
          .deferred(Two.self, label: "two"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsTwo).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenSiblingDeferredInlineFragmentOnDifferentTypeCase_rendersDeferredSelections() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Cat @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asCat = try XCTUnwrap(allAnimals[as: "Cat"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asCat_deferredAsTwo = try XCTUnwrap(allAnimals_asCat[deferred: .init(label: "two")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asCat = subject.test_render(inlineFragment: allAnimals_asCat.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asCat_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asCat_deferredAsTwo.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
          .inlineFragment(AsCat.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(One.self, label: "one"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Two.self, label: "two"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat_deferredAsTwo).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenNonDeferredSiblingOnSameTypeCase_doesNotMergeSiblings_rendersDeferredSelection() async throws {
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

    type Dog implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Dog {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
          .deferred(One.self, label: "one"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenNonDeferredSiblingOnDifferentTypeCase_rendersDeferredSelection() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Cat {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asCat = try XCTUnwrap(allAnimals[as: "Cat"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asCat = subject.test_render(inlineFragment: allAnimals_asCat.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
          .inlineFragment(AsCat.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(One.self, label: "one"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenNestedDeferredInlineFragmentsOnSameTypeCase_doesNotMergeDeferredFragments() async throws {
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

    type Dog implements Animal {
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
          ... on Dog @defer(label: "inner") {
            genus
          }
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOuter = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "outer")])
    let allAnimals_asDog_deferredAsOuter_deferredAsInner = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter[deferred: .init(label: "inner")]
    )

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOuter = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_deferredAsInner = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter_deferredAsInner.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Outer.self, label: "outer"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
          .deferred(Inner.self, label: "inner"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_deferredAsInner).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenNestedDeferredInlineFragmentsOnDifferentTypeCase_rendersNestedDeferredFragments() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
      friend: Animal!
    }
    
    type Cat implements Animal {
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

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOuter = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "outer")])
    let allAnimals_asDog_deferredAsOuter_friend = try XCTUnwrap(allAnimals_asDog_deferredAsOuter[field: "friend"])
    let allAnimals_asDog_deferredAsOuter_friend_asCat = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter_friend[as: "Cat"]
    )
    let allAnimals_asDog_deferredAsOuter_friend_asCat_deferredAsInner = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter_friend_asCat[deferred: .init(label: "inner")]
    )

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOuter = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_friend = subject.test_render(
      childEntity: allAnimals_asDog_deferredAsOuter_friend.selectionSet!.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_friend_asCat = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter_friend_asCat.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_friend_asCat_deferredAsInner = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter_friend_asCat_deferredAsInner.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Outer.self, label: "outer"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
          .field("friend", Friend.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_friend).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .inlineFragment(AsCat.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_friend_asCat).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Inner.self, label: "inner"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_friend_asCat_deferredAsInner).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  // MARK: Selections - Deferred Inline Fragment (with @include/@skip)

  func test__render_selections__givenBothDeferAndIncludeDirectives_onSameTypeCase_rendersDeferredFragment() async throws {
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
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @include(if: $a) @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_ifA = try XCTUnwrap(allAnimals[if: "a"])
    let allAnimals_ifA_deferredAsRoot = try XCTUnwrap(allAnimals_ifA[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_ifA = subject.test_render(inlineFragment: allAnimals_ifA.computed)
    let rendered_allAnimals_ifA_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_ifA_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_ifA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_ifA_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenBothDeferAndIncludeDirectives_directivesOrderShouldNotAffectGeneratedFragments_rendersDeferredFragmentWithinConditional() async throws {
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
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @defer(label: "root") @include(if: $a) {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_ifA = try XCTUnwrap(allAnimals[if: "a"])
    let allAnimals_ifA_deferredAsRoot = try XCTUnwrap(allAnimals_ifA[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_ifA = subject.test_render(inlineFragment: allAnimals_ifA.computed)
    let rendered_allAnimals_ifA_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_ifA_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_ifA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_ifA_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenBothDeferAndIncludeDirectives_onDifferentTypeCases_rendersDeferredSelections() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @include(if: $a) {
          species
        }
        ... on Dog @defer(label: "root") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_ifA = try XCTUnwrap(allAnimals[if: "a"])
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_ifA = subject.test_render(inlineFragment: allAnimals_ifA.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
          .include(if: "a", .inlineFragment(IfA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_ifA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenBothDeferAndSkipDirectives_onSameTypeCase_rendersDeferredSelections() async throws {
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
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @skip(if: $a) @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_skipIfA = try XCTUnwrap(allAnimals[if: !"a"])
    let allAnimals_skipIfA_deferredAsRoot = try XCTUnwrap(allAnimals_skipIfA[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_skipIfA = subject.test_render(inlineFragment: allAnimals_skipIfA.computed)
    let rendered_allAnimals_skipIfA_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_skipIfA_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .include(if: !"a", .inlineFragment(IfNotA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_skipIfA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_skipIfA_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenBothDeferAndSkipDirectives_directivesOrderShouldNotAffectGeneratedFragments_rendersDeferredSelections() async throws {
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
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @defer(label: "root") @skip(if: $a) {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_skipIfA = try XCTUnwrap(allAnimals[if: !"a"])
    let allAnimals_skipIfA_deferredAsRoot = try XCTUnwrap(allAnimals_skipIfA[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_skipIfA = subject.test_render(inlineFragment: allAnimals_skipIfA.computed)
    let rendered_allAnimals_skipIfA_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_skipIfA_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .include(if: !"a", .inlineFragment(IfNotA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_skipIfA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_skipIfA_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenBothDeferAndSkipDirectives_onDifferentTypeCases_rendersDeferredSelections() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @skip(if: $a) {
          species
        }
        ... on Dog @defer(label: "root") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_skipIfA = try XCTUnwrap(allAnimals[if: !"a"])
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_skipIfA = subject.test_render(inlineFragment: allAnimals_skipIfA.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
          .include(if: !"a", .inlineFragment(IfNotA.self)),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_skipIfA).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("genus", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }

  // MARK: Selections - Deferred Named Fragment

  func test__render_selections__givenDeferredNamedFragmentOnSameTypeCase_rendersDeferredSelection() async throws {
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
          ...AnimalFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_animalFragment = try XCTUnwrap(allAnimals[fragment: "AnimalFragment"])
    
    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    
    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .deferred(AnimalFragment.self, label: "root"),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }

  func test__render_selections__givenDeferredNamedFragmentOnDifferentTypeCase_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    
    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(AnimalFragment.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredNamedFragmentWithVariableCondition_rendersDeferredSelectionWithVariable() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(if: "a", label: "root")
        }
      }

      fragment AnimalFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    
    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(if: "a", AnimalFragment.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredNamedFragmentWithTrueCondition_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(if: true, label: "root")
        }
      }

      fragment AnimalFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    
    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(AnimalFragment.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredNamedFragmentWithFalseCondition_doesNotRenderDeferredSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment @defer(if: false, label: "root")
        }
      }

      fragment AnimalFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    
    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .fragment(AnimalFragment.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredInlineFragment_insideNamedFragment_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment
        }
      }

      fragment AnimalFragment on Dog {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])
    let allAnimals_asDog_animalFragment_deferredAsRoot = try XCTUnwrap(
      allAnimals_asDog_animalFragment.rootField[deferred: .init(label: "root")]
    )

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )
    let rendered_allAnimals_asDog_animalFragment_deferredAsRoot = fragmentSubject.test_render(
      childEntity: allAnimals_asDog_animalFragment_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .inlineFragment(AsDog.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .fragment(AnimalFragment.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_rendersDeferredFragmentSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment
        }
      }

      fragment AnimalFragment on Animal {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_animalFragment = try XCTUnwrap(allAnimals[fragment: "AnimalFragment"])
    let allAnimals_animalFragment_asDog = try XCTUnwrap(allAnimals_animalFragment.rootField[as: "Dog"])
    let allAnimals_animalFragment_asDog_deferredAsRoot = try XCTUnwrap(
      allAnimals_animalFragment_asDog[deferred: .init(label: "root")]
    )

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)

    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_animalFragment_asDog = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_animalFragment_asDog.computed)
    )
    let rendered_allAnimals_animalFragment_asDog_deferredAsRoot = fragmentSubject.test_render(
      childEntity: allAnimals_animalFragment_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .fragment(AnimalFragment.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_animalFragment_asDog).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .deferred(Root.self, label: "root"),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_animalFragment_asDog_deferredAsRoot).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("species", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_selections__givenDeferredNamedFragmentWithMatchingSiblingTypeCase_rendersDeferredSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Pet implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          ...AnimalFragment @defer(label: "root")
          ... on Pet {
            id
          }
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asPet = try XCTUnwrap(allAnimals[as: "Pet"])
    let allAnimals_animalFragment = try XCTUnwrap(allAnimals[fragment: "AnimalFragment"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)
    let rendered_allAnimals_asPet = subject.test_render(childEntity: allAnimals_asPet.computed)

    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .inlineFragment(AsPet.self),
          .deferred(AnimalFragment.self, label: "root"),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_asPet).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("id", String.self),
        ] }
      """,
      atLine: 8,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_animalFragment).to(equalLineByLine(
      """
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }
      """,
      atLine: 7,
      ignoringExtraLines: true
    ))
  }

  // MARK: Selections - Include/Skip

  func test__render_selections__givenFieldWithIncludeCondition_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        fieldName @include(if: $a)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: "a", .field("fieldName", String.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithSkipCondition_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($b: Boolean!) {
      allAnimals {
        fieldName @skip(if: $b)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: !"b", .field("fieldName", String.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFieldWithMultipleConditions_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($b: Boolean!) {
      allAnimals {
        fieldName @skip(if: $b) @include(if: $a)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: !"b" && "a", .field("fieldName", String.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenMergedFieldsWithMultipleConditions_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($b: Boolean!) {
      allAnimals {
        fieldName @skip(if: $b) @include(if: $a)
        fieldName @skip(if: $c)
        fieldName @include(if: $d) @skip(if: $e)
        fieldName @include(if: $f)
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: (!"b" && "a") || !"c" || ("d" && !"e") || "f", .field("fieldName", String.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenMultipleSelectionsWithSameIncludeConditions_rendersFieldSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
      fieldB: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        fieldA @include(if: $a)
        fieldB @include(if: $a)
        ... on Pet @include(if: $a) {
          fieldA
        }
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Animal {
      fieldA
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: "a", [
          .field("fieldA", String.self),
          .field("fieldB", String.self),
          .inlineFragment(AsPetIfA.self),
          .inlineFragment(IfA.self),
        ]),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFragmentWithNonMatchingTypeAndInclusionCondition_rendersTypeCaseSelectionWithInclusionCondition() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }

    type Pet {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Pet {
      int
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: "a", .inlineFragment(AsPetIfA.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenInlineFragmentOnSameTypeWithConditions_rendersInlineFragmentSelectionSetAccessorWithCorrectName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Animal @include(if: $a) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .include(if: "a", .inlineFragment(IfA.self)),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenFragmentWithInclusionConditionThatMatchesScope_rendersFragmentSelectionWithoutInclusionCondition() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }

    type Pet {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Pet {
      int
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .fragment(FragmentA.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet", if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  // MARK: Selections - __typename Selection

  func test__render_selections__givenEntityRootSelectionSet_rendersTypenameSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        fieldName
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("fieldName", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenInlineFragment_doesNotRenderTypenameSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }

    interface Pet {
      fieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          fieldName
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("fieldName", String.self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  func test__render_selections__givenOperationRootSelectionSet_doesNotRenderTypenameSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]!
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        fieldName
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("allAnimals", [AllAnimal].self),
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let queryRoot = try XCTUnwrap(
      operation[field: "query"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: queryRoot.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: Merged Sources

  func test__render_mergedSources__givenMergedTypeCasesFromSingleMergedTypeCaseSource_rendersMergedSources() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        predator {
          ... on Pet {
            name
          }
        }
        ... on Dog {
          name
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.AllAnimal.Predator.AsPet.self,
        TestOperationQuery.Data.AllAnimal.AsDog.Predator.self
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog_predator_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  func test__render_mergedSources__givenTypeCaseMergedFromFragmentWithOtherMergedFields_rendersMergedSources() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
          species
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let expected = """
      public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.AllAnimal.Predator.self,
        PredatorDetails.AsPet.self
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let predator_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predator_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  /// Test for edge case in [#2949](https://github.com/apollographql/apollo-ios/issues/2949)
  ///
  /// When the `MergedSource` would have duplicate naming, due to child fields with the same name
  /// (or alias), the fully qualified name must be used. In this example, a `MergedSource` of
  /// `Predator.Predator` the first usage of the name `Predator` would be referencing the nearest
  /// enclosing type (ie. `TestOperationQuery.Predator.Predator`), so it is looking for another
  /// `Predator` type in that scope, which does not exist
  /// (ie. `TestOperationQuery.Predator.Predator.Predator`).
  ///
  /// To correct this we must always use the fully qualified name including the operation name and
  /// `Data` objects to ensure we are referring to the correct type.
  func test__render_mergedSources__givenMergedTypeCaseWithConflictingNames_rendersMergedSourceWithFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      predators: [Animal!]!
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      predators {
        species
        predator {
          ... on Pet {
            name
          }
        }
        ... on Dog {
          name
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.Predator.Predator.AsPet.self,
        TestOperationQuery.Data.Predator.AsDog.Predator.self
      ] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "predators"]?[as: "Dog"]?[field: "predator"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog_predator_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  // MARK: - Field Accessors - Scalar

  func test__render_fieldAccessors__givenScalarFields_rendersAllFieldAccessors() async throws {
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
      public var string: String { __data["string"] }
      public var string_optional: String? { __data["string_optional"] }
      public var int: Int { __data["int"] }
      public var int_optional: Int? { __data["int_optional"] }
      public var float: Double { __data["float"] }
      public var float_optional: Double? { __data["float_optional"] }
      public var boolean: Bool { __data["boolean"] }
      public var boolean_optional: Bool? { __data["boolean_optional"] }
      public var custom: TestSchema.Custom { __data["custom"] }
      public var custom_optional: TestSchema.Custom? { __data["custom_optional"] }
      public var custom_required_list: [TestSchema.Custom] { __data["custom_required_list"] }
      public var custom_optional_list: [TestSchema.Custom]? { __data["custom_optional_list"] }
      public var list_required_required: [String] { __data["list_required_required"] }
      public var list_optional_required: [String]? { __data["list_optional_required"] }
      public var list_required_optional: [String?] { __data["list_required_optional"] }
      public var list_optional_optional: [String?]? { __data["list_optional_optional"] }
      public var nestedList_required_required_required: [[String]] { __data["nestedList_required_required_required"] }
      public var nestedList_required_required_optional: [[String?]] { __data["nestedList_required_required_optional"] }
      public var nestedList_required_optional_optional: [[String?]?] { __data["nestedList_required_optional_optional"] }
      public var nestedList_required_optional_required: [[String]?] { __data["nestedList_required_optional_required"] }
      public var nestedList_optional_required_required: [[String]]? { __data["nestedList_optional_required_required"] }
      public var nestedList_optional_required_optional: [[String?]]? { __data["nestedList_optional_required_optional"] }
      public var nestedList_optional_optional_required: [[String]?]? { __data["nestedList_optional_optional_required"] }
      public var nestedList_optional_optional_optional: [[String?]?]? { __data["nestedList_optional_optional_optional"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 35, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenCustomScalarFields_rendersFieldAccessorsWithNamespaceWhenRequiredInAllConfigurations() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      custom: Custom!
      custom_optional: Custom
      custom_required_list: [Custom!]!
      custom_optional_list: [Custom!]
      lowercaseScalar: lowercaseScalar!
    }

    scalar Custom
    scalar lowercaseScalar
    """

    document = """
    query TestOperation {
      allAnimals {
        custom
        custom_optional
        custom_required_list
        custom_optional_list
        lowercaseScalar
      }
    }
    """

    let expected = """
      public var custom: TestSchema.Custom { __data["custom"] }
      public var custom_optional: TestSchema.Custom? { __data["custom_optional"] }
      public var custom_required_list: [TestSchema.Custom] { __data["custom_required_list"] }
      public var custom_optional_list: [TestSchema.Custom]? { __data["custom_optional_list"] }
      public var lowercaseScalar: TestSchema.LowercaseScalar { __data["lowercaseScalar"] }
    """

    let tests: [ApolloCodegenConfiguration.FileOutput] = [
      .mock(moduleType: .swiftPackageManager(), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .inSchemaModule),
      .mock(moduleType: .other, operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .other, operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .other, operations: .inSchemaModule),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .inSchemaModule)
    ]

    for test in tests {
      // when
      try await buildSubjectAndOperation(configOutput: test)
      let allAnimals = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?.selectionSet
      )

      let actual = subject.test_render(childEntity: allAnimals.computed)

      // then
      expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
    }
  }

  func test__render_fieldAccessors__givenEnumField_rendersFieldAccessorsWithNamespacedInAllConfigurations() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      testEnum: TestEnum!
      testEnumOptional: TestEnumOptional
      lowercaseEnum: lowercaseEnum!
    }

    enum TestEnum {
      CASE_ONE
    }

    enum TestEnumOptional {
      CASE_ONE
    }

    enum lowercaseEnum {
      CASE_ONE
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        testEnum
        testEnumOptional
        lowercaseEnum
      }
    }
    """

    let expected = """
      public var testEnum: GraphQLEnum<TestSchema.TestEnum> { __data["testEnum"] }
      public var testEnumOptional: GraphQLEnum<TestSchema.TestEnumOptional>? { __data["testEnumOptional"] }
      public var lowercaseEnum: GraphQLEnum<TestSchema.LowercaseEnum> { __data["lowercaseEnum"] }
    """

    let tests: [ApolloCodegenConfiguration.FileOutput] = [
      .mock(moduleType: .swiftPackageManager(), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .swiftPackageManager(), operations: .inSchemaModule),
      .mock(moduleType: .other, operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .other, operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .other, operations: .inSchemaModule),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .relative(subpath: nil, accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget"), operations: .absolute(path: "custom", accessModifier: .public)),
      .mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .inSchemaModule)
    ]

    for test in tests {
      // when
      try await buildSubjectAndOperation(configOutput: test)
      let allAnimals = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?.selectionSet
      )

      let actual = subject.test_render(childEntity: allAnimals.computed)

      // then
      expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
    }
  }

  func test__render_fieldAccessors__givenCustomScalar_ID_rendersFieldAccessorWithTypeNameWithoutSuffix() async throws {
    // given
    schemaSDL = """
    type Query {
      AllAnimals: [Animal!]
    }

    type Animal {
      id: ID!
    }
    """

    document = """
    query TestOperation {
      AllAnimals {
        id
      }
    }
    """

    let expected = """
      public var id: TestSchema.ID { __data["id"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "AllAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldWithUpperCaseName_rendersFieldAccessorWithLowercaseName() async throws {
    // given
    schemaSDL = """
    type Query {
      AllAnimals: [Animal!]
    }

    type Animal {
      FieldName: String!
    }

    scalar Custom
    """

    document = """
    query TestOperation {
      AllAnimals {
        FieldName
      }
    }
    """

    let expected = """
      public var fieldName: String { __data["FieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "AllAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldWithAllUpperCaseName_rendersFieldAccessorWithLowercaseName() async throws {
    // given
    schemaSDL = """
    type Query {
      AllAnimals: [Animal!]
    }

    type Animal {
      FIELDNAME: String!
    }
    """

    document = """
    query TestOperation {
      AllAnimals {
        FIELDNAME
      }
    }
    """

    let expected = """
      public var fieldname: String { __data["FIELDNAME"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "AllAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldWithAlias_rendersAllFieldAccessors() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
    }

    scalar Custom
    """

    document = """
    query TestOperation {
      allAnimals {
        aliasedFieldName: string
      }
    }
    """

    let expected = """
      public var aliasedFieldName: String { __data["aliasedFieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenMergedScalarField_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      a: String!
    }

    type Dog {
      b: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        a
        ... on Dog {
          b
        }
      }
    }
    """

    let expected = """
      public var b: String { __data["b"] }
      public var a: String { __data["a"] }
    """

    // when
    try await buildSubjectAndOperation()
    let dog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: dog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldWithSnakeCaseName_rendersFieldAccessorAsCamelCase() async throws {
    // given
    schemaSDL = """
    type Query {
      AllAnimals: [Animal!]
    }

    type Animal {
      field_name: String!
    }
    """

    document = """
    query TestOperation {
      AllAnimals {
        field_name
      }
    }
    """

    let expected = """
      public var fieldName: String { __data["field_name"] }
    """

    // when
    try await buildSubjectAndOperation(conversionStrategies: .init(fieldAccessors: .camelCase))
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "AllAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldWithSnakeCaseUppercaseName_rendersFieldAccessorAsCamelCase() async throws {
    // given
    schemaSDL = """
    type Query {
      AllAnimals: [Animal!]
    }

    type Animal {
      FIELD_NAME: String!
    }
    """

    document = """
    query TestOperation {
      AllAnimals {
        FIELD_NAME
      }
    }
    """

    let expected = """
      public var fieldName: String { __data["FIELD_NAME"] }
    """

    // when
    try await buildSubjectAndOperation(conversionStrategies: .init(fieldAccessors: .camelCase))
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "AllAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  // MARK: Field Accessors - Reserved Keywords + Special Names

  func test__render_fieldAccessors__givenFieldsWithSwiftReservedKeywordNames_rendersFieldsBacktickEscaped() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      associatedtype: String!
      class: String!
      deinit: String!
      enum: String!
      extension: String!
      fileprivate: String!
      func: String!
      import: String!
      init: String!
      inout: String!
      internal: String!
      let: String!
      operator: String!
      private: String!
      precedencegroup: String!
      protocol: String!
      Protocol: String!
      public: String!
      rethrows: String!
      static: String!
      struct: String!
      subscript: String!
      typealias: String!
      var: String!
      break: String!
      case: String!
      catch: String!
      continue: String!
      default: String!
      defer: String!
      do: String!
      else: String!
      fallthrough: String!
      for: String!
      guard: String!
      if: String!
      in: String!
      repeat: String!
      return: String!
      throw: String!
      switch: String!
      where: String!
      while: String!
      as: String!
      false: String!
      is: String!
      nil: String!
      self: String!
      Self: String!
      super: String!
      throws: String!
      true: String!
      try: String!
      _: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        associatedtype
        class
        deinit
        enum
        extension
        fileprivate
        func
        import
        init
        inout
        internal
        let
        operator
        private
        precedencegroup
        protocol
        Protocol
        public
        rethrows
        static
        struct
        subscript
        typealias
        var
        break
        case
        catch
        continue
        default
        defer
        do
        else
        fallthrough
        for
        guard
        if
        in
        repeat
        return
        throw
        switch
        where
        while
        as
        false
        is
        nil
        self
        Self
        super
        throws
        true
        try
      }
    }
    """

    let expected = """
      public var `associatedtype`: String { __data["associatedtype"] }
      public var `class`: String { __data["class"] }
      public var `deinit`: String { __data["deinit"] }
      public var `enum`: String { __data["enum"] }
      public var `extension`: String { __data["extension"] }
      public var `fileprivate`: String { __data["fileprivate"] }
      public var `func`: String { __data["func"] }
      public var `import`: String { __data["import"] }
      public var `init`: String { __data["init"] }
      public var `inout`: String { __data["inout"] }
      public var `internal`: String { __data["internal"] }
      public var `let`: String { __data["let"] }
      public var `operator`: String { __data["operator"] }
      public var `private`: String { __data["private"] }
      public var `precedencegroup`: String { __data["precedencegroup"] }
      public var `protocol`: String { __data["protocol"] }
      public var `protocol`: String { __data["Protocol"] }
      public var `public`: String { __data["public"] }
      public var `rethrows`: String { __data["rethrows"] }
      public var `static`: String { __data["static"] }
      public var `struct`: String { __data["struct"] }
      public var `subscript`: String { __data["subscript"] }
      public var `typealias`: String { __data["typealias"] }
      public var `var`: String { __data["var"] }
      public var `break`: String { __data["break"] }
      public var `case`: String { __data["case"] }
      public var `catch`: String { __data["catch"] }
      public var `continue`: String { __data["continue"] }
      public var `default`: String { __data["default"] }
      public var `defer`: String { __data["defer"] }
      public var `do`: String { __data["do"] }
      public var `else`: String { __data["else"] }
      public var `fallthrough`: String { __data["fallthrough"] }
      public var `for`: String { __data["for"] }
      public var `guard`: String { __data["guard"] }
      public var `if`: String { __data["if"] }
      public var `in`: String { __data["in"] }
      public var `repeat`: String { __data["repeat"] }
      public var `return`: String { __data["return"] }
      public var `throw`: String { __data["throw"] }
      public var `switch`: String { __data["switch"] }
      public var `where`: String { __data["where"] }
      public var `while`: String { __data["while"] }
      public var `as`: String { __data["as"] }
      public var `false`: String { __data["false"] }
      public var `is`: String { __data["is"] }
      public var `nil`: String { __data["nil"] }
      public var `self`: String { __data["self"] }
      public var `self`: String { __data["Self"] }
      public var `super`: String { __data["super"] }
      public var `throws`: String { __data["throws"] }
      public var `true`: String { __data["true"] }
      public var `try`: String { __data["try"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 11 + allAnimals.selections!.fields.count,
      ignoringExtraLines: true)
    )
  }

  func test__render_fieldAccessors__givenEntityFieldWithUnderscorePrefixedName_rendersFieldWithTypeFirstUppercased() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      _oneUnderscore: Animal!
      __twoUnderscore: Animal!
      species: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        _oneUnderscore {
          species
        }
        __twoUnderscore {
          species
        }
      }
    }
    """

    let expected = """
      public var _oneUnderscore: _OneUnderscore { __data["_oneUnderscore"] }
      public var __twoUnderscore: __TwoUnderscore { __data["__twoUnderscore"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 11 + allAnimals.selections!.fields.count,
      ignoringExtraLines: true)
    )
  }

  func test__render_fieldAccessors__givenEntityFieldWithSwiftKeywordAndApolloReservedTypeNames_rendersFieldAccessorWithTypeNameSuffixed() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      self: Animal!
      parentType: Animal!
      dataDict: Animal!
      selection: Animal!
      schema: Animal!
      fragmentContainer: Animal!
      string: Animal!
      bool: Animal!
      int: Animal!
      float: Animal!
      double: Animal!
      iD: Animal!
      any: Animal!
      protocol: Animal!
      type: Animal!
      species: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        self {
          species
        }
        parentType {
          species
        }
        dataDict {
          species
        }
        selection {
          species
        }
        schema {
          species
        }
        fragmentContainer {
          species
        }
        string {
          species
        }
        bool {
          species
        }
        int {
          species
        }
        float {
          species
        }
        double {
          species
        }
        iD {
          species
        }
        any {
          species
        }
        protocol {
          species
        }
        type {
          species
        }
      }
    }
    """

    let expected = """
      public var `self`: Self_SelectionSet { __data["self"] }
      public var parentType: ParentType_SelectionSet { __data["parentType"] }
      public var dataDict: DataDict_SelectionSet { __data["dataDict"] }
      public var selection: Selection_SelectionSet { __data["selection"] }
      public var schema: Schema_SelectionSet { __data["schema"] }
      public var fragmentContainer: FragmentContainer_SelectionSet { __data["fragmentContainer"] }
      public var string: String_SelectionSet { __data["string"] }
      public var bool: Bool_SelectionSet { __data["bool"] }
      public var int: Int_SelectionSet { __data["int"] }
      public var float: Float_SelectionSet { __data["float"] }
      public var double: Double_SelectionSet { __data["double"] }
      public var iD: ID_SelectionSet { __data["iD"] }
      public var any: Any_SelectionSet { __data["any"] }
      public var `protocol`: Protocol_SelectionSet { __data["protocol"] }
      public var type: Type_SelectionSet { __data["type"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 11 + allAnimals.selections!.fields.count,
      ignoringExtraLines: true)
    )
  }

  // MARK: Field Accessors - Entity

  func test__render_fieldAccessors__givenDirectEntityField_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      lowercaseType: lowercaseType!
    }

    type lowercaseType {
      a: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        lowercaseType {
          a
        }
      }
    }
    """

    let expected = """
      public var predator: Predator { __data["predator"] }
      public var lowercaseType: LowercaseType { __data["lowercaseType"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenDirectEntityFieldWithAlias_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        aliasedPredator: predator {
          species
        }
      }
    }
    """

    let expected = """
      public var aliasedPredator: AliasedPredator { __data["aliasedPredator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenDirectEntityFieldAsOptional_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
      }
    }
    """

    let expected = """
      public var predator: Predator? { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenDirectEntityFieldAsList_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predators {
          species
        }
      }
    }
    """

    let expected = """
      public var predators: [Predator]? { __data["predators"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldWithDirectSelectionsAndMergedFromFragment_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      name: String!
      predator: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        predator {
          name
        }
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
      }
    }
    """

    let expected = """
      public var predator: Predator { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: Field Accessors - Merged Fragment

  func test__render_fieldAccessors__givenEntityFieldMergedFromFragment_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
      }
    }
    """

    let expected = """
      public var predator: Predator { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromFragmentEntityNestedInEntity_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        height {
          feet
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromFragmentInTypeCaseWithEntityNestedInEntity_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet {
      predator: Animal!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Pet {
      predator {
        height {
          feet
        }
      }
    }
    """

    let expected = """
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asPet_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asPet_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromTypeCaseInFragment_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet {
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
          ...PredatorDetails
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        height {
          feet
        }
      }
    }
    """

    let predator_expected = """
      public var species: String { __data["species"] }

    """

    let predator_asPet_expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let allAnimals_predator_asPet = try XCTUnwrap(allAnimals_predator[as: "Pet"])

    let allAnimals_predator_actual = subject.test_render(childEntity: allAnimals_predator.computed)
    let allAnimals_predator_asPet_actual = subject.test_render(
      inlineFragment: allAnimals_predator_asPet.computed
    )

    // then
    expect(allAnimals_predator_actual).to(equalLineByLine(predator_expected, atLine: 13, ignoringExtraLines: true))
    expect(allAnimals_predator_asPet_actual).to(equalLineByLine(predator_asPet_expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromFragmentWithEntityNestedInEntityTypeCase_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet {
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        ... on Pet {
          height {
            feet
          }
        }
      }
    }
    """

    let predator_expected = """
      public var species: String { __data["species"] }

    """

    let predator_asPet_expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let allAnimals_predator_asPet = try XCTUnwrap(allAnimals_predator[as: "Pet"])

    let allAnimals_predator_actual = subject.test_render(childEntity: allAnimals_predator.computed)
    let allAnimals_predator_asPet_actual = subject.test_render(
      inlineFragment: allAnimals_predator_asPet.computed
    )

    // then
    expect(allAnimals_predator_actual).to(equalLineByLine(predator_expected, atLine: 12, ignoringExtraLines: true))
    expect(allAnimals_predator_asPet_actual).to(equalLineByLine(predator_asPet_expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenTypeCaseMergedFromFragmentWithOtherMergedFields_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
          species
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let predator_expected = """
      public var asPet: AsPet? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let predator_actual = subject.test_render(childEntity: predator.computed)

    // then
    expect(predator_actual)
      .to(equalLineByLine(predator_expected, atLine: 15, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenTypeCaseMergedFromFragmentWithNoOtherMergedFields_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let predator_expected = """
      public var asPet: AsPet? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let predator_actual = subject.test_render(childEntity: predator.computed)

    // then
    expect(predator_actual)
      .to(equalLineByLine(predator_expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedAsRootOfNestedFragment_rendersFieldAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let predator_asPet_expected = """
      public var favoriteToy: FavoriteToy? { __data["favoriteToy"] }
    """

    // when
    try await buildSubjectAndOperation()
    let predator_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?[as: "Pet"]
    )

    let predator_asPet_actual = subject.test_render(inlineFragment: predator_asPet.computed)

    // then
    expect(predator_asPet_actual)
      .to(equalLineByLine(predator_asPet_expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: Field Accessors - Merged From Parent

  func test__render_fieldAccessors__givenEntityFieldMergedFromParent_notOperationRoot_rendersFieldAccessorWithNameNotIncludingParent() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    type Dog implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var predator: Predator { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromParent_atOperationRoot_rendersFieldAccessorWithFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type AdminQuery {
      name: String!
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
      ... on AdminQuery {
        name
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var allAnimals: [AllAnimal]? { __data["allAnimals"] }
    """

    // when
    try await buildSubjectAndOperation()
    let query_asAdminQuery = try XCTUnwrap(
      operation[field: "query"]?[as: "AdminQuery"]
    )

    let actual = subject.test_render(inlineFragment: query_asAdminQuery.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromSiblingTypeCase_notOperationRoot_rendersFieldAccessorWithNameNotIncludingSharedParent() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          predator {
            species
          }
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var predator: Predator { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldNestedInEntityFieldMergedFromParent_rendersFieldAccessorWithCorrectName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Dog implements Animal {
      name: String!
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          height {
            feet
          }
        }
        ... on Dog {
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldNestedInEntityFieldInMatchingTypeCaseMergedFromParent_rendersFieldAccessorWithCorrectName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Dog implements Animal & Pet {
      name: String!
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          predator {
            height {
              feet
            }
          }
        }
        ... on Dog {
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  // MARK: Field Accessors - Include/Skip

  func test__render_fieldAccessor__givenNonNullFieldWithIncludeCondition_rendersAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        fieldName @include(if: $a)
      }
    }
    """

    let expected = """
      public var fieldName: String? { __data["fieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessor__givenNonNullFieldWithSkipCondition_rendersAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        fieldName @skip(if: $a)
      }
    }
    """

    let expected = """
      public var fieldName: String? { __data["fieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromParentWithInclusionCondition_rendersFieldAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    type Dog implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        predator @include(if: $a) {
          species
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var predator: Predator? { __data["predator"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessor__givenNonNullFieldMergedFromParentWithIncludeConditionThatMatchesScope_rendersAsNotOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
      a: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        fieldName @include(if: $a)
        ... @include(if: $a) {
          a
        }
      }
    }
    """

    let expected = """
      public var a: String { __data["a"] }
      public var fieldName: String { __data["fieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_ifA = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_ifA.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessor__givenNonNullFieldWithIncludeConditionThatMatchesScope_rendersAsNotOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldName: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals @include(if: $a) {
        fieldName @include(if: $a)
      }
    }
    """

    let expected = """
      public var fieldName: String { __data["fieldName"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessor__givenNonNullFieldMergedFromNestedEntityInNamedFragmentWithIncludeCondition_doesNotRenderField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      child: Child!
    }

    type Child {
      a: String!
      b: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...ChildFragment @include(if: $a)
        child {
          a
        }
      }
    }

    fragment ChildFragment on Animal {
      child {
        b
      }
    }
    """

    let expected = """
      public var a: String { __data["a"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_child = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "child"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_child.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessor__givenNonNullFieldMergedFromNestedEntityInNamedFragmentWithIncludeCondition_inConditionalFragment_rendersFieldAsNonOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      child: Child!
    }

    type Child {
      a: String!
      b: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...ChildFragment @include(if: $a)
        child {
          a
        }
      }
    }

    fragment ChildFragment on Animal {
      child {
        b
      }
    }
    """

    let expected = """
      public var a: String { __data["a"] }
      public var b: String { __data["b"] }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_child = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]?[field: "child"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_child.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  // MARK: Field Accessors - Deferred Inline Fragment

  func test__render_fieldAccessor__givenDeferredInlineFragmentWithoutTypeCase_rendersDeferredField() async throws {
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
        ... @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_deferredAsRoot = try XCTUnwrap(allAnimals[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_deferredAsRoot = subject.test_render(inlineFragment: allAnimals_deferredAsRoot.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }

  func test__render_fieldAccessor__givenDeferredInlineFragmentOnSameTypeCase_rendersDeferredField() async throws {
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
        ... on Animal @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_deferredAsRoot = try XCTUnwrap(allAnimals[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_deferredAsRoot = subject.test_render(inlineFragment: allAnimals_deferredAsRoot.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }

  func test__render_fieldAccessor__givenDeferredInlineFragmentOnDifferentTypeCase_rendersDeferredField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenDeferredInlineFragmentWithVariableCondition_rendersDeferredField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: "a", label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(
      allAnimals_asDog[deferred: .init(label: "root", variable: "a")]
    )

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenDeferredInlineFragmentWithTrueCondition_rendersDeferredField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: true, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenDeferredInlineFragmentWithFalseCondition_doesNotRenderDeferredField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: false, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenSiblingDeferredInlineFragmentsOnSameTypeCase_doesNotMergeDeferredFields() async throws {
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

    type Dog implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Dog @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asDog_deferredAsTwo = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "two")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asDog_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsTwo.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsTwo).to(equalLineByLine(
      """

        public var genus: String { __data["genus"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenSiblingDeferredInlineFragmentsOnDifferentTypeCase_doesNotMergeDeferredFields() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Cat @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asCat = try XCTUnwrap(allAnimals[as: "Cat"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asCat_deferredAsTwo = try XCTUnwrap(allAnimals_asCat[deferred: .init(label: "two")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asCat = subject.test_render(inlineFragment: allAnimals_asCat.computed)
    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asCat_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asCat_deferredAsTwo.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 13,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat_deferredAsTwo).to(equalLineByLine(
      """

        public var genus: String { __data["genus"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenDeferredInlineFragmentWithSiblingOnSameTypeCase_doesNotMergeDeferredFields() async throws {
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

    type Dog implements Animal {
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
        ... on Dog @defer(label: "root") {
          species
        }
        ... on Dog {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var genus: String { __data["genus"] }
        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
        public var genus: String { __data["genus"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenDeferredInlineFragmentWithSiblingOnDifferentTypeCase_doesNotMergeDeferredFields() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "root") {
          species
        }
        ... on Cat {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asCat = try XCTUnwrap(allAnimals[as: "Cat"])
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "root")])

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asCat = subject.test_render(inlineFragment: allAnimals_asCat.computed)
    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 13,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat).to(equalLineByLine(
      """

        public var genus: String { __data["genus"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var id: String { __data["id"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fieldAccessor__givenNestedDeferredInlineFragments_doesNotMergeDeferredFields() async throws {
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

    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
      friend: Animal!
    }
    
    type Cat implements Animal {
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

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_asDog = try XCTUnwrap(allAnimals[as: "Dog"])
    let allAnimals_asDog_deferredAsOuter = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "outer")])
    let allAnimals_asDog_deferredAsOuter_asCat = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter[field: "friend"]?[as: "Cat"]
    )
    let allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter_asCat[deferred: .init(label: "inner")]
    )

    let rendered_allAnimals = subject.test_render(inlineFragment: allAnimals.computed)
    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)
    let rendered_allAnimals_asDog_deferredAsOuter = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner.computed
    )

    // AllAnimal
    expect(rendered_allAnimals).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """

        public var id: String { __data["id"] }

      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter).to(equalLineByLine(
      """

        public var species: String { __data["species"] }
        public var friend: Friend { __data["friend"] }
        public var id: String { __data["id"] }

      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner).to(equalLineByLine(
      """

        public var genus: String { __data["genus"] }
      }
      """,
      atLine: 11,
      ignoringExtraLines: true
    ))
  }

  // MARK: - Inline Fragment Accessors

  func test__render_inlineFragmentAccessors__givenDirectTypeCases_rendersTypeCaseAccessorWithCorrectName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        ... on Pet {
          name
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var asPet: AsPet? { _asInlineFragment() }
      public var asDog: AsDog? { _asInlineFragment() }
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

  func test__render_inlineFragmentAccessors__givenMergedTypeCasesFromSingleMergedTypeCaseSource_rendersTypeCaseAccessorWithCorrectName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        predator {
          ... on Pet {
            name
          }
        }
        ... on Dog {
          name
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var asPet: AsPet? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  // MARK: Inline Fragment Accessors - Include/Skip

  func test__render_inlineFragmentAccessors__givenInlineFragmentOnDifferentTypeWithCondition_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Pet @include(if: $a) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public var asPetIfA: AsPetIfA? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_inlineFragmentAccessors__givenInlineFragmentOnDifferentTypeWithSkipCondition_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Pet @skip(if: $a) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public var asPetIfNotA: AsPetIfNotA? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_inlineFragmentAccessors__givenInlineFragmentOnDifferentTypeWithMultipleConditions_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Pet @include(if: $a) @skip(if: $b) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public var asPetIfAAndNotB: AsPetIfAAndNotB? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_inlineFragmentAccessors__givenInlineFragmentOnSameTypeWithMultipleConditions_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Animal @include(if: $a) @skip(if: $b) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public var ifAAndNotB: IfAAndNotB? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_inlineFragmentAccessor__givenNamedFragmentMatchingParentTypeWithInclusionCondition_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Animal {
      int
    }
    """

    let expected = """
      public var ifA: IfA? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_inlineFragmentAccessor__givenInlineFragmentAndNamedFragmentOnSameTypeWithInclusionCondition_rendersBothInlineFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      string: String!
      int: Int!
    }

    type Bird implements Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... on Bird {
          string
        }
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Bird {
      int
    }
    """

    let expected = """
      public var asBird: AsBird? { _asInlineFragment() }
      public var asBirdIfA: AsBirdIfA? { _asInlineFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: - Fragment Accessors

  func test__render_fragmentAccessor__givenFragments_rendersFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...FragmentA
        ...lowercaseFragment
      }
    }

    fragment FragmentA on Animal {
      int
    }

    fragment lowercaseFragment on Animal {
      string
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var fragmentA: FragmentA { _toFragment() }
        public var lowercaseFragment: LowercaseFragment { _toFragment() }
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

  func test__render_fragmentAccessor__givenInheritedFragmentFromParent_rendersFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      string: String!
      int: Int!
    }

    type Cat implements Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...FragmentA
        ... on Cat {
          string
        }
      }
    }

    fragment FragmentA on Animal {
      int
    }

    fragment lowercaseFragment on Animal {
      string
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var fragmentA: FragmentA { _toFragment() }
      }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asCat = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asCat.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  // MARK: - Fragment Accessors - Include Skip

  func test__render_fragmentAccessor__givenFragmentOnSameTypeWithInclusionCondition_rendersFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
        ...lowercaseFragment
      }
    }

    fragment FragmentA on Animal {
      int
    }

    fragment lowercaseFragment on Animal {
      string
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var lowercaseFragment: LowercaseFragment { _toFragment() }
        public var fragmentA: FragmentA? { _toFragment() }
      }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessor__givenFragmentOnSameTypeWithInclusionConditionThatMatchesScope_rendersFragmentAccessorAsNotOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals @include(if: $a) {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Animal {
      int
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var fragmentA: FragmentA { _toFragment() }
      }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessor__givenFragmentOnSameTypeWithInclusionConditionThatPartiallyMatchesScope_rendersFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!, $b: Boolean!) {
      allAnimals @include(if: $a) {
        ...FragmentA @include(if: $a) @include(if: $b)
      }
    }

    fragment FragmentA on Animal {
      int
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var fragmentA: FragmentA? { _toFragment() }
      }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessor__givenFragmentMergedFromParent_withInclusionConditionThatMatchesScope_rendersFragmentAccessorAsNotOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Animal {
      int
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var fragmentA: FragmentA { _toFragment() }
      }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_ifA = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_ifA.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  // MARK: Fragment Accessors - Deferred Inline Fragment

  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithoutTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
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
        ... @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)

    let rendered = subject.test_render(childEntity: allAnimals.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }

  func test__render_fragmentAccessor__givenDeferredInlineFragmentOnSameTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
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
        ... on Animal @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)

    let rendered = subject.test_render(childEntity: allAnimals.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }

  func test__render_fragmentAccessor__givenDeferredInlineFragmentOnDifferentTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithVariableCondition_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: "a", label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithTrueCondition_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: true, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithFalseCondition_doesNotRenderDeferredFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(if: false, label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
      }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenSiblingDeferredInlineFragmentOnSameTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    
    type Dog implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Dog @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(childEntity: allAnimals_asDog.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _one = Deferred(_dataDict: _dataDict)
            _two = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var one: One?
          @Deferred public var two: Two?
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenSiblingDeferredInlineFragmentOnDifferentTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    
    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Cat @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asCat = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"])

    let rendered_allAnimals_asDog = subject.test_render(childEntity: allAnimals_asDog.computed)
    let rendered_allAnimals_asCat = subject.test_render(childEntity: allAnimals_asCat.computed)
    
    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _one = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var one: One?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _two = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var two: Two?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithSiblingOnSameTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    
    type Dog implements Animal {
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
        ... on Dog @defer(label: "root") {
          species
        }
        ... on Dog {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(childEntity: allAnimals_asDog.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 16,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentWithSiblingOnDifferentTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    
    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }
    
    type Cat implements Animal {
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
        ... on Dog @defer(label: "root") {
          species
        }
        ... on Cat {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(childEntity: allAnimals_asDog.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenNestedDeferredInlineFragments_rendersNestedDeferredFragmentAccessorsAsOptional() async throws {
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
    
    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
      friend: Animal!
    }
    
    type Cat implements Animal {
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

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_deferredAsOuter = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "outer")])
    let allAnimals_asDog_deferredAsOuter_asCat = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter[field: "friend"]?[as: "Cat"]
    )

    let rendered_asDog = subject.test_render(childEntity: allAnimals_asDog.computed)
    let rendered_asDog_deferredAsOuter_asCat = subject.test_render(
      childEntity: allAnimals_asDog_deferredAsOuter_asCat.computed
    )
    
    expect(rendered_asDog).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _outer = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var outer: Outer?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
    
    expect(rendered_asDog_deferredAsOuter_asCat).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _inner = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var inner: Inner?
        }
      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenBothDeferAndIncludeDirectivesOnSameTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Animal @include(if: $a) @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_ifA = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[if: "a"])

    let rendered = subject.test_render(childEntity: allAnimals_ifA.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenBothDeferAndSkipDirectivesOnSameTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Animal @skip(if: $a) @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_skipIfA = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[if: !"a"])

    let rendered = subject.test_render(childEntity: allAnimals_skipIfA.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenBothDeferAndIncludeDirectivesOnDifferentTypeCase_rendersDeferredFragmentAccessorsAsOptional() async throws {
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
        ... on Animal @include(if: $a) {
          species
        }
        ... on Dog @defer(label: "root") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(childEntity: allAnimals_asDog.computed)
    
    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }

  // MARK: Fragment Accessors - Deferred Named Fragment

  func test__render_fragmentAccessor__givenDeferredNamedFragmentOnSameTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
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
          ...AnimalFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let rendered = subject.test_render(childEntity: allAnimals.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _animalFragment = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var animalFragment: AnimalFragment?
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredNamedFragmentOnDifferentTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
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
          ...DogFragment @defer(label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _dogFragment = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var dogFragment: DogFragment?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredNamedFragmentWithVariableCondition_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
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
          ...DogFragment @defer(if: "a", label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _dogFragment = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var dogFragment: DogFragment?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredNamedFragmentWithTrueCondition_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
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
          ...DogFragment @defer(if: true, label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _dogFragment = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var dogFragment: DogFragment?
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredNamedFragmentWithFalseCondition_doesNotRenderDeferredFragmentAccessor() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
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
          ...DogFragment @defer(if: false, label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])

    let rendered = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    expect(rendered).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }
      
          public var dogFragment: DogFragment { _toFragment() }
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragment_insideNamedFragment_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment
        }
      }

      fragment AnimalFragment on Dog {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_animalFragment = try XCTUnwrap(allAnimals_asDog[fragment: "AnimalFragment"])

    let rendered_allAnimals_asDog = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_asDog_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_asDog_animalFragment = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_asDog_animalFragment.rootField.selectionSet?.computed)
    )

    expect(rendered_allAnimals_asDog).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var animalFragment: AnimalFragment { _toFragment() }
        }
      """,
      atLine: 14,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_animalFragment).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Dog implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          id
          ...AnimalFragment
        }
      }

      fragment AnimalFragment on Animal {
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)
    let allAnimals_animalFragment = try XCTUnwrap(allAnimals[fragment: "AnimalFragment"])
    let allAnimals_animalFragment_asDog = try XCTUnwrap(allAnimals_animalFragment.rootField[as: "Dog"])

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)

    let fragmentSubject = SelectionSetTemplate(
      definition: allAnimals_animalFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )
    let rendered_allAnimals_animalFragment_asDog = fragmentSubject.test_render(
      childEntity: try XCTUnwrap(allAnimals_animalFragment_asDog.computed)
    )

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var animalFragment: AnimalFragment { _toFragment() }
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))

    expect(rendered_allAnimals_animalFragment_asDog).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _root = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var root: Root?
        }
      """,
      atLine: 12,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_fragmentAccessor__givenDeferredNamedFragmentWithMatchingSiblingTypeCase_rendersDeferredFragmentAccessorAsOptional() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String!
        species: String!
      }

      type Pet implements Animal {
        id: String!
        species: String!
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation {
        allAnimals {
          __typename
          ...AnimalFragment @defer(label: "root")
          ... on Pet {
            id
          }
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?.selectionSet)

    let rendered_allAnimals = subject.test_render(childEntity: allAnimals.computed)

    expect(rendered_allAnimals).to(equalLineByLine(
      """
        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _animalFragment = Deferred(_dataDict: _dataDict)
          }

          @Deferred public var animalFragment: AnimalFragment?
        }
      """,
      atLine: 15,
      ignoringExtraLines: true
    ))
  }

  // MARK: - Nested Selection Sets

  func test__render_nestedSelectionSets__givenDirectEntityFieldAsList_rendersNestedSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predators {
          species
        }
      }
    }
    """

    let expected = """
      public var predators: [Predator]? { __data["predators"] }

      /// AllAnimal.Predator
      public struct Predator: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSets__givenDirectEntityFieldAsList_withIrregularPluralizationRule_rendersNestedSelectionSetWithCorrectSingularName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      people: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        people {
          species
        }
      }
    }
    """

    let expected = """
      public var people: [Person]? { __data["people"] }

      /// AllAnimal.Person
      public struct Person: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSets__givenDirectEntityFieldAsNonNullList_withIrregularPluralizationRule_rendersNestedSelectionSetWithCorrectSingularName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      people: [Animal!]!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        people {
          species
        }
      }
    }
    """

    let expected = """
      public var people: [Person] { __data["people"] }

      /// AllAnimal.Person
      public struct Person: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSets__givenDirectEntityFieldAsList_withCustomIrregularPluralizationRule_rendersNestedSelectionSetWithCorrectSingularName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      people: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        people {
          species
        }
      }
    }
    """

    let expected = """
      public var people: [Peep]? { __data["people"] }

      /// AllAnimal.Peep
      public struct Peep: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation(inflectionRules: [
      ApolloCodegenLib.InflectionRule.irregular(singular: "Peep", plural: "people")
    ])

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  /// Explicit test for edge case surfaced in issue
  /// [#1825](https://github.com/apollographql/apollo-ios/issues/1825)
  func test__render_nestedSelectionSets__givenDirectEntityField_withTwoObjects_oneWithPluralizedNameAsObject_oneWithSingularNameAsList_rendersNestedSelectionSetsWithCorrectNames() async throws {
    // given
    schemaSDL = """
    type Query {
      badge: [Badge]
      badges: ProductBadge
    }

    type Badge {
      a: String
    }

    type ProductBadge {
      b: String
    }
    """

    document = """
    query TestOperation {
      badge {
        a
      }
      badges {
        b
      }
    }
    """

    let expected = """
      public var badge: [Badge?]? { __data["badge"] }
      public var badges: Badges? { __data["badges"] }

      /// Badge
      public struct Badge: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Badge }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("a", String?.self),
        ] }

        public var a: String? { __data["a"] }
      }

      /// Badges
      public struct Badges: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.ProductBadge }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("b", String?.self),
        ] }

        public var b: String? { __data["b"] }
      }
    """

    // when
    try await buildSubjectAndOperation()

    let query = try XCTUnwrap(
      operation[field: "query"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: query.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  /// Explicit test for edge case surfaced in issue
  /// [#1825](https://github.com/apollographql/apollo-ios/issues/1825)
  func test__render_nestedSelectionSets__givenDirectEntityField_withTwoObjectsNonNullFields_oneWithPluralizedNameAsObject_oneWithSingularNameAsList_rendersNestedSelectionSetsWithCorrectNames() async throws {
    // given
    schemaSDL = """
    type Query {
      badge: [Badge!]!
      badges: ProductBadge!
    }

    type Badge {
      a: String
    }

    type ProductBadge {
      b: String
    }
    """

    document = """
    query TestOperation {
      badge {
        a
      }
      badges {
        b
      }
    }
    """

    let expected = """
      public var badge: [Badge] { __data["badge"] }
      public var badges: Badges { __data["badges"] }

      /// Badge
      public struct Badge: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Badge }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("a", String?.self),
        ] }

        public var a: String? { __data["a"] }
      }

      /// Badges
      public struct Badges: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.ProductBadge }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("b", String?.self),
        ] }

        public var b: String? { __data["b"] }
      }
    """

    // when
    try await buildSubjectAndOperation()

    let query = try XCTUnwrap(
      operation[field: "query"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: query.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSets__givenEntityFieldMergedFromTwoSources_rendersMergedSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface WarmBlooded implements Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Dog implements Animal & Pet & WarmBlooded {
      name: String!
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
      meters: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          predator {
            height {
              feet
            }
          }
        }
        ... on WarmBlooded {
          predator {
            height {
              meters
            }
          }
        }
        ... on Dog {
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }

      /// AllAnimal.AsDog.Predator.Height
      public struct Height: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromFragment_rendersSelectionSetAsTypeAlias() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
      }
    }
    """

    let expected = """
      public var predator: Predator { __data["predator"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var predatorDetails: PredatorDetails { _toFragment() }
      }

      public typealias Predator = PredatorDetails.Predator
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromFragmentWithLowercaseName_rendersFragmentNestedSelectionSetName_asTypeAlias_correctlyCased() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...predatorDetails
      }
    }

    fragment predatorDetails on Animal {
      predator {
        species
      }
    }
    """

    let expected = """
      public var predator: Predator { __data["predator"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var predatorDetails: PredatorDetails { _toFragment() }
      }

      public typealias Predator = PredatorDetails.Predator
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromNestedFragmentInTypeCase_withNoOtherMergedFields_rendersSelectionSetAsTypeAlias() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface WarmBlooded implements Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      meters: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...WarmBloodedDetails
        }
      }
    }

    fragment WarmBloodedDetails on WarmBlooded {
      species
      ...HeightInMeters
    }

    fragment HeightInMeters on Animal {
      height {
        meters
      }
    }
    """

    let allAnimals_expected = """
      public var predator: Predator { __data["predator"] }

      /// AllAnimal.Predator
      public struct Predator: TestSchema.SelectionSet {
    """

    let allAnimals_predator_expected = """
      public var asWarmBlooded: AsWarmBlooded? { _asInlineFragment() }

      /// AllAnimal.Predator.AsWarmBlooded
      public struct AsWarmBlooded: TestSchema.InlineFragment {
    """

    let allAnimals_predator_asWarmBlooded_expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var warmBloodedDetails: WarmBloodedDetails { _toFragment() }
        public var heightInMeters: HeightInMeters { _toFragment() }
      }

      public typealias Height = HeightInMeters.Height
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )
    let allAnimals_predator = try XCTUnwrap(
      allAnimals[field: "predator"]
    )
    let allAnimals_predator_asWarmBlooded = try XCTUnwrap(
      allAnimals_predator[as: "WarmBlooded"]
    )

    let allAnimals_actual = subject.test_render(childEntity: allAnimals.computed)
    let allAnimals_predator_actual = subject.test_render(
      childEntity: allAnimals_predator.selectionSet!.computed
    )
    let allAnimals_predator_asWarmBlooded_actual = subject
      .test_render(inlineFragment: allAnimals_predator_asWarmBlooded.computed)

    // then
    expect(allAnimals_actual)
      .to(equalLineByLine(allAnimals_expected, atLine: 12, ignoringExtraLines: true))
    expect(allAnimals_predator_actual)
      .to(equalLineByLine(allAnimals_predator_expected, atLine: 12, ignoringExtraLines: true))
    expect(allAnimals_predator_asWarmBlooded_actual)
      .to(equalLineByLine(allAnimals_predator_asWarmBlooded_expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromTypeCaseInFragment_rendersSelectionSetAsTypeAlias() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet {
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
          ...PredatorDetails
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        height {
          feet
        }
      }
    }
    """

    let predator_asPet_expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var predatorDetails: PredatorDetails { _toFragment() }
      }

      public typealias Height = PredatorDetails.AsPet.Height
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let allAnimals_predator_asPet = try XCTUnwrap(allAnimals_predator[as: "Pet"])

    let allAnimals_predator_asPet_actual = subject.test_render(
      inlineFragment: allAnimals_predator_asPet.computed
    )

    // then
    expect(allAnimals_predator_asPet_actual).to(equalLineByLine(predator_asPet_expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromFragmentEntityNestedInEntity_rendersSelectionSetAsTypeAlias() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ...PredatorDetails
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        height {
          feet
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }

      public typealias Height = PredatorDetails.Predator.Height
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldNestedInEntityFieldInMatchingTypeCaseMergedFromParent_rendersSelectionSetAsTypeAlias() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      height: Height!
    }

    type Dog implements Animal & Pet {
      name: String!
      species: String!
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          predator {
            height {
              feet
            }
          }
        }
        ... on Dog {
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var species: String { __data["species"] }
      public var height: Height { __data["height"] }

      public typealias Height = AllAnimal.AsPet.Predator.Height
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenEntityFieldMergedFromSiblingTypeCase_atOperationRoot_rendersSelectionSetAsTypeAlias_withFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      role: String!
    }

    type AdminQuery implements ModeratorQuery {
      name: String!
      allAnimals: [Animal!]
    }

    interface ModeratorQuery {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }
    """

    document = """
    query TestOperation {
      ... on ModeratorQuery {
        allAnimals {
          species
        }
      }
      ... on AdminQuery {
        name
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var allAnimals: [AllAnimal]? { __data["allAnimals"] }

      public typealias AllAnimal = TestOperationQuery.Data.AsModeratorQuery.AllAnimal
    """

    // when
    try await buildSubjectAndOperation()
    let query_asAdminQuery = try XCTUnwrap(
      operation[field: "query"]?[as: "AdminQuery"]
    )

    let actual = subject.test_render(inlineFragment: query_asAdminQuery.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromParent_atOperationRoot_rendersSelectionSetAsTypeAlias_withFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type AdminQuery {
      name: String!
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
      ... on AdminQuery {
        name
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var allAnimals: [AllAnimal]? { __data["allAnimals"] }

      public typealias AllAnimal = TestOperationQuery.Data.AllAnimal
    """

    // when
    try await buildSubjectAndOperation()
    let query_asAdminQuery = try XCTUnwrap(
      operation[field: "query"]?[as: "AdminQuery"]
    )

    let actual = subject.test_render(inlineFragment: query_asAdminQuery.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMerged_fromTypeCase_withInclusionCondition_rendersSelectionSetAsTypeAlias_withFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAuthors: [Author!]
    }

    type Author {
      name: String
      postsInfoByIds: [PostInfo!]
    }

    interface PostInfo {
      awardings: [AwardingTotal!]
    }

    type AwardingTotal {
      id: String!
      comments: [Comment!]
      total: Int!
    }

    type Comment {
      id: String!
    }

    type Post implements PostInfo {
      id: String!
      awardings: [AwardingTotal!]
    }
    """

    document = """
    query TestOperation($a: Boolean = false) {
      allAuthors {
        name
        postsInfoByIds {
          ... on Post {
            awardings {
              total
            }
          }
          awardings @include(if: $a) {
            comments {
              id
            }
          }
        }
      }
    }
    """

    let expectedType = """
      public var comments: [Comment]? { __data["comments"] }

      /// AllAuthor.PostsInfoById.Awarding.Comment
      public struct Comment: TestSchema.SelectionSet {
    """

    let expectedTypeAlias = """
      public var comments: [Comment]? { __data["comments"] }
      public var total: Int { __data["total"] }

      public typealias Comment = PostsInfoById.Awarding.Comment
    """

    // when
    try await buildSubjectAndOperation()
    let allAuthors_postsInfoByIds = try XCTUnwrap(
      operation[field: "query"]?[field: "allAuthors"]?[field: "postsInfoByIds"]?.selectionSet
    )
    let allAuthors_postsInfoByIds_awardings = try XCTUnwrap(
      allAuthors_postsInfoByIds[field: "awardings"]?.selectionSet
    )
    let allAuthors_postsInfoByIds_asPost_awardings_ifA = try XCTUnwrap(
      allAuthors_postsInfoByIds[as: "Post"]?[field: "awardings"]?[if: "a"]
    )

    let actualType = subject.test_render(
      inlineFragment: allAuthors_postsInfoByIds_awardings.computed
    )
    let actualTypeAlias = subject.test_render(
      inlineFragment: allAuthors_postsInfoByIds_asPost_awardings_ifA.computed
    )

    // then
    expect(actualType).to(equalLineByLine(expectedType, atLine: 12, ignoringExtraLines: true))
    expect(actualTypeAlias).to(equalLineByLine(expectedTypeAlias, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMerged_fromTypeCase_withInclusionCondition_siblingTypeCaseSameFieldSameCondition_rendersSelectionSetAsTypeAlias_withFullyQualifiedName() async throws {
  // given
  schemaSDL = """
  type Query {
    allAuthors: [Thing!]
  }

  type Thing {
    name: String
    postsInfoByIds: [PostInfo!]
  }

  interface PostInfo {
    awardings: [AwardingTotal!]
  }

  type AwardingTotal {
    id: String!
    comments: [Comment!]
    total: Int!
    name: String!
  }

    type Comment {
      id: String!
    }

  type Post implements PostInfo {
    id: String!
    awardings: [AwardingTotal!]
  }
  """

  document = """
  query TestOperation($a: Boolean = false) {
    allAuthors {
      name
      postsInfoByIds {
        ... on Post {
          awardings {
            total
          }
          ... on PostInfo {
            awardings @include(if: $a) {
              name
            }
          }
        }
        awardings @include(if: $a) {
          comments {
            id
          }
        }
      }
    }
  }
  """

  let expectedType = """
    public var comments: [Comment]? { __data["comments"] }

    /// AllAuthor.PostsInfoById.Awarding.Comment
    public struct Comment: TestSchema.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Comment }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", String.self),
      ] }

      public var id: String { __data["id"] }
    }
  """

  let expectedTypeAlias = """
    public static var __selections: [ApolloAPI.Selection] { [
      .field("name", String.self),
    ] }

    public var name: String { __data["name"] }
    public var comments: [Comment]? { __data["comments"] }
    public var total: Int { __data["total"] }

    public typealias Comment = PostsInfoById.Awarding.Comment
  """

  // when
  try await buildSubjectAndOperation()
  let allAuthors_postsInfoByIds = try XCTUnwrap(
    operation[field: "query"]?[field: "allAuthors"]?[field: "postsInfoByIds"]?.selectionSet
  )
  let allAuthors_postsInfoByIds_awardings = try XCTUnwrap(
    allAuthors_postsInfoByIds[field: "awardings"]?.selectionSet
  )
  let allAuthors_postsInfoByIds_asPost_awardings_ifA = try XCTUnwrap(
    allAuthors_postsInfoByIds[as: "Post"]?[field: "awardings"]?[if: "a"]
  )

  let actualType = subject.test_render(
    inlineFragment: allAuthors_postsInfoByIds_awardings.computed
  )
  let actualTypeAlias = subject.test_render(
    inlineFragment: allAuthors_postsInfoByIds_asPost_awardings_ifA.computed
  )

  // then
  expect(actualType).to(equalLineByLine(expectedType, atLine: 12, ignoringExtraLines: true))
  expect(actualTypeAlias).to(equalLineByLine(expectedTypeAlias, atLine: 8, ignoringExtraLines: true))
}

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromParent_notOperationRoot_doesNotRendersTypeAliasForSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var predator: Predator { __data["predator"] }
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenMultipleEntityFields_oneMergedFromParent_rendersChildSelectionSetForOnlyNeededSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      friend: Animal!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      friend: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Pet {
          friend {
            species
          }
        }
      }
    }
    """

    let expected = """
      /// AllAnimal.AsPet.Friend
      public struct Friend: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("species", String.self),
        ] }

        public var species: String { __data["species"] }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: false))
  }

  func test__render_nestedSelectionSet__givenEntityFieldMergedFromSiblingTypeCase_notOperationRoot_rendersSelectionSetAsTypeAlias_withNameNotIncludingSharedParent() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          predator {
            species
          }
        }
        ... on Dog {
          name
        }
      }
    }
    """

    let expected = """
      public var name: String { __data["name"] }
      public var predator: Predator { __data["predator"] }

      public typealias Predator = AsPet.Predator
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSets__givenDirectSelection_typeCase_rendersNestedSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        ... on Pet {
          name
        }
      }
    }
    """

    let expected = """
      public var asPet: AsPet? { _asInlineFragment() }

      /// AllAnimal.AsPet
      public struct AsPet: TestSchema.InlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenMergedTypeCasesFromSingleMergedTypeCaseSource_rendersTypeCaseSelectionSetAsCompositeInlineFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet implements Animal {
      species: String!
      predator: Animal!
      name: String!
    }

    type Dog implements Animal & Pet {
      species: String!
      predator: Animal!
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        predator {
          ... on Pet {
            name
          }
        }
        ... on Dog {
          name
          predator {
            species
          }
        }
      }
    }
    """

    let expected = """
      public var asPet: AsPet? { _asInlineFragment() }

      /// AllAnimal.AsDog.Predator.AsPet
      public struct AsPet: TestSchema.InlineFragment, ApolloAPI.CompositeInlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenInlineFragmentOnSameTypeWithMultipleConditions_renders() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      fieldA: String!
    }

    interface Pet {
      fieldA: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ... @include(if: $a) @skip(if: $b) {
          fieldA
        }
      }
    }
    """

    let expected = """
      public var ifAAndNotB: IfAAndNotB? { _asInlineFragment() }

      /// AllAnimal.IfAAndNotB
      public struct IfAAndNotB: TestSchema.InlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenNamedFragmentOnSameTypeWithInclusionCondition_rendersConditionalSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String!
      int: Int!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      allAnimals {
        ...FragmentA @include(if: $a)
      }
    }

    fragment FragmentA on Animal {
      int
    }
    """

    let expected = """
      /// AllAnimal.IfA
      public struct IfA: TestSchema.InlineFragment {
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

  func test__render_nestedSelectionSet__givenTypeCaseMergedFromFragmentWithOtherMergedFields_rendersTypeCaseAsCompositeInlineFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
          species
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let predator_expected = """
      /// AllAnimal.Predator.AsPet
      public struct AsPet: TestSchema.InlineFragment, ApolloAPI.CompositeInlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let predator_actual = subject.test_render(childEntity: predator.computed)

    // then
    expect(predator_actual)
      .to(equalLineByLine(predator_expected, atLine: 24, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet__givenTypeCaseMergedFromFragmentWithNoOtherMergedFields_rendersTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predator: Animal!
    }

    interface Pet {
      favoriteToy: Item
    }

    type Item {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          ...PredatorDetails
        }
      }
    }

    fragment PredatorDetails on Animal {
      ... on Pet {
        favoriteToy {
          ...PetToy
        }
      }
    }

    fragment PetToy on Item {
      name
    }
    """

    let predator_expected = """
      /// AllAnimal.Predator.AsPet
      public struct AsPet: TestSchema.InlineFragment, ApolloAPI.CompositeInlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]?.selectionSet
    )

    let predator_actual = subject.test_render(childEntity: predator.computed)

    // then
    expect(predator_actual)
      .to(equalLineByLine(predator_expected, atLine: 21, ignoringExtraLines: true))
  }

// Related to https://github.com/apollographql/apollo-ios/issues/3326
  func test__render_nestedSelectionSet__givenInlineFragmentWithOnlyReservedField_doesNotRenderAsCompositeInlineFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal]
    }

    union Animal = AnimalObject | AnimalError

    type AnimalObject {
      species: String!
    }

    type AnimalError {
      code: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on AnimalObject {
          __typename
        }
      }
    }
    """

    let expected = """
      public var asAnimalObject: AsAnimalObject? { _asInlineFragment() }

      /// AllAnimal.AsAnimalObject
      public struct AsAnimalObject: TestSchema.InlineFragment {
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  // MARK: Nested Selection Sets - Reserved Keywords + Special Names

  func test__render_nestedSelectionSet__givenEntityFieldWithSwiftKeywordAndApolloReservedTypeNames_rendersSelectionSetWithNameSuffixed() async throws {
    let fieldNames = SwiftKeywords.TypeNamesToSuffix
    for fieldName in fieldNames {
      // given
      schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
        \(fieldName.firstLowercased): Animal!
      }
      """

      document = """
      query TestOperation {
        allAnimals {
          \(fieldName.firstLowercased) {
            species
          }
        }
      }
      """

      let expected = """
        /// AllAnimal.\(fieldName.firstUppercased)_SelectionSet
        public struct \(fieldName.firstUppercased)_SelectionSet: TestSchema.SelectionSet {
      """

      // when
      try await buildSubjectAndOperation()
      let allAnimals = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?.selectionSet
      )

      let predator_actual = subject.test_render(childEntity: allAnimals.computed)

      // then
      expect(predator_actual)
        .to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
    }
  }

  // MARK: - RootEntityType - Inline Fragment

  func test__render_nestedTypeCase__rendersRootEntityType() async throws {
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
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          name
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.AsPet
    public struct AsPet: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_AsPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_AsPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  func test__render_doublyNestedTypeCase__rendersRootEntityType() async throws {
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
    }

    interface WarmBlooded {
      name: String!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on WarmBlooded {
          ... on Pet {
            name
          }
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.AsWarmBlooded.AsPet
    public struct AsPet: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
    """

    // when
    try await buildSubjectAndOperation()
    let allAnimals_AsPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "WarmBlooded"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_AsPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  func test__render_nestedTypeCaseWithNameConflictingWithChild__rendersRootEntityType() async throws {
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
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predators {
           ... on Pet {
            name
          }
          predators {
            species
          }
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.Predator.AsPet
    public struct AsPet: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data.AllAnimal.Predator
    """

    // when
    try await buildSubjectAndOperation()
    let predators_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  /// Test for edge case in [#2949](https://github.com/apollographql/apollo-ios/issues/2949)
  ///
  /// When the `RootEntityType` would have duplicate naming, due to child fields with the same name
  /// (or alias), the fully qualified name must be used. In this example, a `RootEntityType` of
  /// `Predator.Predator` the first usage of the name `Predator` would be referencing the nearest
  /// enclosing type (ie. `TestOperationQuery.Predator.Predator`), so it is looking for another
  /// `Predator` type in that scope, which does not exist
  /// (ie. `TestOperationQuery.Predator.Predator.Predator`).
  ///
  /// To correct this we must always use the fully qualified name including the operation name and
  /// `Data` objects to ensure we are referring to the correct type.
  func test__render_nestedTypeCaseWithNameConflictingWithChildAtQueryRoot__rendersRootEntityTypeWithFullyQualifiedName() async throws {
    // given
    schemaSDL = """
    type Query {
      predators: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }

    interface Pet {
      name: String!
    }
    """

    document = """
    query TestOperation {
      predators {
        predators {
           ... on Pet {
            name
          }
        }
      }
    }
    """

    let expected = """
    /// Predator.Predator.AsPet
    public struct AsPet: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data.Predator.Predator
    """

    // when
    try await buildSubjectAndOperation()
    let predators_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "predators"]?[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  func test__render_conditionalFragmentOnQueryRoot__rendersRootEntityType() async throws {
    // given
    schemaSDL = """
    type Query {
      name: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      ...Details @include(if: $a)
    }

    fragment Details on Query {
      name
    }
    """

    let expected = """
    /// IfA
    public struct IfA: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data
    """

    // when
    try await buildSubjectAndOperation()
    let query_ifA = try XCTUnwrap(
      operation[field: "query"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: query_ifA.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  func test__render_conditionalTypeCaseFragmentOnQueryRoot__rendersRootEntityType() async throws {
    // given
    schemaSDL = """
    type Query {
      name: String!
    }

    interface AdminQuery {
      adminName: String!
    }
    """

    document = """
    query TestOperation($a: Boolean!) {
      ...AdminDetails @include(if: $a)
    }

    fragment AdminDetails on AdminQuery {
      adminName
    }
    """

    let expected = """
    /// AsAdminQueryIfA
    public struct AsAdminQueryIfA: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = TestOperationQuery.Data
    """

    // when
    try await buildSubjectAndOperation()
    let query_ifA = try XCTUnwrap(
      operation[field: "query"]?[as: "AdminQuery", if: "a"]
    )

    let actual = subject.test_render(inlineFragment: query_ifA.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }

  func test__render_typeCaseInFragmentOnQueryRoot__rendersRootEntityTypeNamespacedToFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      predators: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }

    interface Pet {
      name: String!
    }
    """

    document = """
    query TestOperation {
      ...Details
    }

    fragment Details on Query {
      predators {
        predators {
          ... on Pet {
            name
          }
        }
      }
    }
    """

    let expected = """
    /// Predator.Predator.AsPet
    public struct AsPet: TestSchema.InlineFragment {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public typealias RootEntityType = Details.Predator.Predator
    """

    // when
    try await buildSubjectAndOperation()
    let detailsFragment = try XCTUnwrap(
      operation[fragment: "Details"]
    )
    let detailsFragment_predators_predators_asPet = try XCTUnwrap(
      detailsFragment.rootField[field: "predators"]?[field: "predators"]?[as: "Pet"]
    )

    let fragmentTemplate = SelectionSetTemplate(
      definition: detailsFragment.fragment,
      generateInitializers: false,
      config: self.subject.config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: self.subject.renderAccessControl()
    )

    let actual = fragmentTemplate.test_render(
      inlineFragment: detailsFragment_predators_predators_asPet.computed
    )

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 1, ignoringExtraLines: true))
  }
  
  // MARK: RootEntityType - Deferred Inline Fragment

  func test__render_deferredTypeCase__givenDeferredInlineFragmentWithoutTypeCase_rendersRootEntityType() async throws {
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
        ... @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_deferredAsRoot = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[deferred: .init(label: "root")]
    )

    let rendered_allAnimals_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_deferredAsRoot.computed
    )

    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """
      /// AllAnimal.Root
      public struct Root: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }

  func test__render_deferredTypeCase__givenDeferredInlineFragmentOnSameTypeCase_rendersRootEntityType() async throws {
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
        ... on Animal @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_deferredAsRoot = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[deferred: .init(label: "root")]
    )

    let rendered_allAnimals_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_deferredAsRoot.computed
    )

    expect(rendered_allAnimals_deferredAsRoot).to(equalLineByLine(
      """
      /// AllAnimal.Root
      public struct Root: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }

  func test__render_deferredTypeCase__givenDeferredInlineFragmentOnDifferentTypeCase_rendersRootEntityType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String!
      species: String!
    }

    type Dog implements Animal {
      id: String!
      species: String!
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog_deferredAsRoot = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[deferred: .init(label: "root")]
    )

    let rendered_allAnimals_asDog_deferredAsRoot = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsRoot.computed
    )

    expect(rendered_allAnimals_asDog_deferredAsRoot).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.Root
      public struct Root: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_deferredTypeCase__givenSiblingDeferredInlineFragmentOnSameTypeCase_rendersSeparateRootEntityTypes() async throws {
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
    
    type Dog implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Dog @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asDog_deferredAsTwo = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "two")])

    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asDog_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsTwo.computed
    )

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.One
      public struct One: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsTwo).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.Two
      public struct Two: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_deferredTypeCase__givenSiblingDeferredInlineFragmentOnDifferentTypeCase_rendersSeparateRootEntityTypes() async throws {
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
    
    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
    }

    type Cat implements Animal {
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
        ... on Dog @defer(label: "one") {
          species
        }
        ... on Cat @defer(label: "two") {
          genus
        }
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_deferredAsOne = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "one")])
    let allAnimals_asCat = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"])
    let allAnimals_asCat_deferredAsTwo = try XCTUnwrap(allAnimals_asCat[deferred: .init(label: "two")])

    let rendered_allAnimals_asDog_deferredAsOne = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOne.computed
    )
    let rendered_allAnimals_asCat_deferredAsTwo = subject.test_render(
      inlineFragment: allAnimals_asCat_deferredAsTwo.computed
    )

    expect(rendered_allAnimals_asDog_deferredAsOne).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.One
      public struct One: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asCat_deferredAsTwo).to(equalLineByLine(
      """
      /// AllAnimal.AsCat.Two
      public struct Two: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Cat }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }
  
  func test__render_deferredTypeCase__givenNestedDeferredInlineFragments_rendersNestedRootEntityTypes() async throws {
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
    
    type Dog implements Animal {
      id: String!
      species: String!
      genus: String!
      friend: Animal!
    }

    type Cat implements Animal {
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

    // then
    let allAnimals_asDog = try XCTUnwrap(operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"])
    let allAnimals_asDog_deferredAsOuter = try XCTUnwrap(allAnimals_asDog[deferred: .init(label: "outer")])
    let allAnimals_asDog_deferredAsOuter_asCat = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter[field: "friend"]?[as: "Cat"]
    )
    let allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner = try XCTUnwrap(
      allAnimals_asDog_deferredAsOuter_asCat[deferred: .init(label: "inner")]
    )

    let rendered_allAnimals_asDog_deferredAsOuter = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter.computed
    )
    let rendered_allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner = subject.test_render(
      inlineFragment: allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner.computed
    )

    expect(rendered_allAnimals_asDog_deferredAsOuter).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.Outer
      public struct Outer: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
    
    expect(rendered_allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner).to(equalLineByLine(
      """
      /// AllAnimal.AsDog.Outer.Friend.AsCat.Inner
      public struct Inner: TestSchema.InlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Cat }
      """,
      atLine: 1,
      ignoringExtraLines: true
    ))
  }

  // MARK: - Documentation Tests

  func test__render_nestedSelectionSet__givenSchemaDocumentation_include_hasDocumentation_shouldGenerateDocumentationComment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predators {
          species
        }
      }
    }
    """

    let expected = """
      public var predators: [Predator]? { __data["predators"] }

      /// AllAnimal.Predator
      ///
      /// Parent Type: `Animal`
      public struct Predator: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation(schemaDocumentation: .include)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render_nestedSelectionSet_givenSchemaDocumentation_exclude_hasDocumentation_shouldNotGenerateDocumentationComment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
      predators: [Animal!]
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predators {
          species
        }
      }
    }
    """

    let expected = """
      public var predators: [Predator]? { __data["predators"] }

      /// AllAnimal.Predator
      public struct Predator: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation(schemaDocumentation: .exclude)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenSchemaDocumentation_include_hasDocumentation_shouldGenerateDocumentationComment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      "This field is a string."
      string: String!
    }

    scalar Custom
    """

    document = """
    query TestOperation {
      allAnimals {
        string
      }
    }
    """

    let expected = """
      /// This field is a string.
      public var string: String { __data["string"] }
    """

    // when
    try await buildSubjectAndOperation(schemaDocumentation: .include)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenSchemaDocumentation_exclude_hasDocumentation_shouldNotGenerateDocumentationComment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      "This field is a string."
      string: String!
    }

    scalar Custom
    """

    document = """
    query TestOperation {
      allAnimals {
        string
      }
    }
    """

    let expected = """
      public var string: String { __data["string"] }
    """

    // when
    try await buildSubjectAndOperation(schemaDocumentation: .exclude)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  // MARK: - Deprecation Warnings

  func test__render_fieldAccessors__givenWarningsOnDeprecatedUsage_include_hasDeprecatedField_withDocumentation_shouldGenerateWarningBelowDocumentation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      "This field is a string."
      string: String! @deprecated(reason: "Cause I said so!")
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        string
      }
    }
    """

    let expected = """
      /// This field is a string.
      @available(*, deprecated, message: "Cause I said so!")
      public var string: String { __data["string"] }
    """

    // when
    try await buildSubjectAndOperation(
      schemaDocumentation: .include,
      warningsOnDeprecatedUsage: .include
    )
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenWarningsOnDeprecatedUsage_exclude_hasDeprecatedField_shouldNotGenerateWarning() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      string: String! @deprecated
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        string
      }
    }
    """

    let expected = """
      public var string: String { __data["string"] }
    """

    // when
    try await buildSubjectAndOperation(warningsOnDeprecatedUsage: .exclude)
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_selections__givenWarningsOnDeprecatedUsage_include_usesDeprecatedArgument__shouldGenerateWarning() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal
    }

    type Animal {
      friend(name: String, species: String @deprecated(reason: "Who cares?")): Animal
      species: String
    }
    """

    document = """
    query TestOperation($name: String, $species: String) {
      animal {
        friend(name: $name, species: $species) {
          species
        }
      }
    }
    """

    let expected = """
      #warning("Argument 'species' of field 'friend' is deprecated. Reason: 'Who cares?'")
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("friend", Friend?.self, arguments: [
          "name": .variable("name"),
          "species": .variable("species")
        ]),
      ] }
    """

    // when
    try await buildSubjectAndOperation(
      warningsOnDeprecatedUsage: .include
    )
    let animal = try XCTUnwrap(
      operation[field: "query"]?[field: "animal"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: animal.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenWarningsOnDeprecatedUsage_exclude_usesDeprecatedArgument__shouldNotGenerateWarning() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal
    }

    type Animal {
      friend(name: String, species: String @deprecated(reason: "Who cares?")): Animal
      species: String
    }
    """

    document = """
    query TestOperation($name: String, $species: String) {
      animal {
        friend(name: $name, species: $species) {
          species
        }
      }
    }
    """

    let expected = """
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("friend", Friend?.self, arguments: [
          "name": .variable("name"),
          "species": .variable("species")
        ]),
      ] }
    """

    // when
    try await buildSubjectAndOperation(
      warningsOnDeprecatedUsage: .exclude
    )
    let animal = try XCTUnwrap(
      operation[field: "query"]?[field: "animal"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: animal.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenWarningsOnDeprecatedUsage_include_usesMultipleDeprecatedArgumentsSameField__shouldGenerateWarningAllWarnings() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal
    }

    type Animal {
      friend(
        name: String @deprecated(reason: "Someone broke it."),
        species: String @deprecated(reason: "Who cares?")
      ): Animal
      species: String
    }
    """

    document = """
    query TestOperation($name: String, $species: String) {
      animal {
        friend(name: $name, species: $species) {
          species
        }
      }
    }
    """

    let expected = """
      #warning("Argument 'name' of field 'friend' is deprecated. Reason: 'Someone broke it.'"),
      #warning("Argument 'species' of field 'friend' is deprecated. Reason: 'Who cares?'")
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("friend", Friend?.self, arguments: [
          "name": .variable("name"),
          "species": .variable("species")
        ]),
      ] }
    """

    // when
    try await buildSubjectAndOperation(
      warningsOnDeprecatedUsage: .include
    )
    let animal = try XCTUnwrap(
      operation[field: "query"]?[field: "animal"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: animal.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  func test__render_selections__givenWarningsOnDeprecatedUsage_include_usesMultipleDeprecatedArgumentsDifferentFields__shouldGenerateWarningAllWarnings() async throws {
    // given
    schemaSDL = """
    type Query {
      animal: Animal
    }

    type Animal {
      friend(name: String @deprecated(reason: "Someone broke it.")): Animal
      species(species: String @deprecated(reason: "Redundant")): String
    }
    """

    document = """
    query TestOperation($name: String, $species: String) {
      animal {
        friend(name: $name) {
          species
        }
        species(species: $species)
      }
    }
    """

    let expected = """
      #warning("Argument 'name' of field 'friend' is deprecated. Reason: 'Someone broke it.'"),
      #warning("Argument 'species' of field 'species' is deprecated. Reason: 'Redundant'")
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("friend", Friend?.self, arguments: ["name": .variable("name")]),
        .field("species", String?.self, arguments: ["species": .variable("species")]),
      ] }
    """

    // when
    try await buildSubjectAndOperation(
      warningsOnDeprecatedUsage: .include
    )
    let animal = try XCTUnwrap(
      operation[field: "query"]?[field: "animal"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: animal.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 7, ignoringExtraLines: true))
  }

  // MARK: - Reserved Keyword Type Tests

  func test__render_enumType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    type Query {
      getUser: User
    }

    type User {
      id: String!
      name: String!
      type: Type!
    }

    enum Type {
      ADMIN
      MEMBER
    }
    """

    document = """
    query TestOperation {
        getUser {
            type
        }
    }
    """

    let expectedOne = """
        .field("type", GraphQLEnum<TestSchema.Type_Enum>.self),
    """

    let expectedTwo = """
      public var type: GraphQLEnum<TestSchema.Type_Enum> { __data["type"] }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getUser"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expectedOne, atLine: 9, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedTwo, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_NamedFragmentType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    type Query {
      getUser: User
    }

    type User {
      id: String!
      name: String!
      type: UserRole!
    }

    enum UserRole {
      ADMIN
      MEMBER
    }
    """

    document = """
    query TestOperation {
        getUser {
            ...Type
        }
    }

    fragment Type on User {
        name
        type
    }
    """

    let expectedOne = """
        .fragment(Type_Fragment.self),
    """

    let expectedTwo = """
        public var type: Type_Fragment { _toFragment() }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getUser"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expectedOne, atLine: 9, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedTwo, atLine: 19, ignoringExtraLines: true))
  }

  func test__render_CustomScalarType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    scalar Type

    type Query {
      getUser: User
    }

    type User {
      id: String!
      name: String!
      type: Type!
    }
    """

    document = """
    query TestOperation {
        getUser {
            type
        }
    }
    """

    let expectedOne = """
        .field("type", TestSchema.Type_Scalar.self),
    """

    let expectedTwo = """
      public var type: TestSchema.Type_Scalar { __data["type"] }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getUser"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expectedOne, atLine: 9, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedTwo, atLine: 12, ignoringExtraLines: true))
  }

  func test__render_InterfaceType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    interface Type {
      name: String!
    }

    type Query {
      getUser: Type
    }

    type User implements Type {
      id: String!
    }
    """

    document = """
    query TestOperation {
        getUser {
            name
        }
    }
    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Type_Interface }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getUser"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_UnionType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    union Type = User | Admin

    type Query {
      getUser: Type
    }

    type User {
      id: String!
      name: String!
    }

    type Admin {
      id: String!
      role: String!
    }
    """

    document = """
    query TestOperation {
        getUser {
            ... on User {
              name
            }
            ... on Admin {
              role
            }
        }
    }

    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Unions.Type_Union }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getUser"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_ObjectType__usingReservedKeyword_rendersAsSuffixedType() async throws {
    // given
    schemaSDL = """
    type Query {
      getType: Type
    }

    type Type {
      id: String!
      name: String!
    }
    """

    document = """
    query TestOperation {
        getType {
            name
        }
    }
    """

    let expected = """
      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Type_Object }
    """

    // when
    try await buildSubjectAndOperation()
    let user = try XCTUnwrap(
      operation[field: "query"]?[field: "getType"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: user.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

}
