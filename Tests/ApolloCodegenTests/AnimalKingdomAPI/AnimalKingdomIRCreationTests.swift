import Foundation
import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

final class AnimalKingdomIRCreationTests: XCTestCase {

  actor AnimalKingdomSchema {
    static let shared = AnimalKingdomSchema()

    private var frontend: GraphQLJSFrontend!
    private(set) var schema: GraphQLSchema!
    private(set) var compilationResult: CompilationResult!

    func setUp() async throws {
      guard compilationResult == nil else { return }
      self.frontend = try await GraphQLJSFrontend()
      self.schema = try await frontend.loadSchema(from: [
        try! frontend.makeSource(from: ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.Schema)
      ])
      self.compilationResult = try await frontend.compile(
        schema: schema,
        document: try await operationDocuments(),
        validationOptions: validationOptions()
      )
    }

    func operationDocuments() async throws -> GraphQLDocument {
      let documents = ApolloCodegenInternalTestHelpers.Resources.AnimalKingdom.GraphQLOperations

      return try await frontend.mergeDocuments(
        documents.asyncMap {
          try await frontend.parseDocument(from: $0)
        }
      )
    }

    func validationOptions() -> ValidationOptions {
      return ValidationOptions(config: .init(config: .mock()))

    }

    func tearDown() {
      self.frontend = nil
      self.schema = nil
      self.compilationResult = nil
    }

  }

  var expected: (fields: [ShallowFieldMatcher],
                 typeCases: [ShallowInlineFragmentMatcher],
                 fragments: [ShallowFragmentSpreadMatcher])!
  var operation: IRTestWrapper<IR.Operation>!

  class override func tearDown() {
    super.tearDown()
    Task {
      await AnimalKingdomSchema.shared.tearDown()
    }
  }

  override func setUp() async throws {
    try await AnimalKingdomSchema.shared.setUp()
    try await super.setUp()
  }

  override func tearDown() {
    expected = nil
    operation = nil
    super.tearDown()
  }

  // MARK: - Helpers

  var rootSelectionSet: SelectionSetTestWrapper! {
    operation.rootField.selectionSet
  }

  func buildOperation(named name: String = "AllAnimalsQuery") async throws {
    let compilationResult = await compilationResult()
    let operation = compilationResult.operations.first { $0.name == name }
    let ir = IRBuilderTestWrapper(IRBuilder.mock(compilationResult: compilationResult))
    self.operation = await ir.build(operation: try XCTUnwrap(operation))
  }

  func compilationResult() async -> CompilationResult {
    return await AnimalKingdomSchema.shared.compilationResult
  }

  // MARK: - Tests

