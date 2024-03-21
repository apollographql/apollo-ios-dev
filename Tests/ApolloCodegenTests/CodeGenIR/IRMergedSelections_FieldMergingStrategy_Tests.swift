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

  func test__mergingStrategy_ancestors__givenFieldInAncestor_includesField() async throws {
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
