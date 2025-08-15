import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class SelectionSet_EquatableTests: XCTestCase {

//  func test__equatable__typeCase_withExtraFulfilledFragment_returns_true() {
//    // given
//    class Hero: MockSelectionSet, @unchecked Sendable {
//      typealias Schema = MockSchemaMetadata
//
//      override class var __selections: [Selection] {[
//        .field("__typename", String.self),
//        .field("name", String?.self)
//      ]}
//
//      var name: String? { __data["name"] }
//    }
//
//    let object: JSONObject = [
//      "__typename": "Human",
//      "name": "Johnny Tsunami"
//    ]
//
//    // when
//    let selectionSet1 = MockSelectionSet(_dataDict: DataDict(
//      data: data,
//      fulfilledFragments: [ObjectIdentifier(MockSelectionSet.self)]
//    ))
//
//    let selectionSet2 = MockSelectionSet(_dataDict: DataDict(
//      data: data,
//      fulfilledFragments: []
//    ))
//
//    // then
//    expect(selectionSet1).to(equal(selectionSet2))
//    expect(selectionSet1.hashValue).to(equal(selectionSet2.hashValue))
//  }

}