  func test__directSelections_AllAnimalsQuery_RootQuery__isCorrect() async throws {
    // given
    try await buildOperation()

    expected = (
      fields: [
        .mock("allAnimals",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal"))))))
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = rootSelectionSet.computed.direct

    // then
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_RootQuery__isCorrect() async throws {
    // given
    try await buildOperation()

    // when
    let actual = self.rootSelectionSet.computed.merged

    // then
    expect(actual).to(beEmpty())
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal__isCorrect() async throws {
    // given
    let Interface_Animal = GraphQLInterfaceType.mock("Animal")

    try await buildOperation()

    let selectionSet = try XCTUnwrap(rootSelectionSet[field: "allAnimals"]?.selectionSet)

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(Interface_Animal))))),
      ],
      typeCases: [
        .mock(parentType: GraphQLInterfaceType.mock("WarmBlooded")),
        .mock(parentType: GraphQLInterfaceType.mock("Pet")),
        .mock(parentType: GraphQLObjectType.mock("Cat")),
        .mock(parentType: GraphQLUnionType.mock("ClassroomPet")),
        .mock(parentType: GraphQLObjectType.mock("Dog")),
      ],
      fragments: [
        .mock("HeightInMeters", type: Interface_Animal)
      ]
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(Interface_Animal))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal__isCorrect() async throws {
    // given
    let Interface_Animal = GraphQLInterfaceType.mock("Animal")

    try await buildOperation()

    let selectionSet = try XCTUnwrap(rootSelectionSet[field: "allAnimals"]?.selectionSet)

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(Interface_Animal))
    expect(actual).to(beEmpty())
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
      ],
      typeCases: [],
      fragments: []
    )
    
    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_Predator__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "predators"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
      ],
      typeCases: [
        .mock(parentType: GraphQLInterfaceType.mock("WarmBlooded"))
      ],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("Animal")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_Predator__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "predators"]?.selectionSet
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("Animal")))
    expect(actual).to(beEmpty())
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_Predator_AsWarmBlooded__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "predators"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(.mock("Animal")))))),
        .mock("laysEggs",
              type: .nonNull(.scalar(GraphQLScalarType.boolean()))),
      ],
      typeCases: [],
      fragments: [
        .mock("WarmBloodedDetails", type: GraphQLInterfaceType.mock("WarmBlooded")),
      ]
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_Predator_AsWarmBlooded__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[field: "predators"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("bodyTemperature",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
      ],
      typeCases: [],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsWarmBlooded__isCorrect() async throws  {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [],
      typeCases: [],
      fragments: [
        .mock("WarmBloodedDetails", type: GraphQLInterfaceType.mock("WarmBlooded")),
      ]
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsWarmBlooded__isCorrect() async throws  {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
        .mock("bodyTemperature",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
      ],
      typeCases: [],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsWarmBlooded_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "WarmBlooded"]?[field: "height"]?.selectionSet
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(beNil())
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsWarmBlooded_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "WarmBlooded"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsPet__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height"))))
      ],
      typeCases: [
        .mock(parentType: GraphQLInterfaceType.mock("WarmBlooded")),
      ],
      fragments: [
        .mock("PetDetails", type: GraphQLInterfaceType.mock("Pet")),
      ]
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("Pet")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsPet__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]
    )

    expected = (
      fields: [
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
        .mock("humanName",
              type: .scalar(GraphQLScalarType.string())),
        .mock("favoriteToy",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("owner",
              type: .entity(GraphQLObjectType.mock("Human"))),
      ],
      typeCases: [
      ],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("Pet")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsPet_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("relativeSize",
              type: .nonNull(.enum(GraphQLEnumType.relativeSize()))),
        .mock("centimeters",
              type: .nonNull(.scalar(GraphQLScalarType.float()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsPet_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AsPet_AsWarmBlooded__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [],
      typeCases: [],
      fragments: [
        .mock("WarmBloodedDetails", type: GraphQLInterfaceType.mock("WarmBlooded")),
      ]
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AsPet_AsWarmBlooded__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
        .mock("bodyTemperature",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("humanName",
              type: .scalar(GraphQLScalarType.string())),
        .mock("favoriteToy",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("owner",
              type: .entity(GraphQLObjectType.mock("Human"))),
      ],
      typeCases: [],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
        .mock("PetDetails", type: GraphQLInterfaceType.mock("Pet")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLInterfaceType.mock("WarmBlooded")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsPet_AsWarmBlooded_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]?[field: "height"]?.selectionSet
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(beNil())
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsPet_AsWarmBlooded_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Pet"]?[as: "WarmBlooded"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("relativeSize",
              type: .nonNull(.enum(GraphQLEnumType.relativeSize()))),
        .mock("centimeters",
              type: .nonNull(.scalar(GraphQLScalarType.float()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AsCat__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Cat"]
    )

    expected = (
      fields: [
        .mock("isJellicle",
              type: .nonNull(.scalar(GraphQLScalarType.boolean()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Cat")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AsCat__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Cat"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
        .mock("bodyTemperature",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("humanName",
              type: .scalar(GraphQLScalarType.string())),
        .mock("favoriteToy",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("owner",
              type: .entity(GraphQLObjectType.mock("Human"))),
      ],
      typeCases: [],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
        .mock("WarmBloodedDetails", type: GraphQLInterfaceType.mock("WarmBlooded")),
        .mock("PetDetails", type: GraphQLInterfaceType.mock("Pet")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Cat")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsCat_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Cat"]?[field: "height"]?.selectionSet
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(beNil())
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsCat_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "Cat"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("relativeSize",
              type: .nonNull(.enum(GraphQLEnumType.relativeSize()))),
        .mock("centimeters",
              type: .nonNull(.scalar(GraphQLScalarType.float()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AsClassroomPet__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]
    )

    expected = (
      fields: [],
      typeCases: [
        .mock(parentType: GraphQLObjectType.mock("Bird")),
      ],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLUnionType.mock("ClassroomPet")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AsClassroomPet__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
      ],
      typeCases: [
      ],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLUnionType.mock("ClassroomPet")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AsClassroomPet_AsBird__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]?[as: "Bird"]
    )

    expected = (
      fields: [
        .mock("wingspan",
              type: .nonNull(.scalar(GraphQLScalarType.float())))
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Bird")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__mergedSelections_AllAnimalsQuery_AsClassroomPet_AsBird__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]?[as: "Bird"]
    )

    expected = (
      fields: [
        .mock("height",
              type: .nonNull(.entity(GraphQLObjectType.mock("Height")))),
        .mock("species",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("skinCovering",
              type: .enum(GraphQLEnumType.skinCovering())),
        .mock("predators",
              type: .nonNull(.list(.nonNull(.entity(GraphQLInterfaceType.mock("Animal")))))),
        .mock("bodyTemperature",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("humanName",
              type: .scalar(GraphQLScalarType.string())),
        .mock("favoriteToy",
              type: .nonNull(.scalar(GraphQLScalarType.string()))),
        .mock("owner",
              type: .entity(GraphQLObjectType.mock("Human"))),
      ],
      typeCases: [],
      fragments: [
        .mock("HeightInMeters", type: GraphQLInterfaceType.mock("Animal")),
        .mock("WarmBloodedDetails", type: GraphQLInterfaceType.mock("WarmBlooded")),
        .mock("PetDetails", type: GraphQLInterfaceType.mock("Pet")),
      ]
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Bird")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  func test__directSelections_AllAnimalsQuery_AllAnimal_AsClassroomPet_AsBird_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]?[as: "Bird"]?[field: "height"]?.selectionSet
    )

    // when
    let actual = selectionSet.computed.direct

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(beNil())
  }

  func test__mergedSelections_AllAnimalsQuery_AllAnimal_AsClassroomPet_AsBird_Height__isCorrect() async throws {
    // given
    try await buildOperation()

    let selectionSet = try XCTUnwrap(
      rootSelectionSet[field: "allAnimals"]?[as: "ClassroomPet"]?[as: "Bird"]?[field: "height"]?.selectionSet
    )

    expected = (
      fields: [
        .mock("feet",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("inches",
              type: .scalar(GraphQLScalarType.integer())),
        .mock("meters",
              type: .nonNull(.scalar(GraphQLScalarType.integer()))),
        .mock("relativeSize",
              type: .nonNull(.enum(GraphQLEnumType.relativeSize()))),
        .mock("centimeters",
              type: .nonNull(.scalar(GraphQLScalarType.float()))),
      ],
      typeCases: [],
      fragments: []
    )

    // when
    let actual = selectionSet.computed.merged

    // then
    expect(selectionSet.parentType).to(equal(GraphQLObjectType.mock("Height")))
    expect(actual).to(shallowlyMatch(self.expected))
  }

  // MARK: - Referenced Fragment Tests

  func test__referencedFragments__AllAnimalsQuery_isCorrect() async throws {
    // given
    let compilationResult = await compilationResult()
    let operation = compilationResult.operations.first { $0.name == "AllAnimalsQuery" }

    // when
    let expected: [CompilationResult.FragmentDefinition] = [
      "HeightInMeters",
      "WarmBloodedDetails",
      "PetDetails"
    ].map { expectedName in
      compilationResult.fragments.first(where:{ $0.name == expectedName })!
    }

    // then
    expect(operation?.referencedFragments).to(equal(expected))
  }

  func test__referencedFragments__HeightInMeters_isCorrect() async throws {
    // given
    let compilationResult = await compilationResult()
    let fragment = compilationResult.fragments.first { $0.name == "HeightInMeters" }

    // then
    expect(fragment?.referencedFragments).to(beEmpty())
  }

  func test__referencedFragments__WarmBloodedDetails_isCorrect() async throws {
    // given
    let compilationResult = await compilationResult()
    let fragment = compilationResult.fragments.first { $0.name == "WarmBloodedDetails" }

    // when
    let expected: [CompilationResult.FragmentDefinition] = [
      "HeightInMeters"
    ].map { expectedName in
      compilationResult.fragments.first(where:{ $0.name == expectedName })!
    }

    // then
    expect(fragment?.referencedFragments).to(equal(expected))
  }

  func test__referencedFragments__PetDetails_isCorrect() async throws {
    // given
    let compilationResult = await compilationResult()
    let fragment = compilationResult.fragments.first { $0.name == "PetDetails" }

    // then
    expect(fragment?.referencedFragments).to(beEmpty())
  }
}
