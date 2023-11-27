// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension MyAPI.Unions {
  static let ClassroomPet = Union(
    name: "ClassroomPet",
    possibleTypes: [
      MyAPI.Objects.Cat.self,
      MyAPI.Objects.Bird.self,
      MyAPI.Objects.Rat.self,
      MyAPI.Objects.PetRock.self
    ]
  )
}