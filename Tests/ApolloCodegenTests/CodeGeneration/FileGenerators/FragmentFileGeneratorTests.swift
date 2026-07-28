import XCTest
import Nimble
import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class FragmentFileGeneratorTests: XCTestCase {
  var irFragment: IR.NamedFragment!
  var subject: FragmentFileGenerator!
  var operationDocument: String!

  override func setUp() {
    super.setUp()
    operationDocument = """
    query AllAnimals {
      animals {
        ...animalDetails
      }
    }

    fragment animalDetails on Animal {
      species
    }
    """
  }

  override func tearDown() {
    subject = nil
    irFragment = nil
    operationDocument = nil
    
    super.tearDown()
  }

  // MARK: Test Helpers

  private func buildSubject(config: ApolloCodegenConfiguration = .mock()) async throws {
    let schemaSDL = """
    type Animal {
      species: String
    }

    type Query {
      animals: [Animal]
    }
    """

    let ir = try await IRBuilder.mock(schema: schemaSDL, document: operationDocument)
    irFragment = await ir.build(fragment: ir.compilationResult.fragments[0])

    subject = FragmentFileGenerator(
      irFragment: irFragment,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_fragment() async throws {
    // given
    try await buildSubject()

    let expected: FileTarget = .fragment(irFragment.definition)

    // then
    expect(self.subject.target).to(equal(expected))
  }

  func test__properties__givenGraphQLFragment_shouldReturnFileName_matchingFragmentDefinitionName() async throws {
    // given
    try await buildSubject()

    let expected = irFragment.definition.name

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__givenGraphQLFragmentWithCapitalizationRules_shouldReturnFileName_withRulesApplied() async throws {
    // given
    operationDocument = """
    query AllAnimals {
      animals {
        ...IDDetails
      }
    }

    fragment IDDetails on Animal {
      species
    }
    """

    try await buildSubject(config: .mock(options: .init(
      additionalCapitalizationRules: [.init(term: .string("id"), strategy: .lower)],
      schemaDocumentation: .exclude,
      markTypesNonisolated: false
    )))

    // then
    // File names apply the rules to the raw fragment name (no leading-capital normalization),
    // so the lowercased leading segment stays lowercase, unlike the generated type name `IdDetails`.
    expect(self.subject.fileName).to(equal("idDetails"))
  }

  func test__properties__givenGraphQLFragmentWithReplaceCapitalizationRule_shouldReturnFileName_withReplacementApplied() async throws {
    // given
    operationDocument = """
    query AllAnimals {
      animals {
        ...GraphqlConfig
      }
    }

    fragment GraphqlConfig on Animal {
      species
    }
    """

    try await buildSubject(config: .mock(options: .init(
      additionalCapitalizationRules: [.init(term: .string("graphql"), strategy: .replace("graphQL"))],
      schemaDocumentation: .exclude,
      markTypesNonisolated: false
    )))

    // then
    expect(self.subject.fileName).to(equal("graphQLConfig"))
  }

  func test__properties__givenGraphQLFragment_shouldOverwrite() async throws {
    // given
    try await buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }
  
}
