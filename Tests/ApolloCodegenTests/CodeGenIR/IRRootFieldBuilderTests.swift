import XCTest
import Nimble
import OrderedCollections
import Utilities
import GraphQLCompiler
@testable import IR
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
import ApolloAPI

class IRRootFieldBuilderTests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: CompilationResult.OperationDefinition!
  var result: IRTestWrapper<IR.Operation>!
  var subject: IRTestWrapper<IR.Field>!

  var computedReferencedFragments: IR.RootFieldBuilder.ReferencedFragments! {
    result.referencedFragments
  }

  var schema: IR.Schema { ir.schema }

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    operation = nil
    subject = nil
    result = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildSubjectRootField(operationName: String? = nil) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    if let operationName {
      operation = try XCTUnwrap(ir.compilationResult.operations.first(
        where: { $0.name == operationName }
      ))
    } else {
      operation = try XCTUnwrap(ir.compilationResult.operations.first)
    }
    result = await ir.build(operation: operation)
    subject = result.rootField
  }

  // MARK: - Children Computation

  // MARK: Children - Fragment Type

  func test__children__initWithNamedFragmentOnTheSameType_hasNoChildTypeCase() async throws {
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
    query Test {
      allAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = self.subject[field: "allAnimals"]?.selectionSet

    // then
    expect(allAnimals?.computed.direct?.inlineFragments).to(beEmpty())
  }

  func test__children__initWithNamedFragmentOnMoreSpecificType_hasChildTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    type Bird implements Animal {
      species: String!
    }
    """

    document = """
    query Test {
      allAnimals {
        ...BirdDetails
      }
    }

    fragment BirdDetails on Bird {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])
    let Fragment_BirdDetails = try XCTUnwrap(ir.compilationResult[fragment: "BirdDetails"])

    let allAnimals = self.subject[field: "allAnimals"]?.selectionSet

    // then
    expect(allAnimals?.computed.direct?.inlineFragments.count).to(equal(1))

    let child = allAnimals?[as: "Bird"]
    expect(child?.parentType).to(equal(Object_Bird))
    expect(child?.computed.direct?.namedFragments.values).to(shallowlyMatch([Fragment_BirdDetails]))
  }

  func test__children__isObjectType_initWithNamedFragmentOnLessSpecificMatchingType_hasNoChildTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      birds: [Bird!]
    }

    interface Animal {
      species: String!
    }

    type Bird implements Animal {
      species: String!
    }
    """

    document = """
    query Test {
      birds {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let birds = self.subject[field: "birds"]?.selectionSet

    // then
    expect(birds?.computed.direct?.inlineFragments).to(beEmpty())
  }

  func test__children__isInterfaceType_initWithNamedFragmentOnLessSpecificMatchingType_hasNoChildTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      flyingAnimals: [FlyingAnimal!]
    }

    interface Animal {
      species: String!
    }

    interface FlyingAnimal implements Animal {
      species: String!
    }
    """

    document = """
    query Test {
      flyingAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let flyingAnimals = self.subject[field: "flyingAnimals"]?.selectionSet

    // then
    expect(flyingAnimals?.computed.direct?.inlineFragments).to(beEmpty())
  }

  func test__children__initWithNamedFragmentOnUnrelatedType_hasChildTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      rocks: [Rock!]
    }

    interface Animal {
      species: String!
    }

    type Rock {
      name: String!
    }
    """

    document = """
    query Test {
     rocks {
       ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Fragment_AnimalDetails = try XCTUnwrap(ir.compilationResult[fragment: "AnimalDetails"])

    let rocks = self.subject[field: "rocks"]?.selectionSet

    // then
    expect(rocks?.computed.direct?.inlineFragments.count).to(equal(1))

    let child = rocks?[as: "Animal"]
    expect(child?.parentType).to(equal(Interface_Animal))
    expect(child?.computed.direct?.namedFragments.count).to(equal(1))
    expect(child?.computed.direct?.namedFragments.values[0].definition).to(equal(Fragment_AnimalDetails))
  }

  // MARK: Children Computation - Union Type

  func test__children__givenIsUnionType_withNestedTypeCaseOfObjectType_hasChildrenForTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    type Bird {
      species: String!
    }

    union ClassroomPet = Bird
    """

    document = """
    query Test {
      allAnimals {
        ... on ClassroomPet {
          ... on Bird {
            species
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])
    let Union_ClassroomPet = try XCTUnwrap(schema[union: "ClassroomPet"])

    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Field_Species: ShallowFieldMatcher = .mock(
      "species", type: .nonNull(.scalar(Scalar_String))
    )

    let onClassroomPet = subject[field: "allAnimals"]?[as: "ClassroomPet"]
    let onClassroomPet_onBird = onClassroomPet?[as:"Bird"]

    // then
    expect(onClassroomPet?.parentType).to(beIdenticalTo(Union_ClassroomPet))
    expect(onClassroomPet?.computed.direct?.inlineFragments.count).to(equal(1))

    expect(onClassroomPet_onBird?.parentType).to(beIdenticalTo(Object_Bird))
    expect(onClassroomPet_onBird?.computed.direct?.fields.values).to(shallowlyMatch([Field_Species]))
  }

  // MARK: Children - Type Cases

  func test__children__givenInlineFragment_onSameType_mergesTypeCaseIn_doesNotHaveTypeCaseChild() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      A: String!
      B: String!
    }
    """

    document = """
    query Test {
      aField { # On A
        A
        ... on A {
          B
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct?.inlineFragments).to(beEmpty())
  }

  func test__children__givenInlineFragment_onMatchingType_mergesTypeCaseIn_doesNotHaveTypeCaseChild() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    interface A {
      A: String!
      B: String!
    }

    type B implements A {
      A: String!
      B: String!
    }
    """

    document = """
    query Test {
      bField { # On B
        A
        ... on A {
          B
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Object_B = try XCTUnwrap(schema[object: "B"])

    let bField = subject[field: "bField"]

    let expected = SelectionSetMatcher(
      parentType: Object_B,
      directSelections: [
        .field("A", type: .nonNull(.scalar(Scalar_String))),
        .field("B", type: .nonNull(.scalar(Scalar_String))),
      ]
    )

    // then
    expect(bField?.selectionSet).to(shallowlyMatch(expected))
  }

  func test__children__givenInlineFragment_onNonMatchingType_doesNotMergeTypeCaseIn_hasChildTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    interface A {
      A: String!
      B: String!
    }

    type B {
      A: String
      B: String
    }
    """

    document = """
    query Test {
      aField { # On A
        A
        ... on B {
          B
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_A = try XCTUnwrap(schema[interface: "A"])
    let Object_B = try XCTUnwrap(schema[object: "B"])
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])

    let aField = subject[field: "aField"]

    let expected = SelectionSetMatcher(
      parentType: Interface_A,
      directSelections: [
        .field("A", type: .nonNull(.scalar(Scalar_String))),
        .inlineFragment(parentType: Object_B)
      ]
    )

    let asB_expected = SelectionSetMatcher.directOnly(
      parentType: Object_B,
      directSelections: [
        .field("B", type: .scalar(Scalar_String)),
      ]
    )

    // then
    expect(aField?.selectionSet).to(shallowlyMatch(expected))
    expect(aField?[as: "B"]).to(shallowlyMatch(asB_expected))
  }

  // MARK: Children - Group Duplicate Type Cases

  func test__children__givenInlineFragmentsWithSameType_deduplicatesChildren() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    interface InterfaceA {
      A: String
      B: String
    }

    type B {
      name: String
    }
    """

    document = """
    query Test {
      bField {
        ... on InterfaceA {
          A
        }
        ... on InterfaceA {
          B
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_B = try XCTUnwrap(schema[object: "B"])
    let Interface_A = try XCTUnwrap(schema[interface: "InterfaceA"])
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])

    let bField = subject[field: "bField"]
    let bField_asInterfaceA = bField?[as: "InterfaceA"]

    let bField_expected = SelectionSetMatcher(
      parentType: Object_B,
      directSelections: [
        .inlineFragment(parentType: Interface_A),
      ]
    )

    let bField_asA_expected = SelectionSetMatcher(
      parentType: Interface_A,
      directSelections: [
        .field("A", type: .scalar(Scalar_String)),
        .field("B", type: .scalar(Scalar_String)),
      ]
    )

    // then
    expect(bField?.selectionSet).to(shallowlyMatch(bField_expected))
    expect(bField_asInterfaceA).to(shallowlyMatch(bField_asA_expected))
  }

  func test__children__givenInlineFragmentsWithDifferentType_hasSeperateChildTypeCases() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    interface InterfaceA {
      A: String
    }

    interface InterfaceB {
      B: String
    }

    type A {
      name: String
    }
    """

    document = """
    query Test {
      aField {
        ... on InterfaceA {
          A
        }
        ... on InterfaceB {
          B
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Field_A: ShallowSelectionMatcher = .field("A", type: .scalar(Scalar_String))
    let Field_B: ShallowSelectionMatcher = .field("B", type: .scalar(Scalar_String))

    let aField = subject[field: "aField"]
    let aField_asInterfaceA = aField?[as: "InterfaceA"]
    let aField_asInterfaceB = aField?[as: "InterfaceB"]

    // then
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(2))

    expect(aField_asInterfaceA?.parentType).to(equal(GraphQLInterfaceType.mock("InterfaceA")))
    expect(aField_asInterfaceA?.computed.direct).to(shallowlyMatch([Field_A]))

    expect(aField_asInterfaceB?.parentType).to(equal(GraphQLInterfaceType.mock("InterfaceB")))
    expect(aField_asInterfaceB?.computed.direct).to(shallowlyMatch([Field_B]))
  }

  // MARK: Children - Group Duplicate Fragments

  func test__children__givenDuplicateNamedFragments_onNonMatchingParentType_hasDeduplicatedTypeCaseWithChildFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [InterfaceA!]
    }

    interface InterfaceA {
      a: String
    }

    interface InterfaceB {
      b: String
    }
    """

    document = """
    fragment FragmentB on InterfaceB {
      b
    }

    query Test {
      aField {
        ... FragmentB
        ... FragmentB
      }
    }
    """
    // when
    try await buildSubjectRootField()

    let InterfaceB = try XCTUnwrap(schema[interface: "InterfaceB"])
    let FragmentB = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB"])

    let aField = subject[field: "aField"]
    let aField_asInterfaceB = aField?[as: "InterfaceB"]

    // then
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(1))

    expect(aField_asInterfaceB?.parentType).to(equal(InterfaceB))
    expect(aField_asInterfaceB?.computed.direct).to(shallowlyMatch([.fragmentSpread(FragmentB)]))
  }

  func test__children__givenTwoNamedFragments_onSameNonMatchingParentType_hasDeduplicatedTypeCaseWithBothChildFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [InterfaceA!]
    }

    interface InterfaceA {
      a: String
    }

    interface InterfaceB {
      b: String
      c: String
    }
    """

    document = """
    fragment FragmentB1 on InterfaceB {
      b
    }

    fragment FragmentB2 on InterfaceB {
      c
    }

    query Test {
      aField {
        ...FragmentB1
        ...FragmentB2
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let InterfaceB = try XCTUnwrap(schema[interface: "InterfaceB"])
    let FragmentB1 = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB1"])
    let FragmentB2 = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB2"])

    let aField = subject[field: "aField"]
    let aField_asInterfaceB = aField?[as: "InterfaceB"]

    // then
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(1))

    expect(aField_asInterfaceB?.parentType).to(equal(InterfaceB))
    expect(aField_asInterfaceB?.computed.direct).to(shallowlyMatch([
      .fragmentSpread(FragmentB1),
      .fragmentSpread(FragmentB2)
    ]))
  }

  // MARK: - Selections

  // MARK: Selections - Group Duplicate Fields

  func test__selections__givenFieldSelectionsWithSameName_scalarType_deduplicatesSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: String
    }
    """

    document = """
    query Test {
      aField {
        a
        a
      }
    }
    """

    let expected: [ShallowSelectionMatcher] = [
      .field("a", type: .string())
    ]

    // when
    try await buildSubjectRootField()

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenFieldSelectionsWithSameNameDifferentAlias_scalarType_doesNotDeduplicateSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: String
    }
    """

    document = """
    query Test {
      aField {
        b: a
        c: a
      }
    }
    """

    let expected: [ShallowSelectionMatcher] = [
      .field("a", alias: "b", type: .string()),
      .field("a", alias: "c", type: .string())
    ]

    // when
    try await buildSubjectRootField()

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenFieldSelectionsWithSameResponseKey_onObjectWithDifferentChildSelections_mergesChildSelectionsIntoOneField() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: A
      b: String
      c: Int
    }
    """

    document = """
    query Test {
      aField {
        a {
          b
        }
        a {
          c
        }
      }
    }
    """

    let expectedAFields: [ShallowSelectionMatcher] = [
      .field("b", type: .string()),
      .field("c", type: .integer())
    ]

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let aField = subject[field: "aField"]
    let aField_a = aField?[field: "a"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.count).to(equal(1))
    expect(aField?.selectionSet?.parentType).to(equal(Object_A))
    expect(aField_a?.selectionSet?.parentType).to(equal(Object_A))
    expect(aField_a?.selectionSet?.computed.direct).to(shallowlyMatch(expectedAFields))
  }

  func test__selections__givenFieldSelectionsWithSameResponseKey_onObjectWithSameAndDifferentChildSelections_mergesChildSelectionsAndDoesNotDuplicateFields() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: A
      b: Int
      c: Boolean
      d: String
    }
    """

    document = """
    query Test {
      aField {
        a {
          b
          c
        }
        a {
          b
          d
        }
      }
    }
    """

    let expectedAFields: [ShallowSelectionMatcher] = [
      .field("b", type: .integer()),
      .field("c", type: .boolean()),
      .field("d", type: .string()),
    ]

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let aField = subject[field: "aField"]
    let aField_a = aField?[field: "a"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.count).to(equal(1))
    expect(aField?.selectionSet?.parentType).to(equal(Object_A))
    expect(aField_a?.selectionSet?.parentType).to(equal(Object_A))
    expect(aField_a?.selectionSet?.computed.direct).to(shallowlyMatch(expectedAFields))
  }

  // MARK: Selections - Type Cases

  func test__selections__givenInlineFragment_onSameType_mergesTypeCaseIn() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: String
      b: Int
    }
    """

    document = """
    query Test {
      aField {
        a
        ... on A {
          b
        }
      }
    }
    """

    let expected: [ShallowSelectionMatcher] = [
      .field("a", type: .string()),
      .field("b", type: .integer()),
    ]

    // when
    try await buildSubjectRootField()

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragment_onMatchingType_mergesTypeCaseIn() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    interface A {
      a: String
    }

    type B implements A {
      a: String
      b: Int
    }
    """

    document = """
    query Test {
      bField {
        b
        ... on A {
          a
        }
      }
    }
    """

    let expected: [ShallowSelectionMatcher] = [
      .field("b", type: .integer()),
      .field("a", type: .string()),
    ]

    // when
    try await buildSubjectRootField()

    let bField = subject[field: "bField"]

    // then
    expect(bField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragment_onNonMatchingType_doesNotMergeTypeCaseIn() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    interface A {
      a: String
    }

    type B {
      a: String
      b: Int
    }
    """

    document = """
    query Test {
      aField {
        a
        ... on B {
          b
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let aField = subject[field: "aField"]
    let aField_asB = aField?[as: "B"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.values).to(shallowlyMatch([
      .field("a", type: .string())
    ]))
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(1))

    expect(aField_asB?.computed.direct).to(shallowlyMatch([
      .field("b", type: .integer())
    ]))
  }

  // MARK: Selections - Group Duplicate Type Cases

  func test__selections__givenInlineFragmentsWithSameInterfaceType_deduplicatesSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    interface A {
      a: String
    }

    type B {
      b: Int
    }
    """

    document = """
    query Test {
      bField {
        ... on A { a }
        ... on A { a }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_A = try XCTUnwrap(schema[interface: "A"])

    let expected: [ShallowSelectionMatcher] = [
      .inlineFragment(parentType: Interface_A)
    ]

    let bField = subject[field: "bField"]

    // then
    expect(bField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragmentsWithSameInterfaceType_deduplicatesTypeCaseMergesSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    interface A {
      a: String
      b: Int
    }

    type B {
      c: Int
    }
    """

    document = """
    query Test {
      bField {
        ... on A { a }
        ... on A { b }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected: [ShallowSelectionMatcher] = [
      .field("a", type: .string()),
      .field("b", type: .integer())
    ]

    let actual = subject[field: "bField"]?[as: "A"]

    // then
    expect(actual?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragmentsWithSameObjectType_deduplicatesSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    type A {
      a: String
    }

    type B {
      b: Int
    }
    """

    document = """
    query Test {
      bField {
        ... on A { a }
        ... on A { a }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let expected: [ShallowSelectionMatcher] = [
      .inlineFragment(parentType: Object_A)
    ]

    let bField = subject[field: "bField"]

    // then
    expect(bField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragmentsWithSameUnionType_deduplicatesSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      bField: [B!]
    }

    type A {
      a1: String
      a2: String
    }

    union UnionA = A

    type B {
      b: Int
    }
    """

    document = """
    query Test {
      bField {
        ... on UnionA { ...on A { a1 } }
        ... on UnionA { ...on A { a2 } }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Union_A = try XCTUnwrap(schema[union: "UnionA"])

    let expected: [ShallowSelectionMatcher] = [
      .inlineFragment(parentType: Union_A)
    ]

    let bField = subject[field: "bField"]

    // then
    expect(bField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragmentsWithDifferentType_doesNotDeduplicateSelection() async throws {
    schemaSDL = """
    type Query {
      objField: [Object!]
    }

    type Object {
      name: String
    }

    interface A {
      a: String
    }

    interface B {
      b: String
    }
    """

    document = """
    query Test {
      objField {
        ... on A { a }
        ... on B { b }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_A = try XCTUnwrap(schema[interface: "A"])
    let Interface_B = try XCTUnwrap(schema[interface: "B"])

    let expected: [ShallowSelectionMatcher] = [
      .inlineFragment(parentType: Interface_A),
      .inlineFragment(parentType: Interface_B),
    ]

    let objField = subject[field: "objField"]

    // then
    expect(objField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenInlineFragmentsWithSameType_withSameAndDifferentChildSelections_mergesChildSelectionsIntoOneTypeCaseAndDeduplicatesChildSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: A
    }

    interface B {
      b: Int
      c: Boolean
      d: String
    }
    """

    document = """
    query Test {
      aField {
        ... on B {
          b
          c
        }
        ... on B {
          b
          d
        }
      }
    }
    """

    let expected: [ShallowSelectionMatcher] = [
      .field("b", type: .integer()),
      .field("c", type: .boolean()),
      .field("d", type: .string()),
    ]

    // when
    try await buildSubjectRootField()

    let Interface_B = try XCTUnwrap(schema[interface:"B"])

    let aField = subject[field: "aField"]
    let aField_asB = aField?[as: "B"]

    // then
    expect(aField_asB?.parentType).to(equal(Interface_B))
    expect(aField_asB?.computed.direct).to(shallowlyMatch(expected))
  }

  // MARK: Selections - Fragments

  func test__selections__givenNamedFragmentWithSelectionSet_onMatchingParentType_hasFragmentSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }
    """

    document = """
    fragment FragmentA on A {
      a
    }

    query Test {
      aField {
        ...FragmentA
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let expected: [ShallowSelectionMatcher] = [
      .fragmentSpread("FragmentA", type: Object_A),
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  // MARK: Selections - Group Duplicate Fragments

  func test__selections__givenNamedFragmentsWithSameName_onMatchingParentType_deduplicatesSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }
    """

    document = """
    fragment FragmentA on A {
      a
    }

    query Test {
      aField {
        ...FragmentA
        ...FragmentA
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let expected: [ShallowSelectionMatcher] = [
      .fragmentSpread("FragmentA", type: Object_A),
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenNamedFragmentsWithDifferentNames_onMatchingParentType_doesNotDeduplicateSelection() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
      b: String
    }
    """

    document = """
    fragment FragmentA1 on A {
      a
    }

    fragment FragmentA2 on A {
      b
    }

    query Test {
      aField {
        ...FragmentA1
        ...FragmentA2
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_A = try XCTUnwrap(schema[object: "A"])

    let expected: [ShallowSelectionMatcher] = [
      .fragmentSpread("FragmentA1", type: Object_A),
      .fragmentSpread("FragmentA2", type: Object_A),
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenNamedFragmentsWithSameName_onNonMatchingParentType_deduplicatesSelectionIntoSingleTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
      b: String
    }

    interface B {
      b: String
    }
    """

    document = """
    fragment FragmentB on B {
      b
    }

    query Test {
      aField {
        ...FragmentB
        ...FragmentB
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_B = try XCTUnwrap(schema[interface: "B"])

    let expected: [ShallowSelectionMatcher] = [
      .fragmentSpread("FragmentB", type: Interface_B)
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.count).to(equal(0))
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(1))
    expect(aField?[as: "B"]?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenNamedFragmentsWithDifferentNamesAndSameParentType_onNonMatchingParentType_deduplicatesSelectionIntoSingleTypeCaseWithBothFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }

    interface B {
      b1: String
      b2: String
    }
    """

    document = """
    fragment FragmentB1 on B {
      b1
    }

    fragment FragmentB2 on B {
      b2
    }

    query Test {
      aField {
        ...FragmentB1
        ...FragmentB2
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Fragment_B1 = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB1"])
    let Fragment_B2 = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB2"])

    let expected: [ShallowSelectionMatcher] = [
      .fragmentSpread(Fragment_B1),
      .fragmentSpread(Fragment_B2),
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.count).to(equal(0))
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(1))
    expect(aField?[as: "B"]?.computed.direct).to(shallowlyMatch(expected))
  }

  func test__selections__givenNamedFragmentsWithDifferentNamesAndDifferentParentType_onNonMatchingParentType_doesNotDeduplicate_hasTypeCaseForEachFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }

    interface B {
      b: String
    }

    interface C {
      c: String
    }
    """

    document = """
    fragment FragmentB on B {
      b
    }

    fragment FragmentC on C {
      c
    }

    query Test {
      aField {
        ...FragmentB
        ...FragmentC
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Fragment_B = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB"])
    let Fragment_C = try XCTUnwrap(ir.compilationResult[fragment: "FragmentC"])

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct?.fields.count).to(equal(0))
    expect(aField?.selectionSet?.computed.direct?.inlineFragments.count).to(equal(2))
    expect(aField?[as: "B"]?.computed.direct).to(shallowlyMatch([.fragmentSpread(Fragment_B)]))
    expect(aField?[as: "C"]?.computed.direct).to(shallowlyMatch([.fragmentSpread(Fragment_C)]))
  }

  // MARK: Selections - Nested Objects

  func test__selections__givenNestedObjectInRootAndTypeCase_doesNotInheritSelectionsFromRoot() async throws {
    // given
    schemaSDL = """
    type Query {
      childContainer: HasChild!
    }

    interface HasChild {
      child: Child
    }

    type Root {
      child: Child
    }

    type Child {
      a: Int
      b: Int
    }
    """

    document = """
    query Test {
      childContainer {
        child {
          a
        }
        ... on Root {
          child {
            b
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected: [ShallowSelectionMatcher] = [
      .field("b", type: .integer())
    ]

    let asRoot_child = subject[field: "childContainer"]?[as: "Root"]?[field: "child"]

    // then
    expect(asRoot_child?.selectionSet?.computed.direct).to(shallowlyMatch(expected))
  }

  // MARK: - Merged Selections

  func test__mergedSelections__givenSelectionSetWithSelections_returnsSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }
    """

    document = """
    query Test {
      aField {
        a
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected_direct: [ShallowSelectionMatcher] = [
      .field("a", type: .scalar(.integer()))
    ]
    let expected_merged: [ShallowSelectionMatcher] = [
    ]

    let aField = subject[field: "aField"]

    // then
    expect(aField?.selectionSet?.computed.direct).to(shallowlyMatch(expected_direct))
    expect(aField?.selectionSet?.computed.merged).to(shallowlyMatch(expected_merged))
  }

  func test__mergedSelections__givenSelectionSetWithSelectionsAndParentFields_returnsSelfAndParentFields() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      a: Int
    }

    type B {
      b: Int
    }
    """

    document = """
    query Test {
      aField {
        a
        ... on B {
          b
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = SelectionsMatcher(
      direct: [
        .field("b", type: .integer()),
      ],
      merged: [
        .field("a", type: .integer()),
      ],
      mergedSources: [
        try .mock(subject[field: "aField"])
      ]
    )

    let actual = subject[field: "aField"]?[as: "B"]

    // then
    expect(actual).to(shallowlyMatch(expected))
  }

  // MARK: - Merged Selections - Siblings

  // MARK: Merged Selections - Siblings - Object Type <-> Object Type

  func test__mergedSelections__givenIsObjectType_siblingSelectionSetIsDifferentObjectType_doesNotMergesSiblingSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      species: String
      wingspan: Int
    }

    type Cat implements Animal {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Bird {
          wingspan
        }
        ... on Cat {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let asBirdExpected: [ShallowSelectionMatcher] = [
      .field("wingspan", type: .integer()),
    ]
    let asCatExpected: [ShallowSelectionMatcher] = [
      .field("species", type: .string()),
    ]

    let allAnimals = subject[field: "allAnimals"]
    let asBird = allAnimals?[as: "Bird"]?.computed
    let asCat = allAnimals?[as: "Cat"]?.computed

    // then
    expect(asBird?.merged).to(beEmpty())
    expect(asBird?.direct).to(shallowlyMatch(asBirdExpected))
    expect(asCat?.merged).to(beEmpty())
    expect(asCat?.direct).to(shallowlyMatch(asCatExpected))
  }

  // MARK: Merged Selections - Siblings - Object Type -> Interface Type

  func test__mergedSelections__givenIsObjectType_siblingSelectionSetIsImplementedInterface_mergesSiblingSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      species: String
    }

    type Bird implements Pet {
      species: String
      wingspan: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Bird {
          wingspan
        }
        ... on Pet {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asBird = allAnimals?[as: "Bird"]
    let asPet = allAnimals?[as: "Pet"]

    let asBirdExpected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer()),
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(asPet)
      ]
    )

    let asPetExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )


    // then
    expect(asBird).to(shallowlyMatch(asBirdExpected))
    expect(asPet).to(shallowlyMatch(asPetExpected))
  }

  func test__mergedSelections__givenIsObjectType_siblingSelectionSetIsUnimplementedInterface_doesNotMergeSiblingSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      species: String
    }

    type Bird {
      species: String
      wingspan: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Bird {
          wingspan
        }
        ... on Pet { # Bird does not implement Pet
          species
        }
      }
    }
    """

    let asBirdExpected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer()),
      ],
      merged: [
      ]
    )

    let asPetExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asBird = allAnimals?[as: "Bird"]
    let asPet = allAnimals?[as: "Pet"]

    // then
    expect(asBird).to(shallowlyMatch(asBirdExpected))
    expect(asPet).to(shallowlyMatch(asPetExpected))
  }

  // MARK: Merged Selections - Siblings - Interface Type -> Interface Type

  func test__mergedSelections__givenIsInterfaceType_siblingSelectionSetIsImplementedInterface_mergesSiblingSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      species: String
    }

    interface HousePet implements Pet {
      species: String
      humanName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on HousePet {
          humanName
        }
        ... on Pet { # HousePet Implements Pet
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asHousePet = allAnimals?[as: "HousePet"]
    let asPet = allAnimals?[as: "Pet"]

    let asHousePetExpected = SelectionsMatcher(
      direct: [
        .field("humanName", type: .string()),
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(asPet)
      ]
    )

    let asPetExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // then
    expect(asHousePet).to(shallowlyMatch(asHousePetExpected))
    expect(asPet).to(shallowlyMatch(asPetExpected))
  }

  func test__mergedSelections__givenIsInterfaceType_siblingSelectionSetIsUnimplementedInterface_doesNotMergeSiblingSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      species: String
    }

    interface HousePet {
      humanName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on HousePet {
          humanName
        }
        ... on Pet { # HousePet does not implement Pet
          species
        }
      }
    }
    """

    let asHousePetExpected = SelectionsMatcher(
      direct: [
        .field("humanName", type: .string()),
      ],
      merged: [
      ]
    )

    let asPetExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asHousePet = allAnimals?[as: "HousePet"]
    let asPet = allAnimals?[as: "Pet"]

    // then
    expect(asHousePet).to(shallowlyMatch(asHousePetExpected))
    expect(asPet).to(shallowlyMatch(asPetExpected))
  }

  // MARK: - Merged Selections - Parent's Sibling

  func test__mergedSelections__givenIsNestedInterfaceType_uncleSelectionSetIsTheSameInterfaceType_mergesUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface WarmBlooded {
      bodyTemperature: Int
    }

    interface Pet implements Animal {
      species: String
      humanName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on WarmBlooded {
          ... on Pet {
            humanName
          }
        }
        ... on Pet {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asWarmBlooded_asPet_actual = allAnimals?[as:"WarmBlooded"]?[as: "Pet"]
    let asPet_actual = allAnimals?[as: "Pet"]

    let onWarmBlooded_onPet_expected = SelectionsMatcher(
      direct: [
        .field("humanName", type: .string()),
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(asPet_actual)
      ]
    )

    let onPet_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // then
    expect(asWarmBlooded_asPet_actual).to(shallowlyMatch(onWarmBlooded_onPet_expected))
    expect(asPet_actual).to(shallowlyMatch(onPet_expected))
  }

  func test__mergedSelections__givenIsObjectInInterfaceType_uncleSelectionSetIsMatchingInterfaceType_mergesUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface WarmBlooded {
      bodyTemperature: Int
    }

    interface Pet {
      humanName: String
      species: String
    }

    type Bird implements Pet {
      wingspan: Int
      humanName: String
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on WarmBlooded {
          ... on Bird {
            wingspan
          }
        }
        ... on Pet { # Bird Implements Pet
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asWarmBlooded_asBird_actual = allAnimals?[as: "WarmBlooded"]?[as: "Bird"]
    let asPet_actual = allAnimals?[as: "Pet"]

    let onWarmBlooded_onBird_expected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer()),
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(asPet_actual)
      ]
    )

    let onPet_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // then
    expect(asWarmBlooded_asBird_actual).to(shallowlyMatch(onWarmBlooded_onBird_expected))
    expect(asPet_actual).to(shallowlyMatch(onPet_expected))
  }

  func test__mergedSelections__givenIsObjectInInterfaceType_uncleSelectionSetIsNonMatchingInterfaceType_doesNotMergeUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface WarmBlooded {
      bodyTemperature: Int
    }

    interface Pet {
      humanName: String
      species: String
    }

    type Bird {
      wingspan: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on WarmBlooded {
          ... on Bird {
            wingspan
          }
        }
        ... on Pet { # Bird Does Not Implement Pet
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asWarmBlooded_asBird_actual = allAnimals?[as: "WarmBlooded"]?[as: "Bird"]
    let asPet_actual = allAnimals?[as: "Pet"]

    let asWarmBlooded_asBird_expected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer()),
      ],
      merged: [
      ]
    )

    let asPet_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // then
    expect(asWarmBlooded_asBird_actual).to(shallowlyMatch(asWarmBlooded_asBird_expected))
    expect(asPet_actual).to(shallowlyMatch(asPet_expected))
  }

  // MARK: Merged Selections - Parent's Sibling - Object Type <-> Object in Union Type

  func test__mergedSelections__givenIsObjectType_siblingSelectionSetIsUnionTypeWithNestedTypeCaseOfSameObjectType_mergesSiblingChildSelectionsInBothDirections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      wingspan: Int
      species: String
    }

    union ClassroomPet = Bird
    """

    document = """
    query Test {
      allAnimals {
        ... on Bird {
          wingspan
        }
        ... on ClassroomPet {
          ... on Bird {
            species
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asBirdActual = allAnimals?[as: "Bird"]
    let asClassroomPet_asBirdActual = allAnimals?[as: "ClassroomPet"]?[as: "Bird"]

    let asBirdExpected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer())
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(asClassroomPet_asBirdActual)
      ]
    )

    let asClassroomPet_asBirdExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
        .field("wingspan", type: .integer())
      ],
      mergedSources: [
        try .mock(asBirdActual)
      ]
    )

    // then
    expect(asBirdActual).to(shallowlyMatch(asBirdExpected))
    expect(asClassroomPet_asBirdActual).to(shallowlyMatch(asClassroomPet_asBirdExpected))
  }

  func test__mergedSelections__givenIsObjectType_siblingSelectionSetIsUnionTypeWithNestedTypeCaseOfDifferentObjectType_doesNotMergeSiblingChildSelectionsInEitherDirection() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      wingspan: Int
      species: String
    }

    type Cat implements Animal {
      species: String
    }

    union ClassroomPet = Bird | Cat
    """

    document = """
    query Test {
      allAnimals {
        ... on Bird {
          wingspan
        }
        ... on ClassroomPet {
          ... on Cat {
            species
          }
        }
      }
    }
    """

    let asBirdExpected = SelectionsMatcher(
      direct: [
        .field("wingspan", type: .integer())
      ],
      merged: [
      ]
    )

    let asClassroomPet_asCatExpected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let asBirdActual = allAnimals?[as: "Bird"]
    let asClassroomPet_asCatActual = allAnimals?[as: "ClassroomPet"]?[as: "Cat"]

    // then
    expect(asBirdActual).to(shallowlyMatch(asBirdExpected))
    expect(asClassroomPet_asCatActual).to(shallowlyMatch(asClassroomPet_asCatExpected))
  }

  // MARK: Merged Selections - Parent's Sibling - Interface in Union Type

  func test__mergedSelections__givenInterfaceTypeInUnion_uncleSelectionSetIsMatchingInterfaceType_mergesUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface WarmBlooded implements Animal {
      bodyTemperature: Int
      species: String
    }

    type Bird implements Animal {
      wingspan: Int
      species: String
    }

    union ClassroomPet = Bird
    """

    document = """
    query Test {
      allAnimals {
        ... on WarmBlooded {
          bodyTemperature
        }
        ... on ClassroomPet {
          ... on WarmBlooded {
            species
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asWarmBlooded_actual = allAnimals?[as: "WarmBlooded"]
    let asClassroomPet_asWarmBlooded_actual = allAnimals?[as: "ClassroomPet"]?[as: "WarmBlooded"]

    let asWarmBlooded_expected = SelectionsMatcher(
      direct: [
        .field("bodyTemperature", type: .integer()),
      ],
      merged: [
      ]
    )

    let asClassroomPet_asWarmBlooded_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
        .field("bodyTemperature", type: .integer()),
      ],
      mergedSources: [
        try .mock(asWarmBlooded_actual)
      ]
    )

    // then
    expect(asWarmBlooded_actual).to(shallowlyMatch(asWarmBlooded_expected))
    expect(asClassroomPet_asWarmBlooded_actual).to(shallowlyMatch(asClassroomPet_asWarmBlooded_expected))
  }

  func test__mergedSelections__givenInterfaceTypeInUnion_uncleSelectionSetIsChildMatchingInterfaceType_mergesUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      humanName: String
      species: String
    }

    interface WarmBloodedPet implements Pet {
      bodyTemperature: Int
      species: String
      humanName: String
    }

    type Cat implements WarmBloodedPet & Pet {
      bodyTemperature: Int
      species: String
      humanName: String
    }

    union ClassroomPet = Cat
    """

    document = """
    query Test {
     allAnimals {
       ... on Pet {
         humanName
       }
       ... on ClassroomPet {
         ... on WarmBloodedPet { # WarmBloodedPet implements Pet
           species
         }
       }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asPet_actual = allAnimals?[as: "Pet"]
    let asClassroomPet_asWarmBloodedPet_actual = allAnimals?[as: "ClassroomPet"]?[as: "WarmBloodedPet"]

    let asPet_expected = SelectionsMatcher(
      direct: [
        .field("humanName", type: .string()),
      ],
      merged: [
      ]
    )

    let asClassroomPet_asWarmBloodedPet_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
        .field("humanName", type: .string()),
      ],
      mergedSources: [
        try .mock(asPet_actual)
      ]
    )

    // then
    expect(asPet_actual).to(shallowlyMatch(asPet_expected))
    expect(asClassroomPet_asWarmBloodedPet_actual).to(shallowlyMatch(asClassroomPet_asWarmBloodedPet_expected))
  }

  func test__mergedSelections__givenInterfaceTypeInUnion_uncleSelectionSetIsNonMatchingInterfaceType_doesNotMergesUncleSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }

    interface Pet {
      humanName: String
      species: String
    }

    interface WarmBlooded {
      bodyTemperature: Int
      species: String
      humanName: String
    }

    type Cat implements WarmBlooded & Pet {
      bodyTemperature: Int
      species: String
      humanName: String
    }

    union ClassroomPet = Cat
    """

    document = """
    query Test {
      allAnimals {
        ... on WarmBlooded {
          bodyTemperature
        }
        ... on ClassroomPet {
          ... on Pet {
            species
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let asWarmBlooded_actual = allAnimals?[as: "WarmBlooded"]

    let asClassroomPet_asPet_actual = allAnimals?[as: "ClassroomPet"]?[as: "Pet"]

    let asWarmBlooded_expected = SelectionsMatcher(
      direct: [
        .field("bodyTemperature", type: .integer()),
      ],
      merged: [
      ]
    )

    let asClassroomPet_asPet_expected = SelectionsMatcher(
      direct: [
        .field("species", type: .string()),
      ],
      merged: [
      ]
    )

    // then
    expect(asWarmBlooded_actual).to(shallowlyMatch(asWarmBlooded_expected))
    expect(asClassroomPet_asPet_actual).to(shallowlyMatch(asClassroomPet_asPet_expected))
  }

  // MARK: - Merged Selections - Child Fragment

  func test__mergedSelections__givenChildIsNamedFragmentOnSameType_mergesFragmentFieldsAndMaintainsFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let Fragment_AnimalDetails = try XCTUnwrap(allAnimals?[fragment: "AnimalDetails"])
    let actual = allAnimals?.selectionSet

    let expected = SelectionsMatcher(
      direct: [
        .fragmentSpread(Fragment_AnimalDetails.definition)
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(Fragment_AnimalDetails)
      ]
    )

    // then
    expect(actual).to(shallowlyMatch(expected))
  }

  func test__mergedSelections__givenChildIsNamedFragmentOnSameType_fragmentSpreadTypePathIsCorrect() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ...AnimalDetails
      }
    }

    fragment AnimalDetails on Animal {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let actual = subject[field: "allAnimals"]?[fragment: "AnimalDetails"]

    let query_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: operation.rootType,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes)

    let allAnimals_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    )

    let expectedTypePath = LinkedList([
      query_TypeScope,
      allAnimals_TypeScope,
    ])

    // then
    expect(actual?.typeInfo.scopePath).to(equal(expectedTypePath))
  }

  func test__mergedSelections__givenChildIsNamedFragmentOnMoreSpecificType_doesNotMergeFragmentFields_hasTypeCaseForNamedFragmentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ...BirdDetails
      }
    }

    fragment BirdDetails on Bird {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])
    let Fragment_BirdDetails = try XCTUnwrap(ir.compilationResult[fragment: "BirdDetails"])

    let allAnimals = subject[field: "allAnimals"]

    let allAnimals_expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .inlineFragment(parentType: Object_Bird)
      ],
      mergedSelections: [],
      mergedSources: []
    )

    let allAnimals_asBird_expected = SelectionSetMatcher(
      parentType: Object_Bird,
      directSelections: [
        .fragmentSpread(Fragment_BirdDetails)
      ],
      mergedSelections: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(allAnimals?[as: "Bird"]?[fragment: "BirdDetails"])
      ]
    )

    let actual = allAnimals?.selectionSet

    // then
    expect(actual).to(shallowlyMatch(allAnimals_expected))
    expect(actual?[as: "Bird"]).to(shallowlyMatch(allAnimals_asBird_expected))
  }

  func test__mergedSelections__givenChildIsNamedFragmentOnMultipleNestedMoreSpecificTypes_doesNotMergeFragmentFields_hasTypeCaseForNamedFragmentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      species: String
    }

    type Bird implements Animal & Pet {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Pet {
          ...BirdDetails
        }
      }
    }

    fragment BirdDetails on Bird {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Interface_Pet = try XCTUnwrap(schema[interface: "Pet"])
    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])
    let Fragment_BirdDetails = try XCTUnwrap(ir.compilationResult[fragment: "BirdDetails"])

    let allAnimals = subject[field: "allAnimals"]

    let allAnimals_expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .inlineFragment(parentType: Interface_Pet)
      ],
      mergedSelections: [],
      mergedSources: []
    )

    let allAnimals_asPet_expected = SelectionSetMatcher(
      parentType: Interface_Pet,
      directSelections: [
        .inlineFragment(parentType: Object_Bird)
      ],
      mergedSelections: [],
      mergedSources: []
    )

    let allAnimals_asPet_asBird_expected = SelectionSetMatcher(
      parentType: Object_Bird,
      directSelections: [
        .fragmentSpread(Fragment_BirdDetails)
      ],
      mergedSelections: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(allAnimals?[as: "Pet"]?[as: "Bird"]?[fragment: "BirdDetails"])
      ]
    )

    let actual = allAnimals?.selectionSet

    // then
    expect(actual).to(shallowlyMatch(allAnimals_expected))
    expect(actual?[as: "Pet"]).to(shallowlyMatch(allAnimals_asPet_expected))
    expect(actual?[as: "Pet"]?[as: "Bird"]).to(shallowlyMatch(allAnimals_asPet_asBird_expected))
  }

  func test__mergedSelections__givenIsObjectType_childIsNamedFragmentOnLessSpecificMatchingType_mergesFragmentFields() async throws {
    // given
    schemaSDL = """
    type Query {
      birds: [Bird!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      species: String
    }
    """

    document = """
    fragment AnimalDetails on Animal {
      species
    }

    query Test {
      birds {
        ...AnimalDetails
      }
    }
    """

    // when
    try await buildSubjectRootField()


    let birds = subject[field: "birds"]
    let actual = birds?.selectionSet

    let Fragment_AnimalDetails = try XCTUnwrap(birds?[fragment: "AnimalDetails"])

    let expected = SelectionsMatcher(
      direct: [
        .fragmentSpread(Fragment_AnimalDetails.definition)
      ],
      merged: [
        .field("species", type: .string())
      ],
      mergedSources: [
        try .mock(Fragment_AnimalDetails)
      ]
    )

    // then
    expect(actual).to(shallowlyMatch(expected))
  }

  func test__mergedSelections__givenIsInterfaceType_childIsNamedFragmentOnLessSpecificMatchingType_mergesFragmentFields() async throws {
    // given
    schemaSDL = """
    type Query {
      flyingAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface FlyingAnimal implements Animal {
      species: String
    }
    """

    document = """
    fragment AnimalDetails on Animal {
      species
    }

    query Test {
      flyingAnimals {
        ...AnimalDetails
      }
    }
    """

    // when
    try await buildSubjectRootField()


    let flyingAnimals = subject[field: "flyingAnimals"]
    let actual = flyingAnimals?.selectionSet

    let Fragment_AnimalDetails = try XCTUnwrap(flyingAnimals?[fragment: "AnimalDetails"])

    let expected = SelectionsMatcher(
      direct: [
        .fragmentSpread(Fragment_AnimalDetails.definition)
      ],
      merged: [
        .field("species", type: .string()),
      ],
      mergedSources: [
        try .mock(Fragment_AnimalDetails)
      ]
    )

    // then
    expect(actual).to(shallowlyMatch(expected))
  }

  func test__mergedSelections__givenChildIsNamedFragmentOnUnrelatedType_doesNotMergeFragmentFields_hasTypeCaseForNamedFragmentType() async throws {
    // given
    schemaSDL = """
    type Query {
      rocks: [Rock!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      species: String
    }

    type Rock {
      name: String
    }
    """

    document = """
    fragment BirdDetails on Bird {
      species
    }

    query Test {
      rocks {
        ...BirdDetails
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])

    let Fragment_BirdDetails = try XCTUnwrap(ir.compilationResult[fragment: "BirdDetails"])

    let expected = SelectionsMatcher(
      direct: [
        .inlineFragment(parentType: Object_Bird)
      ],
      merged: [
      ]
    )

    let rocks = subject[field: "rocks"]
    let actual = rocks?.selectionSet

    // then
    expect(actual).to(shallowlyMatch(expected))
    expect(actual?[as: "Bird"]?.computed.direct)
      .to(shallowlyMatch([.fragmentSpread(Fragment_BirdDetails)]))
  }

  func test__mergedSelections__givenNestedNamedFragmentWithNonMatchingParentType_otherNestedNamedFragmentWithNonMatchingParentTypeWithInlineFragmentOnTypeOfFirstFragment_hasFragmentMergedSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      aField: [A!]
    }

    type A {
      someInterface: SomeInterface!
    }

    type B implements BInterface {
      cObject: C!
    }

    type C {
      integer: Int
    }

    interface SomeInterface {
      integer: Int
    }

    interface SomeInterface2 {
      cObject: C!
    }

    interface BInterface {
      cObject: C!
    }
    """

    document = """
    fragment FragmentA on A {
      someInterface {
        ...FragmentB
        ...FragmentB2
      }
    }

    fragment FragmentB on BInterface {
     ... on SomeInterface2 {
        cObject {
          integer
        }
      }
    }

    fragment FragmentB2 on SomeInterface2 {
      cObject {
        integer
      }
    }

    query Test {
      aField {
        ...FragmentA
      }
    }
    """

    // when
    try await buildSubjectRootField()
    
    let Fragment_FragmentB = try XCTUnwrap(ir.compilationResult[fragment: "FragmentB"])
    let Interface_BInterface = try XCTUnwrap(schema[interface: "BInterface"])
    let Interface_SomeInterface2 = try XCTUnwrap(schema[interface: "SomeInterface2"])

    let aField = subject[field: "aField"]
    let someInterfaceField = aField![field: "someInterface"]
    let someInterfaceField_asBInterface = someInterfaceField![as: "BInterface"]

    let FragmentSpread_FragmentA = aField?[fragment: "FragmentA"]
    let FragmentA_someInterface = FragmentSpread_FragmentA?[field: "someInterface"]
    let FragmentA_someInterface_asBInterface = try XCTUnwrap(FragmentA_someInterface?[as: "BInterface"])

    let someInterfaceFieldExpected = SelectionsMatcher(
      direct: nil,
      merged: [
        .inlineFragment(parentType: Interface_BInterface),
        .inlineFragment(parentType: Interface_SomeInterface2),
      ],
      mergedSources: []
    )

    let someInterfaceField_asBInterfaceExpected = SelectionsMatcher(
      direct: nil,
      merged: [
        .fragmentSpread(Fragment_FragmentB, inclusionConditions: .none)
      ],
      mergedSources: [
        .init(typeInfo: FragmentA_someInterface_asBInterface.typeInfo,
              fragment: FragmentSpread_FragmentA?.fragment)
      ]
    )

    // then
    expect(someInterfaceField?.selectionSet).to(shallowlyMatch(someInterfaceFieldExpected))
    expect(someInterfaceField_asBInterface).to(shallowlyMatch(someInterfaceField_asBInterfaceExpected))
  }

  // MARK: - Nested Entity Field - Merged Selections

  func test__mergedSelections__givenEntityFieldOnObjectAndTypeCase_withOtherNestedFieldInTypeCase_mergesParentFieldIntoNestedSelectionsInTypeCase() async throws {
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

    type Height {
      feet: Int
      meters: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        height {
          feet
        }
        ... on Pet {
          height {
            meters
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let allAnimals_height_actual = allAnimals?[field: "height"]?.selectionSet
    let allAnimals_asPet_height_actual = allAnimals?[as: "Pet"]?[field: "height"]?.selectionSet

    let allAnimals_height_expected = SelectionsMatcher(
      direct: [
        .field("feet", type: .integer())
      ],
      merged: [
      ]
    )

    let allAnimals_asPet_height_expected = SelectionsMatcher(
      direct: [
        .field("meters", type: .integer()),
      ],
      merged: [
        .field("feet", type: .integer()),
      ],
      mergedSources: [
        try .mock(allAnimals_height_actual)
      ]
    )

    // then
    expect(allAnimals_height_actual).to(shallowlyMatch(allAnimals_height_expected))
    expect(allAnimals_asPet_height_actual).to(shallowlyMatch(allAnimals_asPet_height_expected))
  }

  func test__mergedSelections__givenEntityFieldOnObjectWithSelectionSetIncludingSameFieldNameAndDifferentSelections_doesNotMergeFieldIntoNestedFieldsSelections() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      height: Height
      predators: [Animal!]
    }

    type Height {
      feet: Int
      meters: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        height {
          feet
        }
        predators {
          height {
            meters
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let allAnimals_expected = SelectionsMatcher(
      direct: [
        .field("feet", type: .integer())
      ],
      merged: [
      ]
    )

    let predators_expected = SelectionsMatcher(
      direct: [
        .field("meters", type: .integer()),
      ],
      merged: [
      ]
    )

    let allAnimals_height_actual = allAnimals?[field: "height"]?.selectionSet
    let predators_height_actual = allAnimals?[field: "predators"]?[field: "height"]?.selectionSet

    // then
    expect(allAnimals_height_actual).to(shallowlyMatch(allAnimals_expected))
    expect(predators_height_actual).to(shallowlyMatch(predators_expected))
  }

  func test__mergedSelections__givenEntityFieldOnInterfaceAndTypeCase_withOtherNestedFieldInTypeCase_mergesParentFieldIntoNestedSelectionsInObjectTypeCaseMatchingInterfaceTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      height: Height
    }

    interface Pet implements Animal {
      height: Height
      species: String
    }

    type Cat implements Pet & Animal {
      species: String
      height: Height
    }

    type Height {
      feet: Int
      meters: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        height {
          feet
        }
        ... on Pet {
          height {
            meters
          }
        }
        ... on Cat {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let allAnimals_asCat_height_actual = allAnimals?[as: "Cat"]?[field: "height"]?.selectionSet

    let allAnimals_asCat_height_expected = SelectionsMatcher(
      direct: nil,
      merged: [
        .field("feet", type: .integer()),
        .field("meters", type: .integer()),
      ],
      mergedSources: [
        try .mock(allAnimals?[field: "height"]),
        try .mock(allAnimals?[as: "Pet"]?[field: "height"]),
      ]
    )

    // then
    expect(allAnimals_asCat_height_actual).to(shallowlyMatch(allAnimals_asCat_height_expected))
  }

  func test__mergedSelections__givenEntityFieldOnInterfaceAndTypeCase_withOtherNestedFieldInTypeCase_doesNotMergeParentFieldIntoNestedSelectionsInObjectTypeCaseNotMatchingInterfaceTypeCase() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      height: Height
    }

    interface Pet implements Animal {
      height: Height
      species: String
    }

    type Elephant implements Animal {
      species: String
      height: Height
    }

    type Height {
      feet: Int
      meters: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        height {
          feet
        }
        ... on Pet {
          height {
            meters
          }
        }
        ... on Elephant { # does not implement Pet
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let allAnimals_asElephant_height_expected = SelectionsMatcher(
      direct: nil,
      merged: [
        .field("feet", type: .integer())
      ],
      mergedSources: [
        try .mock(allAnimals?[field: "height"])
      ]
    )

    let allAnimals_asElephant_height_actual = allAnimals?[as: "Elephant"]?[field: "height"]?.selectionSet

    // then
    expect(allAnimals_asElephant_height_actual).to(shallowlyMatch(allAnimals_asElephant_height_expected))
  }

  func test__mergedSelections__givenEntityFieldOnEntityWithDeepNestedTypeCases_eachTypeCaseHasDifferentNestedEntityFields_mergesFieldIntoMatchingNestedTypeCases() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      height: Height
    }

    interface Pet implements Animal {
      height: Height
      species: String
    }

    interface WarmBlooded {
      height: Height
    }

    type Height {
      feet: Int
      meters: Int
      inches: Int
      yards: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        height {
          feet
        }
        ... on Pet {
          height {
            meters
          }
          ... on WarmBlooded {
            height {
              inches
            }
          }
        }
        ... on WarmBlooded {
          height {
            yards
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let allAnimals_height = allAnimals?[field: "height"]
    let allAnimals_asPet_height = allAnimals?[as: "Pet"]?[field: "height"]
    let allAnimals_asWarmBlooded_height = allAnimals?[as: "WarmBlooded"]?[field: "height"]

    let allAnimals_height_expected = SelectionsMatcher(
      direct: [
        .field("feet", type: .integer())
      ],
      merged: [
      ]
    )

    let allAnimals_asPet_height_expected = SelectionsMatcher(
      direct: [
        .field("meters", type: .integer()),
      ],
      merged: [
        .field("feet", type: .integer()),
      ],
      mergedSources: [
        try .mock(allAnimals_height)
      ]
    )

    let allAnimals_asPet_asWarmBlooded_height_expected = SelectionsMatcher(
      direct: [
        .field("inches", type: .integer()),
      ],
      merged: [
        .field("feet", type: .integer()),
        .field("meters", type: .integer()),
        .field("yards", type: .integer()),
      ],
      mergedSources: [
        try .mock(allAnimals_height),
        try .mock(allAnimals_asPet_height),
        try .mock(allAnimals_asWarmBlooded_height),
      ]
    )

    let allAnimals_asWarmBlooded_height_expected = SelectionsMatcher(
      direct: [
        .field("yards", type: .integer()),
      ],
      merged: [
        .field("feet", type: .integer()),
      ],
      mergedSources: [
        try .mock(allAnimals_height)
      ]
    )

    let allAnimals_height_actual = allAnimals?[field: "height"]?.selectionSet

    let allAnimals_asPet_height_actual =
    allAnimals?[as: "Pet"]?[field: "height"]?.selectionSet

    let allAnimals_asPet_asWarmBlooded_height_actual =
    allAnimals?[as: "Pet"]?[as: "WarmBlooded"]?[field: "height"]?.selectionSet

    let allAnimals_asWarmBlooded_height_actual =
    allAnimals?[as: "WarmBlooded"]?[field: "height"]?.selectionSet

    // then
    expect(allAnimals_height_actual)
      .to(shallowlyMatch(allAnimals_height_expected))
    expect(allAnimals_asPet_height_actual)
      .to(shallowlyMatch(allAnimals_asPet_height_expected))
    expect(allAnimals_asPet_asWarmBlooded_height_actual)
      .to(shallowlyMatch(allAnimals_asPet_asWarmBlooded_height_expected))
    expect(allAnimals_asWarmBlooded_height_actual)
      .to(shallowlyMatch(allAnimals_asWarmBlooded_height_expected))
  }

  func test__mergedSelections__givenSiblingTypeCasesAndNestedEntityTypeCases_onlyNestedEntityFieldMergeTypeCases() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      predator: Animal
      height: Height
    }

    interface Reptile {
      skinCovering: String
    }

    type Cat implements Pet & Animal {
      species: String
      breed: String
      height: Height
      predator: Animal
    }

    type Height {
      feet: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Pet {
          ... on Reptile {
            skinCovering
          }
          predator {
            ... on Pet {
              height {
                feet
              }
            }
            ... on Reptile {
              skinCovering
            }
            ... on Cat {
              breed
            }
          }
        }
        ... on Reptile {
          skinCovering
        }
        ... on Cat {
          breed
        }
      }
    }
    """
    
    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]).toNot(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "skinCovering"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[as: "Reptile"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[as: "Pet"]).to(beNil())

    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[field: "height"]).toNot(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[field: "skinCovering"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[field: "breed"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[as: "Reptile"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[as: "Pet"]).to(beNil())

    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Cat"]?[field: "height"]).toNot(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Cat"]?[field: "skinCovering"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Cat"]?[as: "Reptile"]).to(beNil())
    expect(allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Cat"]?[as: "Pet"]).to(beNil())

    expect(allAnimals?[as: "Pet"]?[field: "predator"]?[as: "Cat"]?[field: "height"]).toNot(beNil())
    expect(allAnimals?[as: "Pet"]?[field: "predator"]?[as: "Cat"]?[field: "breed"]).toNot(beNil())
    expect(allAnimals?[as: "Pet"]?[field: "predator"]?[as: "Cat"]?[field: "skinCovering"]).to(beNil())
    expect(allAnimals?[as: "Pet"]?[field: "predator"]?[as: "Cat"]?[as: "Reptile"]).to(beNil())
    expect(allAnimals?[as: "Pet"]?[field: "predator"]?[as: "Cat"]?[as: "Pet"]).to(beNil())
  }

  func test__mergedSelections__givenSiblingTypeCasesAndNestedEntityTypeCases_withNamedFragments_mergesFragmentsIntoNestedEntityTypeCases() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      predator: Animal
      height: Height
    }

    interface Reptile {
      skinCovering: String
    }

    type Cat implements Pet & Animal {
      species: String
      breed: String
      height: Height
      predator: Animal
    }

    type Height {
      feet: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Pet {
          ... on Reptile {
            ...SkinCoveringFragment
          }
          predator {
            ... on Pet {
              ...HeightFragment
            }
            ... on Reptile {
              ...SkinCoveringFragment
            }
            ... on Cat {
              ...SpeciesFragment
            }
          }
        }
        ... on Reptile {
          ...SkinCoveringFragment
        }
        ... on Cat {
          ...BreedFragment
        }
      }
    }

    fragment HeightFragment on Pet {
      height {
        feet
      }
    }

    fragment SkinCoveringFragment on Reptile {
      skinCovering
    }

    fragment SpeciesFragment on Animal {
      species
    }

    fragment BreedFragment on Cat {
      breed
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]
    let asCat = allAnimals?[as: "Cat"]
    let asCat_predator = asCat?[field: "predator"]

    expect(asCat?[fragment: "BreedFragment"]).toNot(beNil())
    expect(asCat?[fragment: "SkinCoveringFragment"]).to(beNil())

    expect(asCat?[field: "predator"]?[fragment: "SkinCoveringFragment"]).to(beNil())
    expect(asCat?[field: "predator"]?[fragment: "BreedFragment"]).to(beNil())
    expect(asCat?[field: "predator"]?[fragment: "SpeciesFragment"]).to(beNil())
    expect(asCat?[field: "predator"]?[fragment: "HeightFragment"]).to(beNil())

    expect(asCat_predator?[as: "Pet"]?[fragment: "SkinCoveringFragment"]).to(beNil())
    expect(asCat_predator?[as: "Pet"]?[fragment: "BreedFragment"]).to(beNil())
    expect(asCat_predator?[as: "Pet"]?[fragment: "SpeciesFragment"]).to(beNil())
    expect(asCat_predator?[as: "Pet"]?[fragment: "HeightFragment"]).toNot(beNil())

    expect(asCat_predator?[as: "Reptile"]?[fragment: "SkinCoveringFragment"]).toNot(beNil())
    expect(asCat_predator?[as: "Reptile"]?[fragment: "BreedFragment"]).to(beNil())
    expect(asCat_predator?[as: "Reptile"]?[fragment: "SpeciesFragment"]).to(beNil())
    expect(asCat_predator?[as: "Reptile"]?[fragment: "HeightFragment"]).to(beNil())

    expect(asCat_predator?[as: "Cat"]?[fragment: "SkinCoveringFragment"]).to(beNil())
    expect(asCat_predator?[as: "Cat"]?[fragment: "BreedFragment"]).to(beNil())
    expect(asCat_predator?[as: "Cat"]?[fragment: "SpeciesFragment"]).toNot(beNil())
    expect(asCat_predator?[as: "Cat"]?[fragment: "HeightFragment"]).toNot(beNil())
  }

  // MARK: - Nested Entity Field - Merged Selections - Calculate Type Path

  func test__mergedSelections__givenEntityFieldOnTypeWithOnlyMergedSelections_mergedOnlyEntityFieldHasCorrectTypePath() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      height: Height
      predator: Animal
    }

    type Cat implements Animal {
      breed: String
      height: Height
      predator: Animal
    }

    type Height {
      feet: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        predator {
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

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let query_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: operation.rootType,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes)

    let allAnimals_asCat_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    ).appending(schema[object: "Cat"]!)

    let allAnimals_asCat_predator_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes)

    let allAnimals_asCat_predator_height_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[object: "Height"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes)

    let allAnimals_asCat_predator_expectedTypePath = LinkedList([
      query_TypeScope,
      allAnimals_asCat_TypeScope,
      allAnimals_asCat_predator_TypeScope
    ])

    let allAnimals_asCat_predator_height_expectedTypePath = LinkedList([
      query_TypeScope,
      allAnimals_asCat_TypeScope,
      allAnimals_asCat_predator_TypeScope,
      allAnimals_asCat_predator_height_TypeScope
    ])

    let allAnimals_asCat_predator_actual = allAnimals?[as: "Cat"]?[field: "predator"]?.selectionSet

    let allAnimals_asCat_predator_height_actual = allAnimals?[as: "Cat"]?[field: "predator"]?[field: "height"]?.selectionSet

    // then
    expect(allAnimals_asCat_predator_actual?.scopePath).to(equal(allAnimals_asCat_predator_expectedTypePath))

    expect(allAnimals_asCat_predator_height_actual?.scopePath).to(equal(allAnimals_asCat_predator_height_expectedTypePath))
  }

  func test__mergedSelections__givenEntityFieldInMatchingTypeCaseOnTypeWithOnlyMergedSelections_mergedOnlyEntityFieldHasCorrectTypePath() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet {
      predator: Animal
      height: Height
    }

    type Cat implements Pet & Animal {
      species: String
      breed: String
      height: Height
      predator: Animal
    }

    type Height {
      feet: Int
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Pet {
          predator {
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
        ... on Cat {
          breed
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let allAnimals = subject[field: "allAnimals"]

    let query_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: operation.rootType,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes)

    let allAnimals_asCat_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    ).appending(schema[object: "Cat"]!)

    let allAnimals_asCat_predator_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    )

    let allAnimals_asCat_predator_asPet_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[interface: "Animal"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    ).appending(schema[interface: "Pet"]!)

    let allAnimals_asCat_predator_asPet_height_TypeScope = IR.ScopeDescriptor.descriptor(
      forType: schema[object: "Height"]!,
      inclusionConditions: nil,
      givenAllTypesInSchema: schema.referencedTypes
    )

    let allAnimals_asCat_predator_expectedTypePath = LinkedList([
      query_TypeScope,
      allAnimals_asCat_TypeScope,
      allAnimals_asCat_predator_TypeScope
    ])

    let allAnimals_asCat_predator_height_expectedTypePath = LinkedList([
      query_TypeScope,
      allAnimals_asCat_TypeScope,
      allAnimals_asCat_predator_asPet_TypeScope,
      allAnimals_asCat_predator_asPet_height_TypeScope
    ])

    let allAnimals_asCat_predator_actual = allAnimals?[as: "Cat"]?[field: "predator"]?.selectionSet

    let allAnimals_asCat_predator_height_actual = allAnimals?[as: "Cat"]?[field: "predator"]?[as: "Pet"]?[field: "height"]?.selectionSet

    // then
    expect(allAnimals_asCat_predator_actual?.scopePath)
      .to(equal(allAnimals_asCat_predator_expectedTypePath))

    expect(allAnimals_asCat_predator_height_actual?.scopePath)
      .to(equal(allAnimals_asCat_predator_height_expectedTypePath))
  }

  // MARK: - Nested Entity In Fragments - Merged Selections

  func test__mergedSelections__givenEntityField_DirectSelectionsAndMergedFromNestedEntityInFragmentAndFragmentInFragment_nestedEntityFieldHasFragmentMergedSources() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
      predator: Animal!
      height: Height!
    }

    type Height {
      feet: Int
      meters: Int
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
          ...HeightInMeters
        }
      }
    }

    fragment HeightInMeters on Height {
      meters
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Height = try XCTUnwrap(schema[object: "Height"])

    let allAnimals = try XCTUnwrap(
      subject?[field: "allAnimals"]
    )
    let allAnimals_predator = try XCTUnwrap(
      allAnimals[field: "predator"]
    )

    let Fragment_PredatorDetails = try XCTUnwrap(
      subject?[field: "allAnimals"]?[fragment: "PredatorDetails"]
    )
    let PredatorDetails_Predator = try XCTUnwrap(
      Fragment_PredatorDetails[field: "predator"]
    )
    let PredatorDetails_Predator_Height = try XCTUnwrap(
      PredatorDetails_Predator[field: "height"]
    )

    let Fragment_PredatorDetails_HeightInMeters = try XCTUnwrap(
      PredatorDetails_Predator_Height[fragment: "HeightInMeters"]
    )

    let allAnimals_expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .field("predator", type: .nonNull(.entity(Interface_Animal))),
        .fragmentSpread(Fragment_PredatorDetails.definition),
      ],
      mergedSelections: [],
      mergedSources: []
    )

    let predator_expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .field("species", type: .string()),
      ],
      mergedSelections: [
        .field("height", type: .nonNull(.entity(Object_Height)))
      ],
      mergedSources: [
        try .mock(for: PredatorDetails_Predator, from: Fragment_PredatorDetails)
      ]
    )

    let predator_height_expected = SelectionSetMatcher(
      parentType: Object_Height,
      directSelections: nil,
      mergedSelections: [
        .field("feet", type: .integer()),
        .field("meters", type: .integer()),
        .fragmentSpread(Fragment_PredatorDetails_HeightInMeters.definition),
      ],
      mergedSources: [
        try .mock(
          for: PredatorDetails_Predator_Height,
          from: Fragment_PredatorDetails
        ),
        try .mock(
          for: Fragment_PredatorDetails_HeightInMeters.rootField,
          from: Fragment_PredatorDetails_HeightInMeters
        ),
      ]
    )

    // then
    expect(allAnimals.selectionSet).to(shallowlyMatch(allAnimals_expected))
    expect(allAnimals_predator.selectionSet).to(shallowlyMatch(predator_expected))
    expect(allAnimals_predator[field: "height"]?.selectionSet)
      .to(shallowlyMatch(predator_height_expected))
  }

  func test__mergedSelections__givenEntityFieldMergedFromNestedFragmentInTypeCase_withNoOtherMergedFields_hasNestedEntityMergedFields() async throws {
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

    // when
    try await buildSubjectRootField()


    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Interface_WarmBlooded = try XCTUnwrap(schema[interface: "WarmBlooded"])
    let Object_Height = try XCTUnwrap(schema[object: "Height"])

    let allAnimals = try XCTUnwrap(
      subject?[field: "allAnimals"]
    )
    let allAnimals_predator = try XCTUnwrap(
      allAnimals[field: "predator"]
    )
    let allAnimals_predator_asWarmBlooded = try XCTUnwrap(
      allAnimals_predator[as: "WarmBlooded"]
    )

    let Fragment_WarmBloodedDetails = try XCTUnwrap(
      allAnimals_predator_asWarmBlooded[fragment: "WarmBloodedDetails"]
    )

    let WarmBloodedDetails_HeightInMeters = try XCTUnwrap(
      Fragment_WarmBloodedDetails[fragment: "HeightInMeters"]
    )

    let HeightInMeters_Height = try XCTUnwrap(
      WarmBloodedDetails_HeightInMeters[field: "height"]
    )

    let predator_expected = SelectionSetMatcher(
      parentType: Interface_Animal,
      directSelections: [
        .inlineFragment(parentType: Interface_WarmBlooded)
      ],
      mergedSelections: [],
      mergedSources: []
    )

    let predator_asWarmBlooded_expected = SelectionSetMatcher(
      parentType: Interface_WarmBlooded,
      directSelections: [
        .fragmentSpread(Fragment_WarmBloodedDetails.definition)
      ],
      mergedSelections: [
        .field("species", type: .nonNull(.string())),
        .field("height", type: .nonNull(.entity(Object_Height))),
        .fragmentSpread(WarmBloodedDetails_HeightInMeters.definition)
      ],
      mergedSources: [
        try .mock(Fragment_WarmBloodedDetails),
        try .mock(WarmBloodedDetails_HeightInMeters)
      ]
    )

    let predator_asWarmBlooded_height_expected = SelectionSetMatcher(
      parentType: Object_Height,
      directSelections: nil,
      mergedSelections: [
        .field("meters", type: .nonNull(.integer())),
      ],
      mergedSources: [
        try .mock(for: HeightInMeters_Height, from: WarmBloodedDetails_HeightInMeters)
      ]
    )

    // then
    expect(allAnimals_predator.selectionSet).to(shallowlyMatch(predator_expected))
    expect(allAnimals_predator_asWarmBlooded)
      .to(shallowlyMatch(predator_asWarmBlooded_expected))
    expect(allAnimals_predator_asWarmBlooded[field: "height"]?.selectionSet)
      .to(shallowlyMatch(predator_asWarmBlooded_height_expected))
  }

  // MARK: - Nested Entity In Fragments - Merged Sources

  func test__mergedSources__givenEntityField_DirectSelectonsAndMergedFromNestedEntityInFragment_nestedEntityFieldHasFragmentMergedSources() async throws {
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

    // when
    try await buildSubjectRootField()

    let allAnimals_predator = try XCTUnwrap(
      subject?[field: "allAnimals"]?[field: "predator"]
    )

    let Fragment_PredatorDetails = subject?[field: "allAnimals"]?[fragment: "PredatorDetails"]
    let PredatorDetails_predator = try XCTUnwrap(
      Fragment_PredatorDetails?[field: "predator"]
    )

    let expected: OrderedSet<IR.MergedSelections.MergedSource> = [
      try .mock(for: PredatorDetails_predator, from: Fragment_PredatorDetails)
    ]

    // then
    expect(allAnimals_predator.selectionSet?.computed.merged.mergedSources).to(equal(expected))
  }

  // MARK: - Referenced Fragments

  func test__referencedFragments__givenUsesNoFragments_isEmpty() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    expect(self.computedReferencedFragments).to(beEmpty())
  }

  func test__referencedFragments__givenUsesFragmentAtRoot_includesFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }
    """

    document = """
    fragment QueryDetails on Query {
      allAnimals {
        species
      }
    }

    query Test {
      ...QueryDetails
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = await [
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "QueryDetails").xctUnwrapped()
    ].map(\.irObject)

    // then
    expect(Array(self.computedReferencedFragments)).to(equal(expected))
  }

  func test__referencedFragments__givenUsesFragmentOnEntityField_includesFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }
    """

    document = """
    fragment AnimalDetails on Animal {
      species
    }

    query Test {
      allAnimals {
        ...AnimalDetails
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = await [
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "AnimalDetails").xctUnwrapped()
    ].map(\.irObject)

    // then
    expect(Array(self.computedReferencedFragments)).to(equal(expected))
  }

  func test__referencedFragments__givenUsesMultipleFragmentsOnEntityField_includesFragments() async throws {
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
    fragment AnimalDetails on Animal {
      species
    }

    fragment AnimalName on Animal {
      name
    }

    query Test {
      allAnimals {
        ...AnimalDetails
        ...AnimalName
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = await [
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "AnimalDetails").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "AnimalName").xctUnwrapped(),
    ].map(\.irObject)

    // then
    expect(Array(self.computedReferencedFragments)).to(equal(expected))
  }

  func test__referencedFragments__givenUsesFragmentsReferencingOtherFragment_includesBothFragments() async throws {
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
    fragment AnimalDetails on Animal {
      species
      ...AnimalName
    }

    fragment AnimalName on Animal {
      name
    }

    query Test {
      allAnimals {
        ...AnimalDetails
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = await [
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "AnimalDetails").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "AnimalName").xctUnwrapped(),
    ].map(\.irObject)

    // then
    expect(Array(self.computedReferencedFragments)).to(equal(expected))
  }

  func test__referencedFragments__givenMultipleFragments_hasFragmentsInAlphbeticalOrder() async throws {
    // given
    schemaSDL = """
    type Query {
      name: String!
    }
    """

    document =
    """
    query NameQuery {
      ...Fragment4
      ...Fragment1
    }

    fragment Fragment4 on Query {
      name
      ...Fragment3
    }

    fragment Fragment3 on Query {
      name
      ...Fragment2
    }

    fragment Fragment2 on Query {
      name
    }

    fragment Fragment1 on Query {
      name
      ...Fragment5
    }

    fragment Fragment5 on Query {
      name
    }
    """

    // when
    try await buildSubjectRootField()

    let expected = await [
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "Fragment1").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "Fragment2").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "Fragment3").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "Fragment4").xctUnwrapped(),
      try ir.builtFragmentStorage.getFragmentIfBuilt(named: "Fragment5").xctUnwrapped(),
    ].map(\.irObject)

    // then
    expect(Array(self.computedReferencedFragments)).to(equal(expected))
  }

  // MARK: - Deferred Fragments - containsDeferredFragment property

  func test__deferredFragments__givenNoDeferredFragment_containsDeferredFragmentFalse() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      name: String
    }
    """

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beFalse())
  }

  func test__deferredFragments__givenDeferredInlineFragment_containsDeferredFragmentTrue() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      name: String
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
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beTrue())
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithCondition_containsDeferredFragmentTrue() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      name: String
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
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beTrue())
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithConditionFalse_containsDeferredFragmentFalse() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      name: String
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
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beFalse())
  }

  func test__deferredFragments__givenDeferredNamedFragment_onDifferentTypeCase_containsDeferredFragmentTrue() async throws {
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
        ...DogFragment @defer(label: "root")
      }
    }

    fragment DogFragment on Dog {
      species
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beTrue())
  }

  func test__deferredFragments__givenDeferredInlineFragment_withinNamedFragment_containsDeferredFragmentTrue() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      name: String
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
      ... on Dog @defer(label: "root") {
        species
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beTrue())
  }

  func test__deferredFragments__givenDeferredNamedFragment_withSelectionOnDifferentTypeCase_containsDeferredFragmentTrue() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
    }

    interface Pet implements Animal {
      id: String
      species: String
      friends: [Pet]
      name: String
    }

    type Dog implements Pet {
      id: String
      species: String
      friends: [Pet]
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        ...FriendsFragment @defer(label: "root")
      }
    }

    fragment FriendsFragment on Dog {
      id
      ... on Pet {
        friends {
          name
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    expect(self.result.containsDeferredFragment).to(beTrue())
  }

  // MARK: Deferred Fragments - Inline Fragments

  func test__deferredFragments__givenDeferredInlineFragmentWithoutTypeCase_buildsDeferredInlineFragment() async throws {
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
        ... @defer(label: "root") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_deferredAsRoot = allAnimals?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .deferred(Interface_Animal, label: "root"),
        ]
      )
    ))

    expect(allAnimals_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentOnSameTypeCase_buildsDeferredInlineFragment() async throws {
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_deferredAsRoot = allAnimals?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .deferred(Interface_Animal, label: "root"),
        ]
      )
    ))

    expect(allAnimals_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentOnDifferentTypeCase_buildsDeferredInlineFragment() async throws {
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
      name: String!
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals_asDog?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithVariableCondition_buildsDeferredInlineFragmentWithVariable() async throws {
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
      name: String!
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals_asDog?[deferred: .init(label: "root", variable: "a")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root", variable: "a"),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithTrueCondition_buildsDeferredInlineFragment() async throws {
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
      name: String!
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals_asDog?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithFalseCondition_doesNotBuildDeferredInlineFragment() async throws {
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
      name: String!
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog?.containsDeferredChildFragment).to(beFalse())
  }

  func test__deferredFragments__givenSiblingDeferredInlineFragmentsOnSameTypeCase_doesNotMergeDeferredFragments() async throws {
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
      name: String!
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
    try await buildSubjectRootField()

    // then
    let Scalar_String = try XCTUnwrap(schema[scalar: "String"])
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsOne = allAnimals_asDog?[deferred: .init(label: "one")]
    let allAnimals_asDog_deferredAsTwo = allAnimals_asDog?[deferred: .init(label: "two")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "one"),
          .deferred(Object_Dog, label: "two"),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsOne).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsTwo).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("genus", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSelections: [
          .field("id", type: .nonNull(.scalar(Scalar_String))),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenSiblingDeferredInlineFragmentsOnDifferentTypeCase_doesNotMergeDeferredFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    type Bird implements Animal {
      species: String
      wingspan: Int
    }

    type Cat implements Animal {
      species: String
    }
    """.appendingDeferDirective()

    document = """
    query Test {
      allAnimals {
        ... on Bird @defer(label: "bird") {
          wingspan
        }
        ... on Cat @defer(label: "cat") {
          species
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Bird = try XCTUnwrap(schema[object: "Bird"])
    let Object_Cat = try XCTUnwrap(schema[object: "Cat"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asBird = allAnimals?[as: "Bird"]
    let allAnimals_asCat = allAnimals?[as: "Cat"]
    let allAnimals_asBird_deferredAsBird = allAnimals_asBird?[deferred: .init(label: "bird")]
    let allAnimals_asCat_deferredAsCat = allAnimals_asCat?[deferred: .init(label: "cat")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .inlineFragment(parentType: Object_Bird),
          .inlineFragment(parentType: Object_Cat),
        ]
      )
    ))

    expect(allAnimals_asBird).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Bird,
        directSelections: [
          .deferred(Object_Bird, label: "bird"),
        ]
      )
    ))

    expect(allAnimals_asCat).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Cat,
        directSelections: [
          .deferred(Object_Cat, label: "cat"),
        ]
      )
    ))

    expect(allAnimals_asBird_deferredAsBird).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Bird,
        directSelections: [
          .field("wingspan", type: .integer()),
        ]
      )
    ))

    expect(allAnimals_asCat_deferredAsCat).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Cat,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithSiblingOnSameTypeCase_doesNotMergeDeferredFragment() async throws {
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
      name: String
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
          name
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals_asDog?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("name", type: .string()),
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .field("name", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
          try .mock(allAnimals_asDog),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentWithSiblingOnDifferentTypeCase_doesNotMergeDeferredFragment() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      name: String
    }

    type Dog implements Animal {
      id: String
      species: String
      name: String
    }

    type Pet implements Animal {
      id: String
      species: String
      name: String
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
        ... on Pet {
          name
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Object_Pet = try XCTUnwrap(schema[object: "Pet"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asPet = allAnimals?[as: "Pet"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals_asDog?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
          .inlineFragment(parentType: Object_Pet),
        ]
      )
    ))

    expect(allAnimals_asPet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Pet,
        directSelections: [
          .field("name", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenNestedDeferredInlineFragments_buildsNestedDeferredFragments_doesNotMergeDeferredFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
      friend: Animal
    }

    type Cat implements Animal {
      id: String
      species: String
      genus: String
    }
    """.appendingDeferDirective()

    document = """
    query TestOperation {
      allAnimals {
        __typename
        id
        ... on Dog @defer(label: "outer") {
          friend {
            ... on Cat @defer(label: "inner") {
              species
            }
          }
        }
      }
    }
    """

    // when
    try await buildSubjectRootField()

    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Object_Cat = try XCTUnwrap(schema[object: "Cat"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsOuter = allAnimals_asDog?[deferred: .init(label: "outer")]
    let allAnimals_asDog_deferredAsOuter_asCat = allAnimals_asDog_deferredAsOuter?[field: "friend"]?[as: "Cat"]
    let allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner =
    allAnimals_asDog_deferredAsOuter_asCat?[deferred: .init(label: "inner")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "outer"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsOuter).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("friend", type: .entity(Interface_Animal)),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsOuter_asCat).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Cat,
        directSelections: [
          .deferred(Object_Cat, label: "inner"),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsOuter_asCat_deferredAsInner).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Cat,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  // MARK: Deferred Fragments - Inline Fragments (with @include/@skip)

  func test__deferredFragments__givenBothDeferAndIncludeDirectives_onSameTypeCase_buildsInclusionTypeCaseWithNestedDeferredInlineFragment() async throws {
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
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_ifA = allAnimals?[if: "a"]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.include(if: "a")]),
        ]
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.include(if: "a")],
        directSelections: [
          .deferred(Interface_Animal, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndIncludeDirectives_directivesOrderShouldNotAffectGeneratedFragments() async throws {
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
    query IncludeFirst($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @include(if: $a) @defer(label: "root") {
          species
        }
      }
    }

    query DeferFirst($a: Boolean) {
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
    for operationName in ["IncludeFirst", "DeferFirst"] {
      try await buildSubjectRootField(operationName: operationName)

      // then
      let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

      let allAnimals = self.subject[field: "allAnimals"]
      let allAnimals_ifA = allAnimals?[if: "a"]

      let expectedInclusion = SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.include(if: "a")]),
        ]
      )

      let expectedDefer = SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.include(if: "a")],
        directSelections: [
          .deferred(Interface_Animal, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )

      expect(allAnimals?.selectionSet).to(shallowlyMatch(expectedInclusion))
      expect(allAnimals_ifA).to(shallowlyMatch(expectedDefer))
    }
  }

  func test__deferredFragments__givenBothDeferAndIncludeDirectives_onDifferentTypeCases_shouldNotNestFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
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
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_ifA = allAnimals?[if: "a"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals?[as: "Dog"]?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.include(if: "a")]),
          .inlineFragment(parentType: Object_Dog)
        ]
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.include(if: "a")],
        directSelections: [
          .field("species", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("genus", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndSkipDirectives_onSameTypeCase_buildsInclusionTypeCaseWithNestedDeferredInlineFragment() async throws {
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
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_skipIfA = allAnimals?[if: !"a"]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.skip(if: "a")]),
        ]
      )
    ))

    expect(allAnimals_skipIfA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.skip(if: "a")],
        directSelections: [
          .deferred(Interface_Animal, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndSkipDirectives_directivesOrderShouldNotAffectGeneratedFragments() async throws {
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
    query IncludeFirst($a: Boolean) {
      allAnimals {
        __typename
        id
        ... on Animal @skip(if: $a) @defer(label: "root") {
          species
        }
      }
    }

    query DeferFirst($a: Boolean) {
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
    for operationName in ["IncludeFirst", "DeferFirst"] {
      try await buildSubjectRootField(operationName: operationName)
      
      // then
      let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])

      let allAnimals = self.subject[field: "allAnimals"]
      let allAnimals_skipIfA = allAnimals?[if: !"a"]

      let expectedInclusion = SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.skip(if: "a")]),
        ]
      )

      let expectedDefer = SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.skip(if: "a")],
        directSelections: [
          .deferred(Interface_Animal, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )

      expect(allAnimals?.selectionSet).to(shallowlyMatch(expectedInclusion))
      expect(allAnimals_skipIfA).to(shallowlyMatch(expectedDefer))
    }
  }

  func test__deferredFragments__givenBothDeferAndSkipDirectives_onDifferentTypeCases_shouldNotNestFragments() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      id: String
      species: String
      genus: String
    }

    type Dog implements Animal {
      id: String
      species: String
      genus: String
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
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_skipIfA = allAnimals?[if: !"a"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_deferredAsRoot = allAnimals?[as: "Dog"]?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.skip(if: "a")]),
          .inlineFragment(parentType: Object_Dog)
        ]
      )
    ))

    expect(allAnimals_skipIfA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.skip(if: "a")],
        directSelections: [
          .field("species", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("genus", type: .string()),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  // MARK: Deferred Fragments - Named Fragments

  func test__deferredFragments__givenDeferredNamedFragmentOnSameTypeCase_buildsDeferredNamedFragment() async throws {
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
          ...AnimalFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .deferred(Fragment_AnimalFragment, label: "root"),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredNamedFragmentOnDifferentTypeCase_buildsDeferredNamedFragment() async throws {
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
          ...DogFragment @defer(label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Fragment_DogFragment = try XCTUnwrap(ir.compilationResult[fragment: "DogFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Fragment_DogFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredNamedFragmentWithVariableCondition_buildsDeferredNamedFragmentWithVariable() async throws {
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
          ...DogFragment @defer(if: "a", label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Fragment_DogFragment = try XCTUnwrap(ir.compilationResult[fragment: "DogFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()


    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Fragment_DogFragment, label: "root", variable: "a"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredNamedFragmentWithTrueCondition_buildsDeferredNamedFragment() async throws {
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
          ...DogFragment @defer(if: true, label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Fragment_DogFragment = try XCTUnwrap(ir.compilationResult[fragment: "DogFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Fragment_DogFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredNamedFragmentWithFalseCondition_doesNotBuildDeferredNamedFragment() async throws {
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
          ...DogFragment @defer(if: false, label: "root")
        }
      }

      fragment DogFragment on Dog {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let allAnimals_asDog_DogFragment = allAnimals_asDog?[fragment: "DogFragment"]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .fragmentSpread("DogFragment", type: Object_Dog),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .field("species", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
          try .mock(allAnimals_asDog_DogFragment),
        ]
      )
    ))
    
    expect(allAnimals_asDog?.containsDeferredChildFragment).to(beFalse())
    expect(allAnimals_asDog_DogFragment?.rootField.selectionSet?.containsDeferredChildFragment).to(beFalse())
  }

  func test__deferredFragments__givenDeferredInlineFragment_insideNamedFragment_buildsDeferredInlineFragment_insideNamedFragment() async throws {
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
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()
    let dogFragment_asDog_deferredAsRoot = dogFragment[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Object_Dog),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .fragmentSpread("DogFragment", type: Object_Dog),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ]
      )
    ))

    expect(dogFragment_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredInlineFragmentOnDifferentTypeCase_insideNamedFragment_buildsDeferredInlineFragment_insideNamedFragment() async throws {
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
        ... on Dog @defer(label: "root") {
          species
        }
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])

    let allAnimals = self.subject[field: "allAnimals"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()
    let dogFragment_asDog = dogFragment[as: "Dog"]
    let dogFragment_asDog_deferredAsRoot = dogFragment_asDog?[deferred: .init(label: "root")]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .fragmentSpread("DogFragment", type: Interface_Animal),
        ]
      )
    ))

    expect(dogFragment_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Object_Dog, label: "root"),
        ]
      )
    ))

    expect(dogFragment_asDog_deferredAsRoot).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenDeferredNamedFragmentWithMatchingSiblingTypeCase_buildsSiblingInlineFragmentWithMergedDeferredFragmentSelection() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
      }

      type Pet implements Animal {
        id: String
        species: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation($a: Boolean) {
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
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])
    let Object_Pet = try XCTUnwrap(schema[object: "Pet"])

    let allAnimals = self.subject[field: "allAnimals"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()
    let allAnimals_asPet = allAnimals?[as: "Pet"]

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .inlineFragment(parentType: Object_Pet),
          .deferred(Fragment_AnimalFragment, label: "root"),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))

    expect(allAnimals_asPet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Pet,
        directSelections: [
          .field("id", type: .string()),
        ],
        mergedSelections: [
          .deferred(Fragment_AnimalFragment, label: "root"),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))
  }

  // MARK: Deferred Fragments - Named Fragments (with @include/@skip)

  func test__deferredFragments__givenBothDeferAndIncludeDirectives_onSameNamedFragment_buildsNestedDeferredNamedFragment() async throws {
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
      query TestOperation($a: Boolean) {
        allAnimals {
          __typename
          id
          ...AnimalFragment @include(if: $a) @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_ifA = allAnimals?[if: "a"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.include(if: "a")]),
        ],
        mergedSelections: []
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.include(if: "a")],
        directSelections: [
          .deferred(Fragment_AnimalFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndIncludeDirectives_onDifferentNamedFragment_shouldNotNestFragment() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
        genus: String
      }

      type Dog implements Animal {
        id: String
        species: String
        genus: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation($a: Boolean) {
        allAnimals {
          __typename
          id
          ...AnimalFragment @include(if: $a)
          ...DogFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }

      fragment DogFragment on Dog {
        genus
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])
    let Fragment_DogFragment = try XCTUnwrap(ir.compilationResult[fragment: "DogFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_animalFragment = allAnimals?[fragment: "AnimalFragment"]
    let allAnimals_ifA = allAnimals?[if: "a"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()

    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.include(if: "a")]),
          .inlineFragment(parentType: Object_Dog),
        ],
        mergedSelections: [
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.include(if: "a")]),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.include(if: "a")],
        directSelections: [
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.include(if: "a")]),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .field("species", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
          try .mock(allAnimals_animalFragment),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Fragment_DogFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.include(if: "a")]),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("genus", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndSkipDirectives_onSameNamedFragment_buildsNestedDeferredNamedFragment() async throws {
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
      query TestOperation($a: Boolean) {
        allAnimals {
          __typename
          id
          ...AnimalFragment @skip(if: $a) @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_ifA = allAnimals?[if: !"a"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.skip(if: "a")]),
        ]
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.skip(if: "a")],
        directSelections: [
          .deferred(Fragment_AnimalFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))
  }

  func test__deferredFragments__givenBothDeferAndSkipDirectives_onDifferentNamedFragment_shouldNotNestFragment() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      interface Animal {
        id: String
        species: String
        genus: String
      }

      type Dog implements Animal {
        id: String
        species: String
        genus: String
      }
      """.appendingDeferDirective()

    document = """
      query TestOperation($a: Boolean) {
        allAnimals {
          __typename
          id
          ...AnimalFragment @skip(if: $a)
          ...DogFragment @defer(label: "root")
        }
      }

      fragment AnimalFragment on Animal {
        species
      }

      fragment DogFragment on Dog {
        genus
      }
      """

    // when
    try await buildSubjectRootField()

    // then
    let Interface_Animal = try XCTUnwrap(schema[interface: "Animal"])
    let Object_Dog = try XCTUnwrap(schema[object: "Dog"])
    let Fragment_AnimalFragment = try XCTUnwrap(ir.compilationResult[fragment: "AnimalFragment"])
    let Fragment_DogFragment = try XCTUnwrap(ir.compilationResult[fragment: "DogFragment"])

    let allAnimals = self.subject[field: "allAnimals"]
    let allAnimals_animalFragment = allAnimals?[fragment: "AnimalFragment"]
    let allAnimals_ifA = allAnimals?[if: !"a"]
    let animalFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "AnimalFragment").xctUnwrapped()

    let allAnimals_asDog = allAnimals?[as: "Dog"]
    let dogFragment = try await ir.builtFragmentStorage
      .getFragmentIfBuilt(named: "DogFragment").xctUnwrapped()

    expect(allAnimals?.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("id", type: .string()),
          .inlineFragment(parentType: Interface_Animal, inclusionConditions: [.skip(if: "a")]),
          .inlineFragment(parentType: Object_Dog),
        ],
        mergedSelections: [
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.skip(if: "a")]),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(allAnimals_ifA).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        inclusionConditions: [.skip(if: "a")],
        directSelections: [
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.skip(if: "a")]),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .field("species", type: .string()),
        ],
        mergedSources: [
          try .mock(allAnimals),
          try .mock(allAnimals_animalFragment),
        ]
      )
    ))

    expect(animalFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Interface_Animal,
        directSelections: [
          .field("species", type: .string()),
        ]
      )
    ))

    expect(allAnimals_asDog).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .deferred(Fragment_DogFragment, label: "root"),
        ],
        mergedSelections: [
          .field("id", type: .string()),
          .fragmentSpread(Fragment_AnimalFragment, inclusionConditions: [.skip(if: "a")]),
        ],
        mergedSources: [
          try .mock(allAnimals),
        ]
      )
    ))

    expect(dogFragment.rootField.selectionSet).to(shallowlyMatch(
      SelectionSetMatcher(
        parentType: Object_Dog,
        directSelections: [
          .field("genus", type: .string()),
        ]
      )
    ))
  }

}
