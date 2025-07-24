import ApolloCodegenInternalTestHelpers
import IR
import Nimble
import XCTest

@testable import ApolloCodegenLib

final class FragmentTemplateTests: XCTestCase, @unchecked Sendable {

  // MARK: - Helpers

  private func buildFragmentTemplate(
    named fragmentName: String = "TestFragment",
    config: ApolloCodegenConfiguration = .mock(),
    schemaSDL: String = FragmentTemplateTests.defaultSchema,
    document: String = FragmentTemplateTests.defaultDocument
  ) async throws -> (fragment: NamedFragment, template: FragmentTemplate) {
    let ir: IRBuilder = try await .mock(schema: schemaSDL, document: document)
    let fragmentDefinition = try XCTUnwrap(ir.compilationResult[fragment: fragmentName])
    let fragment = await ir.build(fragment: fragmentDefinition)
    return
      (
        fragment,
        FragmentTemplate(
          fragment: fragment,
          config: ApolloCodegen.ConfigurationContext(config: config)
        )
      )
  }

  private static let defaultSchema: String = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

  private static let defaultDocument: String = """
    fragment TestFragment on Query {
      allAnimals {
        species
      }
    }
    """

  private func render(_ template: FragmentTemplate) -> String {
    template.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: - Target Configuration Tests

  func test__target__givenModuleImports_targetHasModuleImports() async throws {
    // given
    let document = """
      fragment TestFragment on Query @import(module: "ModuleA") {
        allAnimals {
          species
        }
      }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(document: document)

    guard case let .operationFile(actual) = template.target else {
      fail("expected operationFile target")
      return
    }

    // then
    expect(actual).to(equal(["ModuleA"]))
  }

  // MARK: Fragment Definition

  func test__render__givenFragment_generatesFragmentDeclarationDefinitionAndBoilerplate() async throws {
    // given
    let expected =
      """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
          #"fragment TestFragment on Query { __typename allAnimals { __typename species } }"#
        }

        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }
      """

    // when
    let (_, template) = try await buildFragmentTemplate()

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenFragment_generatesFragmentDeclarationWithoutDefinition() async throws {
    // given
    let expected =
      """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          operationDocumentFormat: .operationId
        )
      )
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenLowercaseFragment_generatesTitleCaseTypeName() async throws {
    // given
    let document = """
      fragment testFragment on Query {
        allAnimals {
          species
        }
      }
      """

    let expected =
      """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
          #"fragment testFragment on Query { __typename allAnimals { __typename species } }"#
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      named: "testFragment",
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenFragmentWithUnderscoreInName_rendersDeclarationWithName() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    let document = """
      fragment Test_Fragment on Animal {
        species
      }
      """

    let expected = """
      struct Test_Fragment: TestSchema.SelectionSet, Fragment {
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      named: "Test_Fragment",
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Object_rendersParentType() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected = """
        static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Animal }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Interface_rendersParentType() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected = """
        static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Union_rendersParentType() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Dog {
        species: String!
      }

      union Animal = Dog
      """

    let document = """
      fragment TestFragment on Animal {
        ... on Dog {
          species
        }
      }
      """

    let expected = """
        static var __parentType: any ApolloAPI.ParentType { TestSchema.Unions.Animal }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func
    test__render__givenFragmentOnRootOperationTypeWithOnlyTypenameField_generatesFragmentDefinition_withNoSelections()
    async throws
  {
    // given
    let document = """
      fragment TestFragment on Query {
        __typename
      }
      """

    let (_, template) = try await buildFragmentTemplate(
      document: document
    )

    let expected = """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
          #"fragment TestFragment on Query { __typename }"#
        }

        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Query }
      }

      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render__givenFragmentWithOnlyTypenameField_generatesFragmentDefinition_withTypeNameSelection() async throws
  {
    // given
    let document = """
      fragment TestFragment on Animal {
        __typename
      }
      """

    let (_, template) = try await buildFragmentTemplate(
      document: document
    )

    let expected = """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
          #"fragment TestFragment on Animal { __typename }"#
        }

        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Animal }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
        ] }
      }

      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Access Level Tests

  func test__render__givenModuleType_swiftPackageManager_generatesFragmentDefinition_withPublicAccess() async throws {
    // given
    let (_, template) = try await buildFragmentTemplate(config: .mock(.swiftPackage()))

    let expected = """
      public struct TestFragment: TestSchema.SelectionSet, Fragment {
        public static var fragmentDefinition: StaticString {
      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenModuleType_other_generatesFragmentDefinition_withPublicAccess() async throws {
    // given
    let (_, template) = try await buildFragmentTemplate(config: .mock(.other))

    let expected = """
      public struct TestFragment: TestSchema.SelectionSet, Fragment {
        public static var fragmentDefinition: StaticString {
      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func
    test__render__givenModuleType_embeddedInTarget_withInternalAccessModifier_generatesFragmentDefinition_withInternalAccess()
    async throws
  {
    // given
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    )

    let expected = """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func
    test__render__givenModuleType_embeddedInTarget_withPublicAccessModifier_generatesFragmentDefinition_withPublicAccess()
    async throws
  {
    // given
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .public))
    )

    let expected = """
      struct TestFragment: TestSchema.SelectionSet, Fragment {
        public static var fragmentDefinition: StaticString {
      """

    // when
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: Initializer Tests

  func test__render_givenInitializerConfigIncludesNamedFragments_rendersInitializer() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          selectionSetInitializers: [.namedFragments]
        )
      ),
      schemaSDL: schemaSDL,
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragment_configIncludesSpecificFragment_rendersInitializer() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          selectionSetInitializers: [.fragment(named: "TestFragment")]
        )
      ),
      schemaSDL: schemaSDL,
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragment_configDoesNotIncludeNamedFragments_doesNotRenderInitializer() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          selectionSetInitializers: [.operations]
        )
      ),
      schemaSDL: schemaSDL,
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragments_configIncludeSpecificFragmentWithOtherName_doesNotRenderInitializer()
    async throws
  {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal {
        species
      }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          selectionSetInitializers: [.fragment(named: "OtherFragment")]
        )
      ),
      schemaSDL: schemaSDL,
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragments_asLocalCacheMutation_rendersInitializer() async throws {
    // given
    let schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    let document = """
      fragment TestFragment on Animal @apollo_client_ios_localCacheMutation {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      config: .mock(
        options: .init(
          selectionSetInitializers: []
        )
      ),
      schemaSDL: schemaSDL,
      document: document
    )

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 20, ignoringExtraLines: true))
  }

  func
    test__render_givenOperationSelectionSet_initializerConfig_all_fieldMergingConfig_notAll_doesNotRenderInitializer()
    async throws
  {
    let tests: [ApolloCodegenConfiguration.FieldMerging] = [
      .none,
      .ancestors,
      .namedFragments,
      .siblings,
      [.ancestors, .namedFragments],
      [.siblings, .ancestors],
      [.siblings, .namedFragments],
    ]

    for test in tests {
      // given
      let schemaSDL = """
        type Query {
          allAnimals: [Animal!]
        }

        type Animal {
          species: String!
        }
        """

      let document = """
        fragment TestFragment on Animal {
          species
        }
        """

      // when
      let (_, template) = try await buildFragmentTemplate(
        config: .mock(
          options: .init(
            selectionSetInitializers: [.all]
          ),
          experimentalFeatures: .init(fieldMerging: test)
        ),
        schemaSDL: schemaSDL,
        document: document
      )

      let actual = render(template)

      // then
      expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
    }
  }

  // MARK: Local Cache Mutation Tests
  func
    test__render__givenFragment__asLocalCacheMutation_generatesFragmentDeclarationDefinitionAsMutableSelectionSetAndBoilerplate()
    async throws
  {
    // given
    let document = """
      fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """

    let expected =
      """
      struct TestFragment: TestSchema.MutableSelectionSet, Fragment {
      """

    // when
    let (_, template) = try await buildFragmentTemplate(document: document)

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func
    test__render__givenFragment__asLocalCacheMutation_generatesFragmentDefinitionStrippingLocalCacheMutationDirective()
    async throws
  {
    // given
    let document = """
      fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """

    let expected =
      """
      struct TestFragment: TestSchema.MutableSelectionSet, Fragment {
        static var fragmentDefinition: StaticString {
          #"fragment TestFragment on Query { __typename allAnimals { __typename species } }"#
        }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(document: document)

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenFragment__asLocalCacheMutation_generatesFragmentDefinitionAsMutableSelectionSet() async throws
  {
    // given
    let document = """
      fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
        allAnimals {
          species
        }
      }
      """

    let expected =
      """
        var __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Query }
        static var __selections: [ApolloAPI.Selection] { [
          .field("allAnimals", [AllAnimal]?.self),
        ] }

        var allAnimals: [AllAnimal]? {
          get { __data["allAnimals"] }
          set { __data["allAnimals"] = newValue }
        }
      """

    // when
    let (_, template) = try await buildFragmentTemplate(document: document)

    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  // MARK: Casing

  func test__casing__givenLowercasedSchemaName_generatesWithFirstUppercasedNamespace() async throws {
    // given
    let (_, template) = try await buildFragmentTemplate(config: .mock(schemaNamespace: "mySchema"))

    // then
    let expected = """
      struct TestFragment: MySchema.SelectionSet, Fragment {
      """

    let actual = render(template)

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenUppercasedSchemaName_generatesWithUppercasedNamespace() async throws {
    // given
    let (_, template) = try await buildFragmentTemplate(config: .mock(schemaNamespace: "MY_SCHEMA"))

    // then
    let expected = """
      struct TestFragment: MY_SCHEMA.SelectionSet, Fragment {
      """

    let actual = render(template)

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenCapitalizedSchemaName_generatesWithCapitalizedNamespace() async throws {
    // given
    let (_, template) = try await buildFragmentTemplate(config: .mock(schemaNamespace: "MySchema"))

    // then
    let expected = """
      struct TestFragment: MySchema.SelectionSet, Fragment {
      """

    let actual = render(template)

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Reserved Keyword Tests

  func test__render__givenFragmentReservedKeywordName_rendersEscapedName() async throws {
    let keywords = ["Type", "type"]

    try await keywords.asyncForEach { keyword in
      // given
      let schemaSDL = """
        type Query {
          getUser(id: String): User
        }

        type User {
          id: String!
          name: String!
        }
        """

      let document = """
        fragment \(keyword) on User {
            name
        }
        """

      let expected = """
        struct \(keyword.firstUppercased)_Fragment: TestSchema.SelectionSet, Fragment {
        """

      // when
      let (_, template) = try await buildFragmentTemplate(named: keyword, schemaSDL: schemaSDL, document: document)
      let actual = render(template)

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }

  // MARK: - Protocol conformance

  func test__render__givenFragmentWithIdKeyField_rendersIdentifiableConformance() async throws {
    // given
    let schemaSDL = """
      type Query {
        getUser(id: String): User
      }
        
      type User @typePolicy(keyFields: "id") {
        id: String!
        name: String!
      }
      """

    let document = """
      fragment NodeFragment on User {
        id
      }
      """

    let expected = """
      struct NodeFragment: TestSchema.SelectionSet, Fragment, Identifiable {
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      named: "NodeFragment",
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render_givenFragment_withoutUsingIDField_doesNotRenderIdentifiableConformance() async throws {
    // given
    let schemaSDL = """
      type Query {
        getUser(id: String): User
      }
        
      type User @typePolicy(keyFields: "id") {
        id: String!
        name: String!
      }
      """

    let document = """
      fragment UserFragment on User {
        name
      }
      """

    let expected = """
      struct UserFragment: TestSchema.SelectionSet, Fragment {
      """

    // when
    let (_, template) = try await buildFragmentTemplate(
      named: "UserFragment",
      schemaSDL: schemaSDL,
      document: document
    )
    let actual = render(template)

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
}
