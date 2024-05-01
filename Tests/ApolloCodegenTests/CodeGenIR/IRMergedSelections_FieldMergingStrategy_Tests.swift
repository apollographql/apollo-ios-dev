import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
@testable import IR
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
import ApolloAPI

class IRMergedSelections_FieldMergingStrategy_Tests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: CompilationResult.OperationDefinition!
  var rootField: IRTestWrapper<IR.Field>!

  var schema: IR.Schema { ir.schema }

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    operation = nil
    rootField = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildRootField(
    mergingStrategy: IR.MergedSelections.MergingStrategy
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    operation = try XCTUnwrap(ir.compilationResult.operations.first)

    rootField = await ir.build(
      operation: operation,
      mergingStrategy: mergingStrategy
    ).rootField
  }

  // MARK: - Test MergingStrategy: Ancestors

  func test__mergingStrategy_ancestors__givenFieldInParent_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field:"allAnimals"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenFieldInNestedAncestor_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
      bark: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])
    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]),
        try .mock(rootField[field: "allAnimals"]?[as: "Pet"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenMatchingTypeCaseInNestedParent_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    interface HousePet implements Pet & Animal {
      species: String
      petName: String
      houseTrained: Boolean
    }

    type Dog implements Animal & HousePet {
      species: String
      petName: String
      bark: Boolean
      houseTrained: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
          ... on HousePet {
            houseTrained
          }
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])
    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]),
        try .mock(rootField[field: "allAnimals"]?[as: "Pet"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenFieldInSiblingInlineFragmentThatMatchesType_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Dog {
          species
        }
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asDog = rootField[field: "allAnimals"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenExactMatchingTypeCaseInNestedAncestor_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
      bark: Boolean
      bite: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Dog {
          bite
        }
        ... on Pet {
          petName
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])
    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .field("petName", type: .scalar(Scalar_String)),
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]),
        try .mock(rootField[field: "allAnimals"]?[as: "Pet"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenConditionalInlineFragment_fieldInParent_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... @include(if: $a) {
          name
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_ifA = rootField[field: "allAnimals"]?[if: "a"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      inclusionConditions: [.include(if: "a")],
      directSelections: [
        .field("name", type: .scalar(Scalar_String))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field:"allAnimals"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_ifA).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenNamedFragment_doesNotIncludeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let DetailsFragment = try unwrap(self.rootField[field: "allAnimals"]?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals?.selectionSet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenNamedFragmentInParent_includesFragment_doesNotIncludeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
        ... on Pet {
          petName
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let AllAnimals_asPet = AllAnimals?[as: "Pet"]
    let DetailsFragment = try unwrap(self.rootField[field: "allAnimals"]?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSources: [
        try .mock(AllAnimals)
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  // MARK: - Siblings

  func test__mergingStrategy_siblings__givenFieldInParent_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenFieldInNestedAncestor_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
      bark: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenMatchingSiblingTypeCaseInParent_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Dog {
          species
        }
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asDog = rootField[field: "allAnimals"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSelections: [
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]?[as: "Pet"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenMatchingSiblingTypeCaseInNestedParent_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    interface HousePet implements Pet & Animal {
      species: String
      petName: String
      houseTrained: Boolean
    }

    type Dog implements Animal & HousePet {
      species: String
      petName: String
      bark: Boolean
      houseTrained: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
          ... on HousePet {
            houseTrained
          }
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [
        .field("houseTrained", type: .scalar(Scalar_Bool)),
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]?[as: "Pet"]?[as: "HousePet"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenExactMatchingTypeCaseInNestedAncestor_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
      bark: Boolean
      bite: Boolean
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Dog {
          bite
        }
        ... on Pet {
          petName
          ... on Dog {
            bark
          }
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_Bool = try unwrap(self.schema[scalar: "Boolean"])

    // when
    let AllAnimals_asPet_asDog = rootField[field: "allAnimals"]?[as: "Pet"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("bark", type: .scalar(Scalar_Bool))
      ],
      mergedSelections: [
        .field("bite", type: .scalar(Scalar_Bool)),
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]?[as: "Dog"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_asDog).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenConditionalInlineFragment_fieldInParent_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... @include(if: $a) {
          name
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_ifA = rootField[field: "allAnimals"]?[if: "a"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      inclusionConditions: [.include(if: "a")],
      directSelections: [
        .field("name", type: .scalar(Scalar_String))
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_ifA).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenNamedFragment_doesNotIncludeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let DetailsFragment = try unwrap(self.rootField[field: "allAnimals"]?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals?.selectionSet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_siblings__givenNamedFragmentInParent_doesNotIncludeFragmentOrFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
        ... on Pet {
          petName
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .siblings

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let AllAnimals_asPet = AllAnimals?[as: "Pet"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  // MARK: - Named Fragments

  func test__mergingStrategy_namedFragments__givenNamedFragment_includesFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .namedFragments

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let DetailsFragment = try unwrap(self.rootField[field: "allAnimals"]?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSelections: [
        .field("name", type: .scalar(Scalar_String)),
      ],
      mergedSources: [
        try .mock(DetailsFragment)
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals?.selectionSet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_namedFragments__givenNamedFragmentInNestedTypeCaseWithMatchingButNotExactTypeOfFragment_includesFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          ...Details
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .namedFragments

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]
    let DetailsFragment = try unwrap(AllAnimals_asPet?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSelections: [
        .field("name", type: .scalar(Scalar_String)),
      ],
      mergedSources: [
        try .mock(DetailsFragment)
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_namedFragments__givenNamedFragmentInParent_doesNotIncludeFragmentOrFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
        ... on Pet {
          petName
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .namedFragments

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let AllAnimals_asPet = AllAnimals?[as: "Pet"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_namedFragments__givenNamedFragmentOnSameEntityNestedInParent_doesNotIncludeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    interface Pet implements Animal {
      species: String
      petName: String
      bestFriend: Animal
    }
    """

    document = """
    query Test {
      allAnimals {
        bestFriend {
          ...Details
        }
        ... on Pet {
          bestFriend {
            species
          }
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .namedFragments

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet_bestFriend = rootField[field: "allAnimals"]?[as: "Pet"]?[field: "bestFriend"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_bestFriend?.selectionSet).to(shallowlyMatch(expected))
  }

  // MARK: - Named Fragments & Ancestors
  func test__mergingStrategy_namedFragments_ancestors__givenNamedFragmentInParent_includesFragmentAndFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ...Details
        ... on Pet {
          petName
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = [.namedFragments, .ancestors]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals = rootField[field: "allAnimals"]
    let AllAnimals_asPet = AllAnimals?[as: "Pet"]
    let DetailsFragment = try unwrap(self.rootField[field: "allAnimals"]?[fragment: "Details"])

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String)),
        .field("name", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition)
      ],
      mergedSources: [
        try .mock(AllAnimals),
        try .mock(DetailsFragment)
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_namedFragments_ancestors__givenNamedFragmentOnSameEntityNestedInParent_doesNotIncludeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    interface Pet implements Animal {
      species: String
      petName: String
      bestFriend: Animal
    }
    """

    document = """
    query Test {
      allAnimals {
        bestFriend {
          ...Details
        }
        ... on Pet {
          bestFriend {
            species
          }
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = [.namedFragments, .ancestors]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]
    let AllAnimals_asPet_bestFriend = AllAnimals_asPet?[field: "bestFriend"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_bestFriend?.selectionSet).to(shallowlyMatch(expected))
  }

  // MARK: - Named Fragments & Sibling

  func test__mergingStrategy_namedFragments_siblings__givenNamedFragmentOnSameEntityNestedInParent_includeFieldsFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    interface Pet implements Animal {
      species: String
      petName: String
      bestFriend: Animal
    }
    """

    document = """
    query Test {
      allAnimals {
        bestFriend {
          ...Details
        }
        ... on Pet {
          bestFriend {
            species
          }
        }
      }
    }

    fragment Details on Animal {
      name
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = [.namedFragments, .siblings]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]
    let AllAnimals_asPet_bestFriend = AllAnimals_asPet?[field: "bestFriend"]
    let DetailsFragment = try unwrap(
      self.rootField[field: "allAnimals"]?[field: "bestFriend"]?[fragment: "Details"]
    )
    
    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Animal"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [
        .field("name", type: .scalar(Scalar_String)),
        .fragmentSpread(DetailsFragment.definition),
      ],
      mergedSources: [
        try .mock(rootField[field: "allAnimals"]?[field: "bestFriend"]),
        try .mock(DetailsFragment)
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet_bestFriend?.selectionSet).to(shallowlyMatch(expected))
  }

  // MARK: - Composite Inline Fragments - From Siblings

  func test__mergingStrategy_siblings__givenMergedTypeCaseFromSiblingAsCompositeInlineFragment_includeCompositeInlineFragment() async throws {
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

    let mergingStrategy: MergedSelections.MergingStrategy = [.siblings]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])
    let Interface_Animal = try unwrap(self.schema[interface: "Animal"])
    let Interface_Pet = try unwrap(self.schema[interface: "Pet"])

    // when
    let allAnimals_asDog_predator = try XCTUnwrap(
      rootField[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]
    )

    let allAnimals_asDog_predator_asPet = try XCTUnwrap(
      allAnimals_asDog_predator[as: "Pet"]
    )

    let expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [
        .inlineFragment(parentType: Interface_Pet)
      ],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    let expected_asPet = SelectionSetMatcher(
      parentType: Interface_Pet,
      directSelections: nil,
      mergedSelections: [
        .field("name", type: .scalar(Scalar_String)),
      ],
      mergedSources: [try .mock(rootField[field: "allAnimals"]?[field: "predator"]?[as: "Pet"])],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(allAnimals_asDog_predator.selectionSet).to(shallowlyMatch(expected))
    expect(allAnimals_asDog_predator_asPet).to(shallowlyMatch(expected_asPet))
  }

  func test__mergingStrategy_ancestors__givenMergedTypeCaseFromSiblingAsCompositeInlineFragment_doesNotIncludeCompositeInlineFragment() async throws {
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

    let mergingStrategy: MergedSelections.MergingStrategy = [.ancestors]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])
    let Interface_Animal = try unwrap(self.schema[interface: "Animal"])

    // when
    let allAnimals_asDog_predator = try XCTUnwrap(
      rootField[field: "allAnimals"]?[as: "Dog"]?[field: "predator"]
    )

    let expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .field("species", type: .scalar(Scalar_String)),
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(allAnimals_asDog_predator.selectionSet).to(shallowlyMatch(expected))
  }

  // MARK: - Composite Inline Fragments - From Named Fragment

  func test__mergingStrategy_namedFragments__givenNamedFragmentOnUnionWithTypeCase_includeFieldsInTypeCaseFromFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [ClassroomPet!]
    }

    interface Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    type Dog implements Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    type Cat implements Animal {
      species: String
      name: String
      bestFriend: Animal
    }

    union ClassroomPet = Dog | Cat
    """

    document = """
    query Test {
      allAnimals {
        ...Details
      }
    }

    fragment Details on ClassroomPet {
      ... on Dog {
        name
      }
      ... on Cat {
        species
      }
    }
    """

    let mergingStrategy: MergedSelections.MergingStrategy = [.namedFragments]

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asDog = try unwrap(
      self.rootField[field: "allAnimals"]?[as: "Dog"]
    )
    let AllAnimals_asCat = try unwrap(
      self.rootField[field: "allAnimals"]?[as: "Cat"]
    )

    let DetailsFragment = try unwrap(
      self.rootField[field: "allAnimals"]?[fragment: "Details"]
    )

    let expected_asDog = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: nil,
      mergedSelections: [
        .field("name", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        .init(
          typeInfo: DetailsFragment[as: "Dog"]!.typeInfo,
          fragment: DetailsFragment.fragment
        )
      ],
      mergingStrategy: mergingStrategy
    )

    let expected_asCat = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Cat"]),
      directSelections: nil,
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        .init(
          typeInfo: DetailsFragment[as: "Cat"]!.typeInfo,
          fragment: DetailsFragment.fragment
        )
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asDog).to(shallowlyMatch(expected_asDog))
    expect(AllAnimals_asCat).to(shallowlyMatch(expected_asCat))
  }

}
