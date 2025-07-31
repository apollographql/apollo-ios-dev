// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public final class Rat: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Rat
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Rat>>

  public struct MockFields: Sendable {
    @Field<String>("favoriteToy") public var favoriteToy
    @Field<Height>("height") public var height
    @Field<String>("humanName") public var humanName
    @Field<AnimalKingdomAPI.ID>("id") public var id
    @Field<Human>("owner") public var owner
    @Field<[Animal]>("predators") public var predators
    @Field<GraphQLEnum<AnimalKingdomAPI.SkinCovering>>("skinCovering") public var skinCovering
    @Field<String>("species") public var species
  }
}

public extension Mock where O == Rat {
  convenience init(
    favoriteToy: String = "",
    height: Mock<Height> = Mock<Height>(),
    humanName: String? = nil,
    id: AnimalKingdomAPI.ID = "",
    owner: Mock<Human>? = nil,
    predators: [(any AnyMock)] = [],
    skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
    species: String = ""
  ) {
    self.init()
    _setScalar(favoriteToy, for: \.favoriteToy)
    _setEntity(height, for: \.height)
    _setScalar(humanName, for: \.humanName)
    _setScalar(id, for: \.id)
    _setEntity(owner, for: \.owner)
    _setList(predators, for: \.predators)
    _setScalar(skinCovering, for: \.skinCovering)
    _setScalar(species, for: \.species)
  }
}
