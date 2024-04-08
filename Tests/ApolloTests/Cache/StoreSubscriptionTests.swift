import Nimble
import XCTest
@testable import Apollo

open class StoreSubscriptionTests: XCTestCase {
  static let defaultWaitTimeout: TimeInterval = 1

  var store: ApolloStore!

  open override func setUpWithError() throws {
    try super.setUpWithError()
    store = ApolloStore()
  }

  open override func tearDownWithError() throws {
    store = nil
    try super.tearDownWithError()
  }

  // MARK: - Tests

  func testUnsubscribeRemovesSubscriberFromApolloStore() throws {
    let subscriber = NoopSubscriber()

    store.subscribe(subscriber)

    store.unsubscribe(subscriber)

    expect(self.store.subscribers).toEventually(beEmpty())
  }

  /// Fufills the provided expectation when all expected keys have been observed.
  internal class NoopSubscriber: ApolloStoreSubscriber {

    init() {}

    func store(_ store: ApolloStore,
               didChangeKeys changedKeys: Set<CacheKey>,
               contextIdentifier: UUID?) {
      // not implemented, deprecated
    }

    func store(_ store: Apollo.ApolloStore,
               activity: Apollo.ApolloStore.Activity,
               contextIdentifier: UUID?) throws {
      // not implemented
    }
  }
}

final class StoreSubscriptionSimpleTests: StoreSubscriptionTests {

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
      // not implemented, deprecated
    }

    func store(_ store: Apollo.ApolloStore,
               activity: Apollo.ApolloStore.Activity,
               contextIdentifier: UUID?) throws {
      // To match the old didChangeKeys ApolloStoreSubscriber behavior, only operation on the "did merge" action.
      guard case .did(perform: .merge, outcome: .changedKeys(let changedKeys)) = activity else {
        return
      }
      changeSet.subtract(changedKeys)
      if (changeSet.isEmpty) {
        expectation.fulfill()
      }
    }
  }
}

final class StoreSubscriptionAdvancedTests: StoreSubscriptionTests {

  // MARK: - Tests

  func testSubscriberIsNotifiedOfStoreUpdate() throws {
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .merge(records: records)),
        .did(perform: .merge(records: records), outcome: .changedKeys(["QUERY_ROOT.__typename", "QUERY_ROOT.name"]))
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.publish(records: records)

    wait(for: [cacheSubscriberExpectation], timeout: Self.defaultWaitTimeout)
  }

  /// Fufills the provided expectation when all expected keys have been observed.
  internal class AdvancedSubscriber: ApolloStoreSubscriber {
    private let expectation: XCTestExpectation
    private var activities: Set<ApolloStore.Activity>

    init(_ expectation: XCTestExpectation, _ activities: Set<ApolloStore.Activity>) {
      self.expectation = expectation
      self.activities = activities
    }

    func store(_ store: ApolloStore,
               didChangeKeys changedKeys: Set<CacheKey>,
               contextIdentifier: UUID?) {
      // not implemented, deprecated
    }

    func store(_ store: Apollo.ApolloStore,
               activity: Apollo.ApolloStore.Activity,
               contextIdentifier: UUID?) throws {
      activities.remove(activity)
      if (activities.isEmpty) {
        expectation.fulfill()
      }
    }
  }
}
