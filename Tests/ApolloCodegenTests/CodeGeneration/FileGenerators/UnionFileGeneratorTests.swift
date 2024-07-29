import XCTest
import Nimble
@testable import ApolloCodegenLib
import GraphQLCompiler

class UnionFileGeneratorTests: XCTestCase {
  let graphqlUnion = GraphQLUnionType.mock("MockUnion", types: [])

  var subject: UnionFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject() {
    subject = UnionFileGenerator(
      graphqlUnion: graphqlUnion,
      config: ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock())
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_union() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.union))
  }

  func test__properties__givenGraphQLUnion_shouldReturnFileName_matchingUnionName() {
    // given
    buildSubject()

    let expected = graphqlUnion.name.schemaName

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__givenGraphQLUnion_shouldOverwrite() {
    // given
    buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }
  
  // MARK: Schema Customization Tests
  
  func test__filename_matchesCustomName() throws {
    // given
    let customName = "MyCustomUnion"
    graphqlUnion.name.customName = customName
    buildSubject()
    
    // then
    expect(self.subject.fileName).to(equal(customName))
  }
}
