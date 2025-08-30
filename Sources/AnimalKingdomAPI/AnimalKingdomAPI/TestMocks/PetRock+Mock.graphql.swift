// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public class PetRock: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.PetRock
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<PetRock>>

  public struct MockFields {
    @Field<String>("favoriteToy") public var favoriteToy
    @Field<String>("humanName") public var humanName
    @Field<AnimalKingdomAPI.ID>("id") public var id
    @Field<Human>("owner") public var owner
  }
}

public extension Mock where O == PetRock {
  convenience init(
    favoriteToy: String = "",
    humanName: String? = nil,
    id: AnimalKingdomAPI.ID = "",
    owner: Mock<Human>? = nil
  ) {
    self.init()
    _setScalar(favoriteToy, for: \.favoriteToy)
    _setScalar(humanName, for: \.humanName)
    _setScalar(id, for: \.id)
    _setEntity(owner, for: \.owner)
  }
}
