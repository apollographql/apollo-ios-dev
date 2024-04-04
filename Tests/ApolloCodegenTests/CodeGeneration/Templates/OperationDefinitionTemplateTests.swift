import XCTest
import Nimble
import OrderedCollections
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class OperationDefinitionTemplateTests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var operation: IR.Operation!
  var config: ApolloCodegenConfiguration!
  var subject: OperationDefinitionTemplate!

  override func setUp() {
    super.setUp()
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

    config = .mock()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    operation = nil
    config = nil
    subject = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubjectAndOperation(named operationName: String = "TestOperation") async throws {
    ir = try await .mock(schema: schemaSDL, document: document)
    let operationDefinition = try XCTUnwrap(ir.compilationResult[operation: operationName])
    operation = await ir.build(operation: operationDefinition)
    subject = OperationDefinitionTemplate(
      operation: operation,
      operationIdentifier: nil,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: - Target Configuration Tests

  func test__target__givenModuleImports_targetHasModuleImports() async throws {
    // given
    document = """
    query TestOperation @import(module: "ModuleA") {
      allAnimals {
        species
      }
    }
    """

    // when
    try await buildSubjectAndOperation()

    guard case let .operationFile(actual) = subject.target else {
      fail("expected operationFile target")
      return
    }

    // then
    expect(actual).to(equal(["ModuleA"]))
  }

  // MARK: - Operation Definition Tests

  func test__generate__givenQuery_generatesQueryOperation() async throws {
    // given
    let expected =
    """
    class TestOperationQuery: GraphQLQuery {
      static let operationName: String = "TestOperation"
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate_givenQuery_configIncludesMarkOperationDefinitionsAsFinal_generatesFinalQueryDefinitions() async throws {
    // given
    let expected =
    """
    final class TestOperationQuery: GraphQLQuery {
      static let operationName: String = "TestOperation"
    """

    config = .mock(options: .init(markOperationDefinitionsAsFinal: true))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithNameEndingInQuery_generatesQueryOperationWithoutDoubledTypeSuffix() async throws {
    // given
    document = """
    query TestOperationQuery {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationQuery: GraphQLQuery {
      static let operationName: String = "TestOperationQuery"
    """

    // when
    try await buildSubjectAndOperation(named: "TestOperationQuery")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenMutationWithNameEndingInQuery_generatesQueryOperationWithBothSuffixes() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Mutation {
      addAnimal: Animal!
    }

    type Animal {
      species: String!
    }
    """

    document = """
    mutation TestOperationQuery {
      addAnimal {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationQueryMutation: GraphQLMutation {
      static let operationName: String = "TestOperationQuery"
    """

    // when
    try await buildSubjectAndOperation(named: "TestOperationQuery")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenMutation_generatesMutationOperation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Mutation {
      addAnimal: Animal!
    }

    type Animal {
      species: String!
    }
    """

    document = """
    mutation TestOperation {
      addAnimal {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationMutation: GraphQLMutation {
      static let operationName: String = "TestOperation"
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenSubscription_generatesSubscriptionOperation() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Subscription {
      streamAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    subscription TestOperation {
      streamAnimals {
        species
      }
    }
    """

    let expected =
    """
    class TestOperationSubscription: GraphQLSubscription {
      static let operationName: String = "TestOperation"
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithLowercasing_generatesCorrectlyCasedQueryOperation() async throws {
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
    query lowercaseOperation($variable: String = "TestVar") {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    class LowercaseOperationQuery: GraphQLQuery {
      static let operationName: String = "lowercaseOperation"
      static let operationDocument: ApolloAPI.OperationDocument = .init(
        definition: .init(
          #\"query lowercaseOperation($variable: String = \"TestVar\") { allAnimals { __typename species } }\"#
    """

    // when
    try await buildSubjectAndOperation(named: "lowercaseOperation")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: - Selection Set Declaration

  func test__generate__givenOperationSelectionSet_rendersDeclaration() async throws {
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
      struct Data: TestSchema.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: ApolloAPI.ParentType { TestSchema.Objects.Query }
    """

    // when
    try await buildSubjectAndOperation()
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 10, ignoringExtraLines: true))
  }

  // MARK: - Selection Set Initializers

  func test__generate_givenOperationSelectionSet_configIncludesOperations_rendersInitializer() async throws {
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
                  ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
                ]
              ))
            }
      """

    config = .mock(options: .init(selectionSetInitializers: [.operations]))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 50, ignoringExtraLines: true))
  }

  func test__generate_givenOperationSelectionSet_configIncludesSpecificOperation_rendersInitializer() async throws {
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
                  ObjectIdentifier(TestOperationQuery.Data.AllAnimal.self)
                ]
              ))
            }
      """

    config = .mock(options: .init(selectionSetInitializers: [
      .operation(named: "TestOperation")
    ]))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 50, ignoringExtraLines: true))
  }

  func test__render_givenOperationSelectionSet_configDoesNotIncludeOperations_doesNotRenderInitializer() async throws {
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

    config = .mock(options: .init(selectionSetInitializers: [.namedFragments]))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine("    }", atLine: 35, ignoringExtraLines: true))
  }

  func test__render_givenOperationSelectionSet_configIncludeSpecificOperationWithOtherName_doesNotRenderInitializer() async throws {
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

    config = .mock(options: .init(selectionSetInitializers: [
      .operation(named: "OtherOperation")
    ]))

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine("    }", atLine: 35, ignoringExtraLines: true))
  }

  // MARK: - Variables

  func test__generate__givenQueryWithScalarVariable_generatesQueryOperationWithVariable() async throws {
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
    query TestOperation($variable: String!) {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable: String

      public init(variable: String) {
        self.variable = variable
      }

      public var __variables: Variables? { ["variable": variable] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithMutlipleScalarVariables_generatesQueryOperationWithVariables() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
      intField: Int!
    }
    """

    document = """
    query TestOperation($variable1: String!, $variable2: Boolean!, $variable3: Int!) {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable1: String
      public var variable2: Bool
      public var variable3: Int

      public init(
        variable1: String,
        variable2: Bool,
        variable3: Int
      ) {
        self.variable1 = variable1
        self.variable2 = variable2
        self.variable3 = variable3
      }

      public var __variables: Variables? { [
        "variable1": variable1,
        "variable2": variable2,
        "variable3": variable3
      ] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithNullableScalarVariable_generatesQueryOperationWithVariable() async throws {
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
    query TestOperation($variable: String = "TestVar") {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable: GraphQLNullable<String>
    
      public init(variable: GraphQLNullable<String> = "TestVar") {
        self.variable = variable
      }

      public var __variables: Variables? { ["variable": variable] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  func test__generate__givenQueryWithCapitalizedVariable_generatesQueryOperationWithLowercaseVariable() async throws {
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
    query TestOperation($Variable: String) {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var variable: GraphQLNullable<String>

      public init(variable: GraphQLNullable<String>) {
        self.variable = variable
      }

      public var __variables: Variables? { ["Variable": variable] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }

  // MARK: Variables - Reserved Keywords + Special Names

  func test__generate__givenQueryWithSwiftReservedKeywordNames_generatesQueryOperationWithVariablesBackticked() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
      intField: Int!
    }
    """

    document = """
    query TestOperation(
      $as: String
      $associatedtype: String
      $break: String
      $case: String
      $catch: String
      $class: String
      $continue: String
      $default: String
      $defer: String
      $deinit: String
      $do: String
      $else: String
      $enum: String
      $extension: String
      $fallthrough: String
      $false: String
      $fileprivate: String
      $for: String
      $func: String
      $guard: String
      $if: String
      $import: String
      $in: String
      $init: String
      $inout: String
      $internal: String
      $is: String
      $let: String
      $nil: String
      $operator: String
      $precedencegroup: String
      $private: String
      $protocol: String
      $public: String
      $repeat: String
      $rethrows: String
      $return: String
      $static: String
      $struct: String
      $subscript: String
      $super: String
      $switch: String
      $throw: String
      $throws: String
      $true: String
      $try: String
      $typealias: String
      $var: String
      $where: String
      $while: String
    ) {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      public var `as`: GraphQLNullable<String>
      public var `associatedtype`: GraphQLNullable<String>
      public var `break`: GraphQLNullable<String>
      public var `case`: GraphQLNullable<String>
      public var `catch`: GraphQLNullable<String>
      public var `class`: GraphQLNullable<String>
      public var `continue`: GraphQLNullable<String>
      public var `default`: GraphQLNullable<String>
      public var `defer`: GraphQLNullable<String>
      public var `deinit`: GraphQLNullable<String>
      public var `do`: GraphQLNullable<String>
      public var `else`: GraphQLNullable<String>
      public var `enum`: GraphQLNullable<String>
      public var `extension`: GraphQLNullable<String>
      public var `fallthrough`: GraphQLNullable<String>
      public var `false`: GraphQLNullable<String>
      public var `fileprivate`: GraphQLNullable<String>
      public var `for`: GraphQLNullable<String>
      public var `func`: GraphQLNullable<String>
      public var `guard`: GraphQLNullable<String>
      public var `if`: GraphQLNullable<String>
      public var `import`: GraphQLNullable<String>
      public var `in`: GraphQLNullable<String>
      public var `init`: GraphQLNullable<String>
      public var `inout`: GraphQLNullable<String>
      public var `internal`: GraphQLNullable<String>
      public var `is`: GraphQLNullable<String>
      public var `let`: GraphQLNullable<String>
      public var `nil`: GraphQLNullable<String>
      public var `operator`: GraphQLNullable<String>
      public var `precedencegroup`: GraphQLNullable<String>
      public var `private`: GraphQLNullable<String>
      public var `protocol`: GraphQLNullable<String>
      public var `public`: GraphQLNullable<String>
      public var `repeat`: GraphQLNullable<String>
      public var `rethrows`: GraphQLNullable<String>
      public var `return`: GraphQLNullable<String>
      public var `static`: GraphQLNullable<String>
      public var `struct`: GraphQLNullable<String>
      public var `subscript`: GraphQLNullable<String>
      public var `super`: GraphQLNullable<String>
      public var `switch`: GraphQLNullable<String>
      public var `throw`: GraphQLNullable<String>
      public var `throws`: GraphQLNullable<String>
      public var `true`: GraphQLNullable<String>
      public var `try`: GraphQLNullable<String>
      public var `typealias`: GraphQLNullable<String>
      public var `var`: GraphQLNullable<String>
      public var `where`: GraphQLNullable<String>
      public var `while`: GraphQLNullable<String>

      public init(
        `as`: GraphQLNullable<String>,
        `associatedtype`: GraphQLNullable<String>,
        `break`: GraphQLNullable<String>,
        `case`: GraphQLNullable<String>,
        `catch`: GraphQLNullable<String>,
        `class`: GraphQLNullable<String>,
        `continue`: GraphQLNullable<String>,
        `default`: GraphQLNullable<String>,
        `defer`: GraphQLNullable<String>,
        `deinit`: GraphQLNullable<String>,
        `do`: GraphQLNullable<String>,
        `else`: GraphQLNullable<String>,
        `enum`: GraphQLNullable<String>,
        `extension`: GraphQLNullable<String>,
        `fallthrough`: GraphQLNullable<String>,
        `false`: GraphQLNullable<String>,
        `fileprivate`: GraphQLNullable<String>,
        `for`: GraphQLNullable<String>,
        `func`: GraphQLNullable<String>,
        `guard`: GraphQLNullable<String>,
        `if`: GraphQLNullable<String>,
        `import`: GraphQLNullable<String>,
        `in`: GraphQLNullable<String>,
        `init`: GraphQLNullable<String>,
        `inout`: GraphQLNullable<String>,
        `internal`: GraphQLNullable<String>,
        `is`: GraphQLNullable<String>,
        `let`: GraphQLNullable<String>,
        `nil`: GraphQLNullable<String>,
        `operator`: GraphQLNullable<String>,
        `precedencegroup`: GraphQLNullable<String>,
        `private`: GraphQLNullable<String>,
        `protocol`: GraphQLNullable<String>,
        `public`: GraphQLNullable<String>,
        `repeat`: GraphQLNullable<String>,
        `rethrows`: GraphQLNullable<String>,
        `return`: GraphQLNullable<String>,
        `static`: GraphQLNullable<String>,
        `struct`: GraphQLNullable<String>,
        `subscript`: GraphQLNullable<String>,
        `super`: GraphQLNullable<String>,
        `switch`: GraphQLNullable<String>,
        `throw`: GraphQLNullable<String>,
        `throws`: GraphQLNullable<String>,
        `true`: GraphQLNullable<String>,
        `try`: GraphQLNullable<String>,
        `typealias`: GraphQLNullable<String>,
        `var`: GraphQLNullable<String>,
        `where`: GraphQLNullable<String>,
        `while`: GraphQLNullable<String>
      ) {
        self.`as` = `as`
        self.`associatedtype` = `associatedtype`
        self.`break` = `break`
        self.`case` = `case`
        self.`catch` = `catch`
        self.`class` = `class`
        self.`continue` = `continue`
        self.`default` = `default`
        self.`defer` = `defer`
        self.`deinit` = `deinit`
        self.`do` = `do`
        self.`else` = `else`
        self.`enum` = `enum`
        self.`extension` = `extension`
        self.`fallthrough` = `fallthrough`
        self.`false` = `false`
        self.`fileprivate` = `fileprivate`
        self.`for` = `for`
        self.`func` = `func`
        self.`guard` = `guard`
        self.`if` = `if`
        self.`import` = `import`
        self.`in` = `in`
        self.`init` = `init`
        self.`inout` = `inout`
        self.`internal` = `internal`
        self.`is` = `is`
        self.`let` = `let`
        self.`nil` = `nil`
        self.`operator` = `operator`
        self.`precedencegroup` = `precedencegroup`
        self.`private` = `private`
        self.`protocol` = `protocol`
        self.`public` = `public`
        self.`repeat` = `repeat`
        self.`rethrows` = `rethrows`
        self.`return` = `return`
        self.`static` = `static`
        self.`struct` = `struct`
        self.`subscript` = `subscript`
        self.`super` = `super`
        self.`switch` = `switch`
        self.`throw` = `throw`
        self.`throws` = `throws`
        self.`true` = `true`
        self.`try` = `try`
        self.`typealias` = `typealias`
        self.`var` = `var`
        self.`where` = `where`
        self.`while` = `while`
      }

      public var __variables: Variables? { [
        "as": `as`,
        "associatedtype": `associatedtype`,
        "break": `break`,
        "case": `case`,
        "catch": `catch`,
        "class": `class`,
        "continue": `continue`,
        "default": `default`,
        "defer": `defer`,
        "deinit": `deinit`,
        "do": `do`,
        "else": `else`,
        "enum": `enum`,
        "extension": `extension`,
        "fallthrough": `fallthrough`,
        "false": `false`,
        "fileprivate": `fileprivate`,
        "for": `for`,
        "func": `func`,
        "guard": `guard`,
        "if": `if`,
        "import": `import`,
        "in": `in`,
        "init": `init`,
        "inout": `inout`,
        "internal": `internal`,
        "is": `is`,
        "let": `let`,
        "nil": `nil`,
        "operator": `operator`,
        "precedencegroup": `precedencegroup`,
        "private": `private`,
        "protocol": `protocol`,
        "public": `public`,
        "repeat": `repeat`,
        "rethrows": `rethrows`,
        "return": `return`,
        "static": `static`,
        "struct": `struct`,
        "subscript": `subscript`,
        "super": `super`,
        "switch": `switch`,
        "throw": `throw`,
        "throws": `throws`,
        "true": `true`,
        "try": `try`,
        "typealias": `typealias`,
        "var": `var`,
        "where": `where`,
        "while": `while`
      ] }
    """

    // when
    try await buildSubjectAndOperation()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 8, ignoringExtraLines: true))
  }
  
  // MARK: - Reserved Keyword Tests
  
  func test__generate__givenInputObjectUsingReservedKeyword_rendersAsEscapedType() async throws {
    // given
    schemaSDL = """
    input Type {
      id: String!
    }

    type Query {
      getUser(type: Type!): User
    }

    type User {
      id: String!
      name: String!
      role: String!
    }
    """

    document = """
    query TestOperation($type: Type!) {
        getUser(type: $type) {
            name
        }
    }
    """

    let expectedOne = """
      public var type: Type_InputObject
    """
    
    let expectedTwo = """
      public init(type: Type_InputObject) {
    """

    // when
    try await buildSubjectAndOperation()
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expectedOne, atLine: 8, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedTwo, atLine: 10, ignoringExtraLines: true))
  }
  
  // MARK: - Defer Metadata
  
  func test__generateMetadata__whenContainsDeferredFragment_rendersDeferMetadata() async throws {
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
    try await buildSubjectAndOperation()
    let actual = renderSubject()
    
    // then
    expect(self.operation.containsDeferredFragment).to(beTrue())
    
    expect(actual).to(equalLineByLine(
      """
      }
      
      // MARK: Deferred Fragment Metadata
      
      extension TestOperationQuery {
      """,
      atLine: 61,
      ignoringExtraLines: true
    ))
    
    expect(actual).to(equalLineByLine(
      """
      }
      """,
      atLine: 73,
      ignoringExtraLines: false
    ))
  }
  
  func test__generateMetadata__whenDoesNotContainDeferredFragment_doesNotRenderDeferMetadata() async throws {
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
        species
      }
    }
    """

    // when
    try await buildSubjectAndOperation()
    let actual = renderSubject()
    
    // then
    expect(self.operation.containsDeferredFragment).to(beFalse())
    
    expect(actual).to(equalLineByLine(
      """
      }
      """,
      atLine: 37,
      ignoringExtraLines: false
    ))
  }
}
