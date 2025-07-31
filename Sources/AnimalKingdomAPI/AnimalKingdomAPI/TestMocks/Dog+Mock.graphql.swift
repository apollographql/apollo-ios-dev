// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public final class Dog: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Dog
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Dog>>

  public struct MockFields: Sendable {
    @Field<AnimalKingdomAPI.CustomDate>("birthdate") public var birthdate
    @Field<Int32>("bodyTemperature") public var bodyTemperature
    @Field<String>("favoriteToy") public var favoriteToy
    @Field<Height>("height") public var height
    @Field<AnimalKingdomAPI.Object>("houseDetails") public var houseDetails
    @Field<String>("humanName") public var humanName
    @Field<AnimalKingdomAPI.ID>("id") public var id
    @Field<Bool>("laysEggs") public var laysEggs
    @Field<Human>("owner") public var owner
    @Field<[Animal]>("predators") public var predators
    @Field<GraphQLEnum<AnimalKingdomAPI.SkinCovering>>("skinCovering") public var skinCovering
    @Field<String>("species") public var species
  }
}

public extension Mock where O == Dog {
  convenience init(
    birthdate: AnimalKingdomAPI.CustomDate? = nil,
    bodyTemperature: Int32 = 0,
    favoriteToy: String = "",
    height: Mock<Height> = Mock<Height>(),
    houseDetails: AnimalKingdomAPI.Object? = nil,
    humanName: String? = nil,
    id: AnimalKingdomAPI.ID = "",
    laysEggs: Bool = false,
    owner: Mock<Human>? = nil,
    predators: [(any AnyMock)] = [],
    skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
    species: String = ""
  ) {
    self.init()
    _setScalar(birthdate, for: \.birthdate)
    _setScalar(bodyTemperature, for: \.bodyTemperature)
    _setScalar(favoriteToy, for: \.favoriteToy)
    _setEntity(height, for: \.height)
    _setScalar(houseDetails, for: \.houseDetails)
    _setScalar(humanName, for: \.humanName)
    _setScalar(id, for: \.id)
    _setScalar(laysEggs, for: \.laysEggs)
    _setEntity(owner, for: \.owner)
    _setList(predators, for: \.predators)
    _setScalar(skinCovering, for: \.skinCovering)
    _setScalar(species, for: \.species)
  }
}
