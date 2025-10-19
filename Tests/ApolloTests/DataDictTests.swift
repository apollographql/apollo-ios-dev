import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import Nimble

class DataDictTests: XCTestCase {

  class Data: MockSelectionSet {
    class Animal: MockSelectionSet {
      class Predator: MockSelectionSet { }
    }
  }
  
  func test__encoding_simpleDataStructure_works() throws {
    // given
    let subject = DataDict(
      data: [
        "__typename": "Animal",
        "name": "Dog"
      ],
      fulfilledFragments: [],
      deferredFragments: []
    )

    // then
    expect(
      try JSONEncoder().encode(subject).jsonString()
    ).to(match("""
      {
        "__typename": "Animal",
        "name": "Dog"
      }
      """))
  }
  
  func test__encoding_nestedDataStructure_works() throws {
    // given
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

    // then
    expect(
      try JSONEncoder().encode(subject).jsonString()
    ).to(match("""
      {
        "animals": [
          {
            "__typename": "Animal",
            "name": "Dog"
          }, {
            "__typename": "Animal",
            "name": "Cat"
          }
        ]
      }
      """))
  }
  
  func test__encoding_dataStructureWithArrayProperties_works() throws {
    // givens
    let subject = DataDict(
      data: [
        "animals": [
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Dog"
            ],
            fulfilledFragments: [],
            deferredFragments: []
          ),
          DataDict(
            data: [
              "__typename": "Animal",
              "name": "Cat"
            ],
            fulfilledFragments: [],
            deferredFragments: []
          )
        ],
        "coordinates": [[1.0, 2.0], [3.0, 4.0], DataDict._NullValue],
      ],
      fulfilledFragments: []
    )

    // then
    expect(
      try JSONEncoder().encode(subject).jsonString()
    ).to(match("""
      {
        "animals": [
          {
            "__typename": "Animal",
            "name": "Dog"
          }, {
            "__typename": "Animal",
            "name": "Cat"
          }
        ],
        "coordinates": [
          [1.0, 2.0],
          [3.0, 4.0],
          null
        ]
      }
      """))
  }


}

extension Data {
  public func jsonString(ignoring ignoredKeys: [String] = []) throws -> String {
    var object = try JSONSerialization.jsonObject(with: self, options: [])
    if !ignoredKeys.isEmpty {
      object = (object as? [String: Any?])?
        .filter { !ignoredKeys.contains($0.key) } as Any
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    return String(data: data, encoding: .utf8)!
  }
}

func match(_ expectedValue: String) -> Matcher<String> {
  let expectedData = Data(expectedValue.utf8)

  let expectedString = try! expectedData.jsonString()
  return equal(expectedString)
}
