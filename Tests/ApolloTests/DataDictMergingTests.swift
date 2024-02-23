import XCTest
@testable import Apollo
import ApolloAPI
import Nimble

class DataDictMergingTests: XCTestCase {

  // MARK: Errors

  func test__merging__givenEmptyPathComponent_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ]),
      ]
    ])

    let mergeDataDict = DataDict([
      "key": "value"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [])
    ).to(throwError(DataDict.MergeError.emptyMergePath))
  }

  func test__merging__givenIndexPathForDataDictType_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ]),
      ]
    ])

    let mergeDataDict = DataDict([
      "key": "value"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.index(0)])
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.index(0), "DataDict")))
  }

  func test__merging__givenFieldPathForArrayType_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ]),
      ]
    ])

    let mergeDataDict = DataDict([
      "key": "value"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("animals"), .field("first")])
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.field("first"), "Array")))
  }

  func test__merging__givenInvalidFieldPath_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ])
      ]
    ])

    let mergeDataDict = DataDict([
      "__typename": "Animal"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("nonexistent"), .index(0)])
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.field("nonexistent"))))
  }

  func test__merging__givenInvalidIndexPath_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ])
      ]
    ])

    let mergeDataDict = DataDict([
      "__typename": "Animal"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("animals"), .index(3)])
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.index(3))))
  }

  func test__merging__givenPathToNonDataDictType_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ]),
      ]
    ])

    let mergeDataDict = DataDict([
      "key": "value"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("animals")])
    ).to(throwError(DataDict.MergeError.incrementalMergeNeedsDataDict))
  }

  func test__merging__givenPathToExistingFieldData_withNewValue_throwsError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ])
      ]
    ])

    let mergeDataDict = DataDict([
      "__typename": "NewValue"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("animals"), .index(0)])
    ).to(throwError(DataDict.MergeError.cannotOverwriteFieldData("Animal", "NewValue")))
  }

  func test__merging__givenPathToExistingFieldData_withSameValue_doesNotThrowError() throws {
    // given
    let subject = DataDict([
      "animals": [
        DataDict([
          "__typename": "Animal",
          "name": "Dog"
        ]),
        DataDict([
          "__typename": "Animal",
          "name": "Cat"
        ])
      ]
    ])

    let mergeDataDict = DataDict([
      "__typename": "Animal"
    ])

    // then
    expect(
      try subject.merging(mergeDataDict, at: [.field("animals"), .index(0)])
    ).notTo(throwError())
  }

}

// MARK: - Helpers

extension DataDict {
  fileprivate init(_ data: [String: AnyHashable]) {
    self.init(data: data, fulfilledFragments: [])
  }
}
