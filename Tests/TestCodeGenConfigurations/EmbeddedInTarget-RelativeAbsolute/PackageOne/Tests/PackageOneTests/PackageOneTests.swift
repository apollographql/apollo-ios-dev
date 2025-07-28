import XCTest
@testable import PackageOne
import TestMocks
import ApolloTestSupport

final class PackageOneTests: XCTestCase {
  func testOperation() async {
    let mockDog = Mock<Dog>(species: "Canis familiaris")
    let mockQuery = Mock<Query>(dog: mockDog)
    let dogQuery = await DogQuery.Data.from(mockQuery)

    XCTAssertEqual(dogQuery.dog.species, "Canis familiaris")
  }
}
