// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
import AnimalKingdomAPI

public class Query: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Query
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Query>>

  public struct MockFields {
    @Field<[Animal]>("allAnimals") public var allAnimals
    @Field<[ClassroomPet?]>("classroomPets") public var classroomPets
    @Field<[Pet]>("pets") public var pets
  }
}

public extension Mock where O == Query {
  convenience init(
    allAnimals: [(any AnyMock)]? = nil,
    classroomPets: [(any AnyMock)?]? = nil,
    pets: [(any AnyMock)]? = nil
  ) {
    self.init()
    _setList(allAnimals, for: \.allAnimals)
    _setList(classroomPets, for: \.classroomPets)
    _setList(pets, for: \.pets)
  }
}
