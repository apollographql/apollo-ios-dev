// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Objects {
  static let Dog = ApolloAPI.Object(
    typename: "Dog",
    implementedInterfaces: [
      Interfaces.Animal.self,
      Interfaces.Pet.self,
      Interfaces.HousePet.self,
      Interfaces.WarmBlooded.self
    ],
    keyFields: ["id"]
  )
}