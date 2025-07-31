// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import AnimalKingdomAPI

public final class Height: MockObject {
  public static let objectType: ApolloAPI.Object = AnimalKingdomAPI.Objects.Height
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Height>>

  public struct MockFields: Sendable {
    @Field<Double>("centimeters") public var centimeters
    @Field<Int32>("feet") public var feet
    @Field<Int32>("inches") public var inches
    @Field<Int32>("meters") public var meters
    @Field<GraphQLEnum<AnimalKingdomAPI.RelativeSize>>("relativeSize") public var relativeSize
  }
}

public extension Mock where O == Height {
  convenience init(
    centimeters: Double = 0.0,
    feet: Int32 = 0,
    inches: Int32? = nil,
    meters: Int32 = 0,
    relativeSize: GraphQLEnum<AnimalKingdomAPI.RelativeSize> = .case(.large)
  ) {
    self.init()
    _setScalar(centimeters, for: \.centimeters)
    _setScalar(feet, for: \.feet)
    _setScalar(inches, for: \.inches)
    _setScalar(meters, for: \.meters)
    _setScalar(relativeSize, for: \.relativeSize)
  }
}
