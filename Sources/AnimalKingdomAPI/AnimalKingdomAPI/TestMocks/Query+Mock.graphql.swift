// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public class Query: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Query
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Query>>

  public struct MockFields {
    @Field<[Animal]>("allAnimals") public var allAnimals
    @Field<[ClassroomPet?]>("classroomPets") public var classroomPets
    @Field<[Pet]>("findPet") public var findPet
    @Field<[Pet]>("pets") public var pets
  }
}

public extension Mock where O == Query {
  convenience init(
    allAnimals: [(any AnyMock)] = [],
    classroomPets: [(any AnyMock)?]? = nil,
    findPet: [(any AnyMock)] = [],
    pets: [(any AnyMock)] = []
  ) {
    self.init()
    _setList(allAnimals, for: \.allAnimals)
    _setList(classroomPets, for: \.classroomPets)
    _setList(findPet, for: \.findPet)
    _setList(pets, for: \.pets)
  }
}
