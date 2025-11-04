import XCTest
import Nimble
import IR
import TemplateString
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class SelectionSetTemplate_FieldMerging_Tests: XCTestCase {

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
    fieldMerging: ApolloCodegenConfiguration.FieldMerging = .all,
    selectionSetInitializers: Bool = false,
    warningsOnDeprecatedUsage: ApolloCodegenConfiguration.Composition = .exclude,
    conversionStrategies: ApolloCodegenConfiguration.ConversionStrategies = .init(),
    cocoapodsImportStatements: Bool = false
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])

    operation = await ir.build(
      operation: operationDefinition,
      mergingStrategy: fieldMerging.options
    )

    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      schemaNamespace: "TestSchema",
      output: configOutput,
      options: .init(
        additionalInflectionRules: inflectionRules,
        schemaDocumentation: schemaDocumentation,
        cocoapodsCompatibleImportStatements: cocoapodsImportStatements,
        warningsOnDeprecatedUsage: warningsOnDeprecatedUsage,
        conversionStrategies: conversionStrategies
      ),
      experimentalFeatures: .init(fieldMerging: fieldMerging)
    ))
    let mockTemplateRenderer = MockTemplateRenderer(
      target: .operationFile(),
      template: "",
      config: config
    )
    subject = SelectionSetTemplate(
      definition: self.operation.irObject,
      generateInitializers: selectionSetInitializers,
      config: config,
      nonFatalErrorRecorder: .init(),
      renderAccessControl: mockTemplateRenderer.accessControlModifier(for: .member)
    )
  }

  // MARK: - Tests

  // MARK: - Field Accessors

  func test__render_fieldAccessors__givenFieldMerging_doesNotIncludeNamedFragments_entityFieldMergedFromFragment_doesNotRenderFieldAccessorForFragmentField() async throws {
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
        species
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

      public var species: String { __data["species"] }

    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .none
    )
    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?.selectionSet
    )

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldMerging_siblings_rendersSiblingField_notAncestorField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet implements Animal & WarmBlooded {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }

    interface WarmBlooded implements Animal {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        ... on Pet {
          petName
        }
        ... on WarmBlooded {
          bodyTemperature
        }
      }
    }
    """

    let expected = """

      public var petName: String { __data["petName"] }
      public var bodyTemperature: Int { __data["bodyTemperature"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenFieldMerging_ancestors_rendersAncestorField_notSiblingField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet implements Animal & WarmBlooded {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }

    interface WarmBlooded implements Animal {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        species
        ... on Pet {
          petName
        }
        ... on WarmBlooded {
          bodyTemperature
        }
      }
    }
    """

    let expected = """

      public var petName: String { __data["petName"] }
      public var species: String { __data["species"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  // MARK: - Fragment Accessors

  func test__render_fragmentAccessors__givenFieldMerging_ancestors_rendersAncestorFragment_notSiblingFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet implements Animal & WarmBlooded {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }

    interface WarmBlooded implements Animal {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...SpeciesFragment
        ... on Pet {
          petName
        }
        ... on WarmBlooded {
          ...TempDetails
        }
      }
    }

    fragment SpeciesFragment on Animal {
      species
    }

    fragment TempDetails on WarmBlooded {
      bodyTemperature
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var speciesFragment: SpeciesFragment { _toFragment() }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 18, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessors__givenFieldMerging_siblings_rendersSiblingFragment_notAncestorFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet implements Animal & WarmBlooded {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }

    interface WarmBlooded implements Animal {
      species: String!
      petName: String!
      bodyTemperature: Int!
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...SpeciesFragment
        ... on Pet {
          petName
        }
        ... on WarmBlooded {
          ...TempDetails
        }
      }
    }

    fragment SpeciesFragment on Animal {
      species
    }

    fragment TempDetails on WarmBlooded {
      bodyTemperature
    }
    """

    let expected = """
      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var tempDetails: TempDetails { _toFragment() }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )
    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 19, ignoringExtraLines: true))
  }

  // MARK: - Composite Inline Fragments

  func test__render_compositeInlineFragment__givenFieldMerging_siblings_rendersSiblingCompositeInlineFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
      name: String
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
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
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )

    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_compositeInlineFragment__givenFieldMerging_ancestors_doesNotRenderSiblingCompositeInlineFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
      name: String
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
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
      public var species: String? { __data["species"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  // MARK: - Child Entity Selection Sets

  func test__render_childEntitySelectionSet__givenFieldMerging_none__givenEntityFieldMergedFromAncestor_doesNotRenderMergedChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    type Dog implements Animal {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public var species: String? { __data["species"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .none
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_ancestors__givenEntityFieldMergedFromAncestor_doesNotRenderMergedChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    type Dog implements Animal {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_ancestors__givenEntityFieldMergedFromAncestorAndSibling_doesNotRenderMergedChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Pet {
          predator {
            name
          }
        }
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_siblings__givenEntityFieldMergedFromAncestorAndSibling_rendersTypealiasToEntityInSibling() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Pet {
          predator {
            name
          }
        }
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }

      public typealias Predator = AsPet.Predator
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_ancestorsAndSiblings__givenEntityFieldMergedFromAncestorAndSibling_rendersMergedChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        predator {
          species
        }
        ... on Pet {
          predator {
            name
          }
        }
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }

      /// AllAnimal.AsDog.Predator
      public struct Predator: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.ancestors, .siblings]
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  // MARK: - Child Entity Selection Sets - In Union

  func test__render_childEntitySelectionSet_inUnion__givenFieldMerging_siblings__givenEntityFieldMergedFromSibling_rendersMergedChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      housePets: [HousePet!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }

    union HousePet = Dog
    """

    document = """
    query TestOperation {
      housePets {
        ... on Animal {
          predator {
            name
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
      public var predator: Predator? { __data["predator"] }

      /// HousePet.AsDog.Predator
      public struct Predator: TestSchema.SelectionSet {
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.siblings]
    )

    let housePets_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "housePets"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: housePets_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  // MARK: - Child Entity Selection Sets - From Named Fragments

  func test__render_childEntitySelectionSet__givenFieldMerging_ancestors__givenEntityFieldMergedFromNamedFragmentInAncestor_doesNotRenderChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ... on Dog {
          species
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
      public var species: String? { __data["species"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var predatorDetails: PredatorDetails { _toFragment() }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_ancestorsAndNamedFragments__givenEntityFieldMergedFromNamedFragmentInAncestor_rendersTypealiasToEntityInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ... on Dog {
          species
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
      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var predatorDetails: PredatorDetails { _toFragment() }
      }

      public typealias Predator = PredatorDetails.Predator
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.ancestors, .namedFragments]
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_siblingsAndNamedFragments__givenEntityFieldMergedFromNamedFragmentInAncestor_doesNotIncludeFieldAccessorOrChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ... on Dog {
          species
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
      public var species: String? { __data["species"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.siblings, .namedFragments]
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging__givenEntityFieldWithAdditionalFieldMergedFromNamedFragmentInAncestor_mergesFieldCorrectly() async throws {
    let tests: [(ApolloCodegenConfiguration.FieldMerging, shouldMergeField: Bool)] = [
      ([.ancestors, .namedFragments], false),
      ([.siblings, .namedFragments], true),
      (.namedFragments, false)
    ]

    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ... on Dog {
          predator {
            name
          }
        }
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
      }
    }
    """

    for test in tests {
      let expected = TemplateString("""
        public var name: String? { __data["name"] }
      \(if: test.shouldMergeField, "  public var species: String? { __data[\"species\"] }")
      }
      """).description

      // when
      try await buildSubjectAndOperation(
        fieldMerging: test.0
      )

      let allAnimals_asDog_predator = try XCTUnwrap(
        operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]
      )

      let actual = subject.test_render(
        childEntity: allAnimals_asDog_predator.selectionSet!.computed
      )

      // then
      expect(actual).to(equalLineByLine(
        expected,
        atLine: test.shouldMergeField ? 16 : 15,
        ignoringExtraLines: false))
    }
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_namedFragments__givenEntityFieldMergedFromNamedFragment_rendersFieldAsTypealiasToEntityInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        species
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
      }
    }
    """

    let expected = "public typealias Predator = PredatorDetails.Predator"

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .namedFragments
    )

    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_namedFragments__givenEntityFieldMergedFromMultipleNamedFragments_rendersChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ...PredatorName
        species
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
        predator {
          species
        }
      }
    }

    fragment PredatorName on Animal {
      predator {
        name
        predator {
          name
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.Predator
    public struct Predator: TestSchema.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.AllAnimal.Predator.self,
        PredatorDetails.Predator.self,
        PredatorName.Predator.self
      ] }

      public var species: String? { __data["species"] }
      public var predator: Predator? { __data["predator"] }
      public var name: String? { __data["name"] }

      /// AllAnimal.Predator.Predator
      public struct Predator: TestSchema.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.Predator.Predator.self,
          PredatorDetails.Predator.Predator.self,
          PredatorName.Predator.Predator.self
        ] }
    
        public var species: String? { __data["species"] }
        public var name: String? { __data["name"] }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .namedFragments
    )

    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_namedFragments__givenEntityFieldMergedFromNamedFragment_withMatchingInlineFragments_doesNotRenderChildSelectionSet() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ...PredatorName
        species
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
        ... on Dog {
          name
        }
      }
    }

    fragment PredatorName on Animal {
      predator {
        name
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.Predator
    public struct Predator: TestSchema.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.AllAnimal.Predator.self,
        PredatorDetails.Predator.self,
        PredatorName.Predator.self
      ] }

      public var species: String? { __data["species"] }
      public var name: String? { __data["name"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.namedFragments]
    )

    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render_childEntitySelectionSet__givenFieldMerging_namedFragmentsAndAncestors__givenEntityFieldMergedFromMultipleNamedFragment_withMatchingInlineFragmentsInBoth_rendersChildSelectionSets() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        ...PredatorName
        species
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        species
        ... on Dog {
          name
        }
      }
    }

    fragment PredatorName on Animal {
      predator {
        name
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = """
    /// AllAnimal.Predator
    public struct Predator: TestSchema.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        TestOperationQuery.Data.AllAnimal.Predator.self,
        PredatorDetails.Predator.self,
        PredatorName.Predator.self
      ] }

      public var species: String? { __data["species"] }
      public var name: String? { __data["name"] }

      public var asDog: AsDog? { _asInlineFragment() }

      /// AllAnimal.Predator.AsDog
      public struct AsDog: TestSchema.InlineFragment, ApolloAPI.CompositeInlineFragment {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public typealias RootEntityType = TestOperationQuery.Data.AllAnimal.Predator
        public static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Dog }
        public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
          PredatorDetails.Predator.self,
          PredatorDetails.Predator.AsDog.self,
          PredatorName.Predator.self,
          PredatorName.Predator.AsDog.self
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.Predator.self,
          TestOperationQuery.Data.AllAnimal.Predator.AsDog.self,
          PredatorDetails.Predator.self,
          PredatorDetails.Predator.AsDog.self,
          PredatorName.Predator.self,
          PredatorName.Predator.AsDog.self
        ] }

        public var species: String? { __data["species"] }
        public var name: String? { __data["name"] }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: [.namedFragments, .ancestors]
    )

    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: - Child Entity Selection Set - From Union In Named Fragment

  func test__render_childEntitySelectionSet__givenFieldMerging_all__givenEntityFieldMergedFromNamedFragment_rendersFieldAsTypealiasToEntityInFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Carnivore
      name: String
    }

    union Carnivore = Dog
    """

    document = """
    query TestOperation {
      allAnimals {
        ...PredatorDetails
        species
      }
    }

    fragment PredatorDetails on Animal {
      predator {
        ... on Dog {
          species
        }
      }
    }
    """

    let expected = "public typealias Predator = PredatorDetails.Predator"

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .all
    )

    let allAnimals_predator = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[field: "predator"]
    )

    let actual = subject.test_render(childEntity: allAnimals_predator.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: - Named Fragment Accessors

  func test__render_fragmentAccessors__givenFieldMerging_ancestors__givenEntityFieldMergedFromNamedFragmentInAncestor_rendersFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...AnimalDetails
        ... on Dog {
          name
        }
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected = """
      public var name: String? { __data["name"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var animalDetails: AnimalDetails { _toFragment() }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessors__givenFieldMerging_siblings__givenEntityFieldMergedFromNamedFragmentInAncestor_doesNotRenderFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ...AnimalDetails
        ... on Dog {
          name
        }
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected = """
      public var name: String? { __data["name"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessors__givenFieldMerging_siblings__givenEntityFieldMergedFromNamedFragmentInSibling_rendersFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          ...AnimalDetails
        }
        ... on Dog {
          name
        }
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected = """
      public var name: String? { __data["name"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var animalDetails: AnimalDetails { _toFragment() }
      }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .siblings
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_fragmentAccessors__givenFieldMerging_ancestors__givenEntityFieldMergedFromNamedFragmentInSibling_doesNotRenderFragmentAccessor() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal
      name: String
    }

    interface Pet implements Animal {
      species: String
      predator: Animal
    }

    type Dog implements Animal & Pet {
      species: String
      predator: Animal
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        ... on Pet {
          ...AnimalDetails
        }
        ... on Dog {
          name
        }
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    let expected = """
      public var name: String? { __data["name"] }
    }
    """

    // when
    try await buildSubjectAndOperation(
      fieldMerging: .ancestors
    )

    let allAnimals_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Dog"]
    )

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 16, ignoringExtraLines: true))
  }

}
