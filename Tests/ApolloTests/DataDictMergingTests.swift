import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class DataDictMergingTests: XCTestCase {

  class Data: MockSelectionSet {
    class Animal: MockSelectionSet {
      class Predator: MockSelectionSet { }
    }
  }

  let subject = DataDict(
    data: [
      "animals": [
        DataDict(
          data: [
            "__typename": "Animal",
            "name": "Dog"
          ],
          fulfilledFragments: [
            ObjectIdentifier(Data.Animal.self),
          ]
        ),
        DataDict(
          data: [
            "__typename": "Animal",
            "name": "Cat"
          ],
          fulfilledFragments: [
            ObjectIdentifier(Data.Animal.self),
          ]
        )
      ]
    ],
    fulfilledFragments: [
      ObjectIdentifier(Data.self),
    ]
  )

  // MARK: Errors

  func test__merging__givenEmptyPathComponent_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = []

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: pathComponents)
    ).to(throwError(DataDict.MergeError.emptyMergePath))
  }

  func test__merging__givenIndexPathForDataDictType_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .index(0),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: [.index(0)])
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.index(0), "DataDict")))
  }

  func test__merging__givenFieldPathForArrayType_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("animals"),
      .field("first"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: pathComponents)
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.field("first"), "Array")))
  }

  func test__merging__givenInvalidFieldPath_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("nonexistent"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: pathComponents)
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.field("nonexistent"))))
  }

  func test__merging__givenInvalidIndexPath_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("animals"),
      .index(3),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: pathComponents)
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.index(3))))
  }

  func test__merging__givenPathToNonDataDictType_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("animals"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: pathComponents)
    ).to(throwError(DataDict.MergeError.incrementalMergeNeedsDataDict))
  }

  func test__merging__givenPathToExistingFieldData_withNewValue_throwsError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("animals"),
      .index(0),
    ]

    let mergeDataDict = DataDict(
      data: [
      "__typename": "NewValue"
      ],
      fulfilledFragments: []
    )

    // then
    expect(
      try self.subject.merging(mergeDataDict, at: pathComponents)
    ).to(throwError(DataDict.MergeError.cannotOverwriteFieldData("Animal", "NewValue")))
  }

  func test__merging__givenPathToExistingFieldData_withSameValue_doesNotThrowError() throws {
    // given
    let pathComponents: [PathComponent] = [
      .field("animals"),
      .index(0),
    ]

    let mergeDataDict = DataDict(
      data: [
        "__typename": "Animal"
      ],
      fulfilledFragments: []
    )

    // then
    expect(
      try self.subject.merging(mergeDataDict, at: pathComponents)
    ).notTo(throwError())
  }

}
