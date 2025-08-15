// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public final class Crocodile: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Crocodile
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Crocodile>>

  public struct MockFields: Sendable {
    @Field<Int>("age") public var age
    @Field<Height>("height") public var height
    @Field<AnimalKingdomAPI.ID>("id") public var id
    @Field<[Animal]>("predators") public var predators
    @Field<GraphQLEnum<AnimalKingdomAPI.SkinCovering>>("skinCovering") public var skinCovering
    @Field<String>("species") public var species
    @Field<String>("tag") public var tag
  }
}

public extension Mock where O == Crocodile {
  convenience init(
    age: Int = 0,
    height: Mock<Height> = Mock<Height>(),
    id: AnimalKingdomAPI.ID = "",
    predators: [(any AnyMock)] = [],
    skinCovering: GraphQLEnum<AnimalKingdomAPI.SkinCovering>? = nil,
    species: String = "",
    tag: String? = nil
  ) {
    self.init()
    _setScalar(age, for: \.age)
    _setEntity(height, for: \.height)
    _setScalar(id, for: \.id)
    _setList(predators, for: \.predators)
    _setScalar(skinCovering, for: \.skinCovering)
    _setScalar(species, for: \.species)
    _setScalar(tag, for: \.tag)
  }
}
