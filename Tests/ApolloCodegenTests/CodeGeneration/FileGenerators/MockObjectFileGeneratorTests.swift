import XCTest
import Nimble
@testable import ApolloCodegenLib
import GraphQLCompiler

class MockObjectFileGeneratorTests: XCTestCase {
  let graphqlObject = GraphQLObjectType.mock("MockObject", interfaces: [], fields: [:])

  var subject: MockObjectFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject() {
    subject = MockObjectFileGenerator(
      graphqlObject: graphqlObject,
      fields: [],
      ir: .mock(compilationResult: .mock()),
      config: ApolloCodegen.ConfigurationContext(config: .mock(.other))
    )
  }

  // MARK: Property Tests

  func test__properties__shouldReturnTargetType_testMock() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.testMock))
  }

  func test__properties__givenGraphQLObject_shouldReturnFileName_matchingObjectName() {
    // given
    buildSubject()

    let expected = "\(graphqlObject.name.schemaName)+Mock"

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
    expect(self.subject.fileName).to(equal("\(customName)+Mock"))
  }
}
