import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class DataDictMergingTests: XCTestCase {

  class Data: MockSelectionSet, @unchecked Sendable {
    class Animal: MockSelectionSet, @unchecked Sendable {
      class Predator: MockSelectionSet, @unchecked Sendable { }
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
          ],
          deferredFragments: [
            ObjectIdentifier(Data.Animal.Predator.self)
          ]
        ),
        DataDict(
          data: [
            "__typename": "Animal",
            "name": "Cat"
          ],
          fulfilledFragments: [
            ObjectIdentifier(Data.Animal.self),
          ],
          deferredFragments: [
            ObjectIdentifier(Data.Animal.Predator.self)
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
    let mergePath: [PathComponent] = []

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.emptyMergePath))
  }

  func test__merging__givenIndexPathForDataDictType_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
      .index(0),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.index(0), "DataDict")))
  }

  func test__merging__givenFieldPathForArrayType_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("animals"),
      .field("first"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.invalidPathComponentForDataType(.field("first"), "Array")))
  }

  func test__merging__givenInvalidFieldPath_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("nonexistent"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.field("nonexistent"))))
  }

  func test__merging__givenInvalidIndexPath_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("animals"),
      .index(3),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.cannotFindPathComponent(.index(3))))
  }

  func test__merging__givenPathToNonDataDictType_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("animals"),
    ]

    // then
    expect(
      try self.subject.merging(DataDict.empty(), at: mergePath)
    ).to(throwError(DataDict.MergeError.incrementalMergeNeedsDataDict))
  }

  func test__merging__givenPathToExistingFieldData_withNewValue_throwsError() throws {
    // given
    let mergePath: [PathComponent] = [
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
      try self.subject.merging(mergeDataDict, at: mergePath)
    ).to(throwError(DataDict.MergeError.cannotOverwriteFieldData("Animal", "NewValue")))
  }

  func test__merging__givenPathToExistingFieldData_withSameValue_doesNotThrowError() throws {
    // given
    let mergePath: [PathComponent] = [
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
      try self.subject.merging(mergeDataDict, at: mergePath)
    ).notTo(throwError())
  }

  // MARK: Merging

  func test__merging__givenFulfilledFragments_shouldAddFulfilledFragments_andRemoveMatchingDeferredFragments() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("animals"),
      .index(0),
    ]

    let mergeDataDict = DataDict(
      data: [
        "__typename": "Animal",
        "predators": [
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Coyote"
            ],
            fulfilledFragments: []
          )
        ]
      ],
      fulfilledFragments: [
        ObjectIdentifier(Data.Animal.Predator.self)
      ]
    )

    // then
    let data: DataDict = try self.subject.merging(mergeDataDict, at: mergePath)
    
    expect(data._fulfilledFragments).to(equal([
      ObjectIdentifier(Data.self)
    ]))

    let animals = data._data["animals"] as! [DataDict]
    let mergedAnimal = animals[0]
    let unmergedAnimal = animals[1]

    expect(mergedAnimal._fulfilledFragments).to(equal([
      ObjectIdentifier(Data.Animal.self),
      ObjectIdentifier(Data.Animal.Predator.self),
    ]))
    expect(mergedAnimal._deferredFragments).to(beEmpty())

    expect(unmergedAnimal._fulfilledFragments).to(equal([
      ObjectIdentifier(Data.Animal.self)
    ]))
    expect(unmergedAnimal._deferredFragments).to(equal([
      ObjectIdentifier(Data.Animal.Predator.self),
    ]))
  }

  func test__merging__givenSimpleMergePath_shouldMergeData() throws {
    // given
    let subject = DataDict(
      data: [
        "animal": DataDict(
          data: [
            "__typename": "Animal",
            "name": "Cat"
          ],
          fulfilledFragments: []
        )
      ],
      fulfilledFragments: []
    )

    let mergePath: [PathComponent] = [
      .field("animal"),
    ]

    let mergeDataDict = DataDict(
      data: [
        "__typename": "Animal",
        "colour": "Orange",
        "predators": [
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Coyote"
            ],
            fulfilledFragments: []
          )
        ]
      ],
      fulfilledFragments: []
    )

    // then
    let data: DataDict = try subject.merging(mergeDataDict, at: mergePath)
    let animal = data._data["animal"] as! DataDict

    expect(animal).to(equal(DataDict(
      data: [
        "__typename": "Animal",
        "name": "Cat",
        "colour": "Orange",
        "predators": [
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Coyote"
            ],
            fulfilledFragments: []
          )
        ]
      ],
      fulfilledFragments: []
    )))
  }

  func test__merging__givenMixedNestedMergePath_shouldMergeInNestedData() throws {
    // given
    let mergePath: [PathComponent] = [
      .field("animals"),
      .index(1),
    ]

    let mergeDataDict = DataDict(
      data: [
        "__typename": "Animal",
        "predators": [
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Coyote"
            ],
            fulfilledFragments: []
          )
        ]
      ],
      fulfilledFragments: []
    )

    // then
    let data: DataDict = try self.subject.merging(mergeDataDict, at: mergePath)
    let animals = data._data["animals"] as! [DataDict]

    expect(animals).to(haveCount(2))

    let unmergedAnimal = animals[0]
    let mergedAnimal = animals[1]

    expect(unmergedAnimal._data).to(equal([
      "__typename": "Animal",
      "name": "Dog",
    ]))

    expect(mergedAnimal._data).to(equal([
      "__typename": "Animal",
      "name": "Cat",
      "predators": [
        DataDict(
          data: [
            "__typename": "Animal",
            "name": "Coyote"
          ],
          fulfilledFragments: []
        )
      ]
    ]))
  }

}

