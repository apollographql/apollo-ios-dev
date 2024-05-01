@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers
import XCTest
import Nimble

class IncrementalJSONResponseParsingInterceptorTests: XCTestCase {

  class CatQuery: MockQuery<CatQuery.CatSelectionSet> {
    class CatSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("isJellicle", Bool.self)
      ]}
    }
  }

  class DogQuery: MockQuery<DogQuery.DogSelectionSet> {
    class DogSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("favouriteToy", String.self)
      ]}
    }
  }

  class AnimalQuery: MockQuery<AnimalQuery.AnAnimal> {
    class AnAnimal: MockSelectionSet {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata> {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("species", String.self),
          .deferred(DeferredGenus.self, label: "deferredGenus"),
          .deferred(DeferredFriend.self, label: "deferredFriend"),
        ]}

        var species: String { __data["species"] }

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredGenus = Deferred(_dataDict: _dataDict)
            _deferredFriend = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredGenus: DeferredGenus?
          @Deferred var deferredFriend: DeferredFriend?
        }

        class DeferredGenus: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("genus", String.self),
          ]}

          var genus: String { __data["genus"] }
        }

        class DeferredFriend: MockTypeCase {
          override class var __selections: [Selection] {[
            .field("friend", Friend.self),
          ]}

          var friend: Friend { __data["friend"] }

          class Friend: MockSelectionSet {
            override class var __selections: [Selection] {[
              .field("name", String.self),
            ]}

            var name: String { __data["name"] }
          }
        }
      }
    }

    override class var deferredFragments: [DeferredFragmentIdentifier : any SelectionSet.Type]? {[
      DeferredFragmentIdentifier(label: "deferredGenus", fieldPath: ["animal"]): AnAnimal.Animal.DeferredGenus.self,
      DeferredFragmentIdentifier(label: "deferredFriend", fieldPath: ["animal"]): AnAnimal.Animal.DeferredFriend.self,
    ]}
  }

  let defaultTimeout = 0.5

  // MARK: - Errors

  func test__errors__givenNoResponse_shouldThrow() {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    // when
    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: nil
    ) { result in
      defer {
        expectation.fulfill()
      }

      // then
      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(IncrementalJSONResponseParsingInterceptor.ParsingError.noResponseToParse)
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenEmptyDataResponse_shouldThrow() {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")

    // when
    subject.intercept(
      request: .mock(operation: MockQuery.mock()),
      response: .mock(data: Data())
    ) { result in
      defer {
        expectation.fulfill()
      }

      // then
      expect(result).to(beFailure { error in
        expect(error).to(
          matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.couldNotParseToJSON(data: Data())
          )
        )
      })
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenIncrementalResponse_withMismatchedPartialResult_shouldThrow() {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")
    expectation.expectedFulfillmentCount = 2

    // when
    subject.intercept(
      request: .mock(operation: CatQuery()),
      response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
    ) { result in

      // then
      expect(result).to(beSuccess())
      expectation.fulfill()

      subject.intercept(
        request: .mock(operation: DogQuery()),
        response: .mock(data: #"{"incremental":{"favouriteToy":"Stick"}}"#.data(using: .utf8)!)
      ) { result in

        expect(result).to(beFailure { error in
          expect(error).to(matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.mismatchedCurrentResultType
          ))
          expectation.fulfill()
        })
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test_errors_givenResponse_withMissingIncrementalKey_shouldThrow() {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let expectation = expectation(description: "Received callback")
    expectation.expectedFulfillmentCount = 2

    // when
    subject.intercept(
      request: .mock(operation: CatQuery()),
      response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
    ) { result in

      // then
      expect(result).to(beSuccess())
      expectation.fulfill()

      subject.intercept(
        request: .mock(operation: CatQuery()),
        response: .mock(data: #"{"data":{"isJellicle":false}}"#.data(using: .utf8)!)
      ) { result in

        expect(result).to(beFailure { error in
          expect(error).to(matchError(
            IncrementalJSONResponseParsingInterceptor.ParsingError.couldNotParseIncrementalJSON(
              json: ["data": ["isJellicle": false]]
            )
          ))
          expectation.fulfill()
        })
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  // MARK: Parsing tests

  func test__parsing__givenSingleIncrementalResult_shouldMergeResult() throws {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let partialExpectation = expectation(description: "Received partial response callback")
    let incrementalExpectation = expectation(description: "Received incremental response callback")

    // when
    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "data": {
            "animal": {
              "__typename": "Animal",
              "species": "Canis Familiaris"
            }
          }
        }
        """.data(using: .utf8)!)
    ) { result in
      defer {
        partialExpectation.fulfill()
      }

      // then
      expect(result).to(beSuccess())

      let graphQLResult = try? result.get()?.parsedResponse
      expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
      expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(beNil())
      expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend).to(beNil())
    }

    wait(for: [partialExpectation], timeout: defaultTimeout)

    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "incremental": [{
            "label": "deferredGenus",
            "data": {
              "genus": "Canis"
            },
            "path": [
              "animal"
            ]
          }]
        }
        """.data(using: .utf8)!
      )
    ) { result in
      defer {
        incrementalExpectation.fulfill()
      }

      expect(result).to(beSuccess())

      let graphQLResult = try? result.get()?.parsedResponse
      expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
      expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend).to(beNil())
    }

    wait(for: [incrementalExpectation], timeout: defaultTimeout)
  }

  func test__parsing__givenMultipleIncrementalResults_shouldMergeResults() throws {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let partialExpectation = expectation(description: "Received partial response callback")
    let incrementalExpectation = expectation(description: "Received incremental response callback")

    // when
    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "data": {
            "animal": {
              "__typename": "Animal",
              "species": "Canis Familiaris"
            }
          }
        }
        """.data(using: .utf8)!)
    ) { result in
      defer {
        partialExpectation.fulfill()
      }

      // then
      expect(result).to(beSuccess())

      let graphQLResult = try? result.get()?.parsedResponse
      expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
      expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(beNil())
      expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend).to(beNil())
    }

    wait(for: [partialExpectation], timeout: defaultTimeout)

    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "incremental": [
            {
              "label": "deferredGenus",
              "data": {
                "genus": "Canis"
              },
              "path": [
                "animal"
              ]
            },
            {
              "label": "deferredFriend",
              "data": {
                "friend": {
                  "name": "Buster"
                }
              },
              "path": [
                "animal"
              ]
            }
          ]
        }
        """.data(using: .utf8)!
      )
    ) { result in
      defer {
        incrementalExpectation.fulfill()
      }

      expect(result).to(beSuccess())

      let graphQLResult = try? result.get()?.parsedResponse
      expect(graphQLResult?.data?.animal.species).to(equal("Canis Familiaris"))
      expect(graphQLResult?.data?.animal.fragments.deferredGenus?.genus).to(equal("Canis"))
      expect(graphQLResult?.data?.animal.fragments.deferredFriend?.friend.name).to(equal("Buster"))
    }

    wait(for: [incrementalExpectation], timeout: defaultTimeout)
  }

  // MARK: Cache Records Tests

  func test__cacheRecords__givenMultipleIncrementalObjectsInSingleIncrementalResponse_shouldMergeCacheRecordsForIncrementalResult() throws {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let partialExpectation = expectation(description: "Received partial response callback")
    let incrementalExpectation = expectation(description: "Received incremental response callback")

    // when
    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "data": {
            "animal": {
              "__typename": "Animal",
              "species": "Canis Familiaris"
            }
          }
        }
        """.data(using: .utf8)!)
    ) { result in
      defer {
        partialExpectation.fulfill()
      }

      // then
      expect(result).to(beSuccess())

      let cacheRecords = try? result.get()?.cacheRecords
      expect(cacheRecords).to(equal(RecordSet(records: [
        Record(key: "QUERY_ROOT", [
          "animal": CacheReference("QUERY_ROOT.animal")
        ]),
        Record(key: "QUERY_ROOT.animal", [
          "__typename": "Animal",
          "species": "Canis Familiaris"
        ])
      ])))
    }

    wait(for: [partialExpectation], timeout: defaultTimeout)

    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "incremental": [
            {
              "label": "deferredGenus",
              "data": {
                "genus": "Canis"
              },
              "path": [
                "animal"
              ]
            },
            {
              "label": "deferredFriend",
              "data": {
                "friend": {
                  "name": "Buster"
                }
              },
              "path": [
                "animal"
              ]
            }
          ]
        }
        """.data(using: .utf8)!
      )
    ) { result in
      defer {
        incrementalExpectation.fulfill()
      }

      expect(result).to(beSuccess())

      let cacheRecords = try? result.get()?.cacheRecords
      expect(cacheRecords).to(equal(RecordSet(records: [
        Record(key: "QUERY_ROOT", [
          "animal": CacheReference("QUERY_ROOT.animal")
        ]),
        Record(key: "QUERY_ROOT.animal", [
          "__typename": "Animal",
          "genus": "Canis",
          "species": "Canis Familiaris",
          "friend": CacheReference("QUERY_ROOT.animal.friend")
        ]),
        Record(key: "QUERY_ROOT.animal.friend", [
          "name": "Buster"
        ])
      ])))
    }

    wait(for: [incrementalExpectation], timeout: defaultTimeout)
  }

  func test__cacheRecords__givenMultipleIncrementalResponses_shouldComputeCacheRecordsMatchingResponses() throws {
    // given
    let subject = InterceptorTester(interceptor: IncrementalJSONResponseParsingInterceptor())

    let partialExpectation = expectation(description: "Received partial response callback")
    let incrementalExpectation = expectation(description: "Received incremental response callback")
    incrementalExpectation.expectedFulfillmentCount = 2

    // when
    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "data": {
            "animal": {
              "__typename": "Animal",
              "species": "Canis Familiaris"
            }
          }
        }
        """.data(using: .utf8)!)
    ) { result in
      defer {
        partialExpectation.fulfill()
      }

      // then
      expect(result).to(beSuccess())

      let cacheRecords = try? result.get()?.cacheRecords
      expect(cacheRecords).to(equal(RecordSet(records: [
        Record(key: "QUERY_ROOT", [
          "animal": CacheReference("QUERY_ROOT.animal")
        ]),
        Record(key: "QUERY_ROOT.animal", [
          "__typename": "Animal",
          "species": "Canis Familiaris"
        ])
      ])))
    }

    wait(for: [partialExpectation], timeout: defaultTimeout)

    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "incremental": [
            {
              "label": "deferredGenus",
              "data": {
                "genus": "Canis"
              },
              "path": [
                "animal"
              ]
            }
          ]
        }
        """.data(using: .utf8)!
      )
    ) { result in
      defer {
        incrementalExpectation.fulfill()
      }

      expect(result).to(beSuccess())

      let cacheRecords = try? result.get()?.cacheRecords
      expect(cacheRecords).to(equal(RecordSet(records: [
        Record(key: "QUERY_ROOT", [
          "animal": CacheReference("QUERY_ROOT.animal")
        ]),
        Record(key: "QUERY_ROOT.animal", [
          "__typename": "Animal",
          "genus": "Canis",
          "species": "Canis Familiaris"
        ])
      ])))
    }

    subject.intercept(
      request: .mock(operation: AnimalQuery()),
      response: .mock(data: """
        {
          "incremental": [
            {
              "label": "deferredFriend",
              "data": {
                "friend": {
                  "name": "Buster"
                }
              },
              "path": [
                "animal"
              ]
            }
          ]
        }
        """.data(using: .utf8)!
      )
    ) { result in
      defer {
        incrementalExpectation.fulfill()
      }

      expect(result).to(beSuccess())

      let cacheRecords = try? result.get()?.cacheRecords
      expect(cacheRecords).to(equal(RecordSet(records: [
        Record(key: "QUERY_ROOT", [
          "animal": CacheReference("QUERY_ROOT.animal")
        ]),
        Record(key: "QUERY_ROOT.animal", [
          "__typename": "Animal",
          "genus": "Canis",
          "species": "Canis Familiaris",
          "friend": CacheReference("QUERY_ROOT.animal.friend")
        ]),
        Record(key: "QUERY_ROOT.animal.friend", [
          "name": "Buster"
        ])
      ])))
    }

    wait(for: [incrementalExpectation], timeout: defaultTimeout)
  }
}
