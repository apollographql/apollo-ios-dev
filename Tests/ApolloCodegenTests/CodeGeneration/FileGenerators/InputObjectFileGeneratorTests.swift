import XCTest
import Nimble
@testable import ApolloCodegenLib
import GraphQLCompiler

class InputObjectFileGeneratorTests: XCTestCase {
  let graphqlInputObject = GraphQLInputObjectType.mock("MockInputObject")

  var subject: InputObjectFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject() { 
    subject = InputObjectFileGenerator(
      graphqlInputObject: graphqlInputObject,
      config: ApolloCodegen.ConfigurationContext(config: ApolloCodegenConfiguration.mock())
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_inputObject() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.inputObject))
  }

  func test__properties__givenGraphQLInputObject_shouldReturnFileName_matchingInputObjectName() {
    // given
    buildSubject()

    let expected = graphqlInputObject.name.schemaName

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__givenGraphQLInputObject_shouldOverwrite() {
    // given
    buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }
  
  // MARK: Schema Customization Tests
  
  func test__filename_matchesCustomName() throws {
    // given
    let customName = "MyCustomInputObject"
    graphqlInputObject.name.customName = customName
    buildSubject()
    
    // then
    expect(self.subject.fileName).to(equal(customName))
  }
}
