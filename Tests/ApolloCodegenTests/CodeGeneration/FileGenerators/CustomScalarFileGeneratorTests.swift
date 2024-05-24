import XCTest
import Nimble
@testable import ApolloCodegenLib
import GraphQLCompiler

class CustomScalarFileGeneratorTests: XCTestCase {
  let graphqlScalar = GraphQLScalarType.mock(name: "MockCustomScalar")

  var subject: CustomScalarFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject() {
    subject = CustomScalarFileGenerator(
      graphqlScalar: graphqlScalar,
      config: ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock())
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_customScalar() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.customScalar))
  }

  func test__properties__givenGraphQLScalar_shouldReturnFileName_matchingScalarName() {
    // given
    buildSubject()

    let expected = graphqlScalar.name.schemaName

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__givenGraphQLScalar_shouldNotOverwrite() {
    // given
    buildSubject()

    // then
    expect(self.subject.overwrite).to(beFalse())
  }
  
  // MARK: Schema Customization Tests
  
  func test__filename_matchesCustomName() throws {
    // given
    let customName = "MyCustomScalar"
    graphqlScalar.name.customName = customName
    buildSubject()
    
    // then
    expect(self.subject.fileName).to(equal(customName))
  }
  
}
