import XCTest
import Nimble
import IR
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
    warningsOnDeprecatedUsage: ApolloCodegenConfiguration.Composition = .exclude,
    conversionStrategies: ApolloCodegenConfiguration.ConversionStrategies = .init(),
    cocoapodsImportStatements: Bool = false
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition, mergingStrategy: fieldMerging.options)
    let config = ApolloCodegen.ConfigurationContext(config: .mock(
      schemaNamespace: "TestSchema",
      output: configOutput,
      options: .init(
        additionalInflectionRules: inflectionRules,
        schemaDocumentation: schemaDocumentation,
        fieldMerging: fieldMerging,
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
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 11, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 11, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
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
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }
}
