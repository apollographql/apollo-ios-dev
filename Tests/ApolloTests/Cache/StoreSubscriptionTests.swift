import XCTest
@testable import Apollo

class StoreSubscriptionTests: XCTestCase {
  static let defaultWaitTimeout: TimeInterval = 1

  var store: ApolloStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    store = ApolloStore()
  }

  override func tearDownWithError() throws {
    store = nil
    try super.tearDownWithError()
  }

  // MARK: - Tests

  func testSubscriberIsNotifiedOfStoreUpdate() throws {
    let cacheKeyChangeExpectation = XCTestExpectation(description: "Subscriber is notified of cache key change")
    let expectedChangeKeySet: Set<String> = ["QUERY_ROOT.__typename", "QUERY_ROOT.name"]
    let subscriber = SimpleSubscriber(cacheKeyChangeExpectation, expectedChangeKeySet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.publish(
      records: [
        "QUERY_ROOT": [
          "__typename": "Hero",
          "name": "Han Solo"
        ]
      ]
    )

    wait(for: [cacheKeyChangeExpectation], timeout: Self.defaultWaitTimeout)
  }

  func testUnsubscribedSubscriberDoesNotReceiveStoreUpdate() throws {
    let cacheKeyChangeExpectation = XCTestExpectation(description: "Subscriber is notified of cache key change")
    cacheKeyChangeExpectation.isInverted = true

    let expectedChangeKeySet: Set<String> = ["QUERY_ROOT.__typename", "QUERY_ROOT.name"]
    let subscriber = SimpleSubscriber(cacheKeyChangeExpectation, expectedChangeKeySet)

    store.subscribe(subscriber)

    store.unsubscribe(subscriber)

    store.publish(
      records: [
        "QUERY_ROOT": [
          "__typename": "Hero",
          "name": "Han Solo"
        ]
      ]
    )

    wait(for: [cacheKeyChangeExpectation], timeout: Self.defaultWaitTimeout)
  }

  /// Fufills the provided expectation when all expected keys have been observed.
  internal class SimpleSubscriber: ApolloStoreSubscriber {
    private let expectation: XCTestExpectation
    private var changeSet: Set<String>

    init(_ expectation: XCTestExpectation, _ changeSet: Set<String>) {
      self.expectation = expectation
      self.changeSet = changeSet
    }

    func store(_ store: ApolloStore,
               didChangeKeys changedKeys: Set<CacheKey>,
               contextIdentifier: UUID?) {
      changeSet.subtract(changedKeys)
      if (changeSet.isEmpty) {
        expectation.fulfill()
      }
    }
  }
}
