import ApolloCodegenInternalTestHelpers
import IR
import Nimble
import XCTest

@testable import ApolloCodegenLib

class SelectionSetTemplate_FulfilledAndDeferredFragment_Tests: XCTestCase {

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

  func test__render_givenSelectionSet_fulfilledFragmentsIncludeSelf() async throws {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.selectionSet!.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_givenSelectionSetOnUnionType_fulfilledFragmentsIncludeUnion() async throws {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsAnimalUnion.self,
          TestOperationQuery.Data.AllAnimal.AsAnimalUnion.AsDog.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asAnimalUnion_asDog = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "AnimalUnion"]?[as: "Dog"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asAnimalUnion_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func
    test__render_givenNestedTypeCaseSelectionSetOnInterfaceTypeNotInheritingFromParentInterface_fulfilledFragmentsIncludesAllTypeCasesInScope()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsPet.self,
          TestOperationQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asPet_asWarmBlooded = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet_asWarmBlooded.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsCat.self,
          TestOperationQuery.Data.AllAnimal.AsPet.self,
          TestOperationQuery.Data.AllAnimal.AsPet.AsWarmBlooded.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asCat = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Cat"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asCat.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: - Named Fragment Tests

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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          AnimalDetails.self
        ] }
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

  func test__render_givenNamedFragmentSelectionNestedInNamedFragment_fulfilledFragmentsIncludesNamedFragment()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          AnimalDetails.self,
          Fragment2.self
        ] }
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

  func test__render_givenTypeCaseWithNamedFragmentMergedFromParent_fulfilledFragmentsIncludesNamedFragment()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsPet.self,
          AnimalDetails.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_asPet = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragmentWithNonMatchingType_fulfilledFragmentsOnlyIncludesNamedFragmentOnTypeCase()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
      """

    let allAnimals_asPet_expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsPet.self,
          AnimalDetails.self
        ] }
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
    expect(allAnimals_actual).to(
      equalLineByLine(
        allAnimals_expected,
        atLine: 13,
        ignoringExtraLines: true
      )
    )

    expect(allAnimals_asPet_actual).to(
      equalLineByLine(
        allAnimals_asPet_expected,
        atLine: 13,
        ignoringExtraLines: true
      )
    )
  }

  /// Verifies the fix for [#2989](https://github.com/apollographql/apollo-ios/issues/2989).
  ///
  /// When a fragment merges a type case from another fragment, the initializer at that type case
  /// scope needs to include both the root and type case selection sets of the merged fragment.
  ///
  /// In this test, we are verifying that the `PredatorFragment.AsPet` selection set is included in
  /// `fulfilledFragments`.
  func
    test__render_givenNamedFragmentReferencingNamedFragmentInitializedAsTypeCaseFromChildFragment_fulfilledFragmentsIncludesChildFragmentTypeCase()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          Fragment1.Predator.self,
          Fragment1.Predator.AsPet.self,
          PredatorFragment.self,
          PredatorFragment.AsPet.self,
          PetFragment.self
        ] }
      """

    // when
    let fragment = try await buildSubjectAndFragment(named: "Fragment1")

    let predators_asPet = try XCTUnwrap(
      fragment[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 15, ignoringExtraLines: true))
  }

  /// Verifies fix for [#2989](https://github.com/apollographql/apollo-ios/issues/2989).
  ///
  /// When a fragment merges a type case from another fragment, the initializer at that type case
  /// scope needs to include both the root and type case selection sets of the merged fragment.
  ///
  /// In this test, we are verifying that the `PredatorFragment.Predator.AsPet` selection set is included in
  /// `fulfilledFragments`.
  func
    test__render_givenNamedFragmentWithNestedFieldMergedFromChildNamedFragmentInitializedAsTypeCaseFromChildFragment_fulfilledFragmentsIncludesChildFragmentTypeCase()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          Fragment1.Predator.self,
          Fragment1.Predator.AsPet.self,
          PredatorFragment.Predator.self,
          PredatorFragment.Predator.AsPet.self,
          PetFragment.self
        ] }
      """

    // when
    let fragment = try await buildSubjectAndFragment(named: "Fragment1")

    let predators_asPet = try XCTUnwrap(
      fragment[field: "predators"]?[as: "Pet"]
    )

    let actual = subject.test_render(inlineFragment: predators_asPet.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  // MARK - Include/Skip

  func test__render_given_inlineFragmentWithInclusionCondition_fulfilledFragmentsIncludeParent() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.IfA.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithMultipleInclusionConditions_rendersInitializerWithFulfilledFragments()
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.IfAAndNotB.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a" && !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render_given_inlineFragmentWithNestedInclusionConditions_rendersInitializerWithFulfilledFragments()
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.IfA.self,
          TestOperationQuery.Data.AllAnimal.IfA.IfNotB.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]?[if: !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func
    test__render_given_inlineFragmentWithInclusionConditionNestedInEntityWithOtherInclusionCondition_rendersInitializerWithFulfilledFragments()
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.IfA.Friend.self,
          TestOperationQuery.Data.AllAnimal.IfA.Friend.IfNotB.self
        ] }
      """

    // when
    try await buildSubjectAndOperation()

    let allAnimals_friend = try XCTUnwrap(
      operation[field: "query"]?[field: "allAnimals"]?[if: "a"]?[field: "friend"]?[if: !"b"]
    )

    let actual = subject.test_render(inlineFragment: allAnimals_friend.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  // MARK: - Named Fragment & Include/Skip Tests

  func
    test__render_givenNamedFragmentWithInclusionCondition_fulfilledFragmentsOnlyIncludesNamedFragmentOnInlineFragmentForInclusionCondition()
    async throws
  {
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
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
      """

    let allAnimals_ifA_expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.IfA.self,
          AnimalDetails.self
        ] }
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
    expect(allAnimals_actual).to(
      equalLineByLine(
        allAnimals_expected,
        atLine: 13,
        ignoringExtraLines: true
      )
    )
    expect(allAnimals_ifA_actual).to(
      equalLineByLine(
        allAnimals_ifA_expected,
        atLine: 13,
        ignoringExtraLines: true
      )
    )
  }

  // MARK: - Defer Tests

  func test__render__givenDeferredInlineFragmentWithoutTypeCase_deferredFragmentsIncludesFragment() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.SlowSpecies.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnSameTypeCase_deferredFragmentsIncludesFragment() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.SlowSpecies.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_deferredFragmentsIsInTypeCase() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsDog.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.AsDog.SlowSpecies.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render__givenSiblingDeferredInlineFragmentsOnSameTypeCase_deferredFragmentsIncludeBothFragments()
    async throws
  {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsDog.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.AsDog.SlowSpecies.self,
          TestOperationQuery.Data.AllAnimal.AsDog.SlowGenus.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render__givenNestedDeferredInlineFragments_rendersDeferredFragments() async throws {
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

    let expected_asDog =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsDog.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.AsDog.Outer.self
        ] }
      """

    let expected_asDog_deferredOuter_Friend_asCat =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.self,
          TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.AsCat.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          TestOperationQuery.Data.AllAnimal.AsDog.Outer.Friend.AsCat.Inner.self
        ] }
      """

    let actual_asDog = subject.test_render(childEntity: allAnimals_asDog.computed)
    let actual_asDog_deferredOuter_Friend_asCat = subject.test_render(
      childEntity: allAnimals_asDog_deferredOuter_Friend_asCat.computed
    )

    // then
    expect(actual_asDog).to(equalLineByLine(expected_asDog, atLine: 13, ignoringExtraLines: true))
    expect(actual_asDog_deferredOuter_Friend_asCat).to(
      equalLineByLine(expected_asDog_deferredOuter_Friend_asCat, atLine: 13, ignoringExtraLines: true)
    )
  }

  func test__render__givenDeferredNamedFragmentOnSameTypeCase_rendersDeferredFragments() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          AnimalFragment.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 14, ignoringExtraLines: true))
  }

  func test__render__givenDeferredNamedFragmentOnDifferentTypeCase_rendersDeferredFragments() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TestOperationQuery.Data.AllAnimal.self,
          TestOperationQuery.Data.AllAnimal.AsDog.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          DogFragment.self
        ] }
      """

    let actual = subject.test_render(childEntity: allAnimals_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragment_insideNamedFragment_rendersDeferredFragments() async throws {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DogFragment.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          DogFragment.SlowSpecies.self
        ] }
      """

    let actual = subject.test_render(inlineFragment: fragment_rootField.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }

  func test__render__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_rendersDeferredFragments()
    async throws
  {
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

    let expected =
      """
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DogFragment.self,
          DogFragment.AsDog.self
        ] }
        public static var __deferredFragments: [any ApolloAPI.Deferred.Type] { [
          DogFragment.AsDog.SlowSpecies.self
        ] }
      """

    let actual = subject.test_render(inlineFragment: fragment_asDog.computed)

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 13, ignoringExtraLines: true))
  }
}
