import XCTest
import Nimble
import OrderedCollections
import IR
import GraphQLCompiler
@testable import ApolloCodegenLib

class MockInterfacesFileGeneratorTests: XCTestCase {
  static let mockInterface = GraphQLInterfaceType.mock("MockUnion")

  var subject: MockInterfacesFileGenerator!

  override func tearDown() {
    subject = nil
  }

  // MARK: Test Helpers

  private func buildSubject(interfaces: OrderedSet<GraphQLInterfaceType> = [mockInterface]) {
    let compilationResult = CompilationResult.mock(
      referencedTypes: interfaces.elements
    )    

    let ir = IRBuilder.mock(compilationResult: compilationResult)

    subject = MockInterfacesFileGenerator(
      ir: ir,
      config: ApolloCodegen.ConfigurationContext(config: .mock(.other))
    )
  }

  // MARK: Property Tests

  func test__init_givenNoInterfaces__shouldBeNil() {
    // given
    buildSubject(interfaces: [])

    // then
    expect(self.subject).to(beNil())
  }

  func test__properties__shouldReturnTargetType_testMock() {
    // given
    buildSubject()

    // then
    expect(self.subject.target).to(equal(.testMock))
  }

  func test__properties__shouldReturnFileName() {
    // given
    buildSubject()

    let expected = "MockObject+Interfaces"

    // then
    expect(self.subject.fileName).to(equal(expected))
  }

  func test__properties__overwrite_shouldBeTrue() {
    // given
    buildSubject()

    // then
    expect(self.subject.overwrite).to(beTrue())
  }
}
