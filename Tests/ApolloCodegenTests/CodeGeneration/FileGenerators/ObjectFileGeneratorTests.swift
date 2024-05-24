import XCTest
import Nimble
@testable import ApolloCodegenLib
import GraphQLCompiler

class ObjectFileGeneratorTests: XCTestCase {
  let graphqlObject = GraphQLObjectType.mock("MockObject")

  var subject: ObjectFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject() {
    subject = ObjectFileGenerator(
      graphqlObject: graphqlObject,
      config: ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock())
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_object() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.object))
  }

  func test__properties__givenGraphQLObject_shouldReturnFileName_matchingObjectName() {
    // given
    buildSubject()

    let expected = graphqlObject.name.schemaName

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__givenGraphQLObject_shouldOverwrite() {
    // given
    buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }
  
  // MARK: Schema Customization Tests
  
  func test__filename_matchesCustomName() throws {
    // given
    let customName = "MyCustomObject"
    graphqlObject.name.customName = customName
    buildSubject()
    
    // then
    expect(self.subject.fileName).to(equal(customName))
  }
}
