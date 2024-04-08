import Nimble
import XCTest
@testable import Apollo
//@testable import ApolloSQLite

open class StoreSubscriptionTests: XCTestCase {
  static let defaultWaitTimeout: TimeInterval = 1

  var cache: NormalizedCache!
  var store: ApolloStore!

  open override func setUpWithError() throws {
    try super.setUpWithError()
    cache = InMemoryNormalizedCache()
    //cache = try! SQLiteNormalizedCache(fileURL: URL(fileURLWithPath: "/tmp/test.sqlite"))
    store = ApolloStore(cache: cache)
  }

  open override func tearDownWithError() throws {
    cache = nil
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

  func testSubscriberIsNotifiedOfStoreRead() throws {
    let keys = Set(["QUERY_ROOT"])
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let _ = try cache.merge(records: records)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"], records.storage["QUERY_ROOT"]!)

    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .loadRecords(forKeys: keys)),
        .did(perform: .loadRecords(forKeys: keys), outcome: .records(records.storage))
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.withinReadTransaction { transaction in
      try transaction.loadObject(forKey: "QUERY_ROOT").get()
    } completion: { result in
        switch result {
        case .success(let record):
            XCTAssertEqual(record, records.storage["QUERY_ROOT"])
        case .failure(let error):
            XCTFail(String(describing: error))
        }
    }

    wait(for: [cacheSubscriberExpectation], timeout: Self.defaultWaitTimeout)
  }

  func testSubscriberIsNotifiedOfStorePublish() throws {
    let keys = Set(["QUERY_ROOT.__typename", "QUERY_ROOT.name"])
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .merge(records: records)),
        .did(perform: .merge(records: records), outcome: .changedKeys(keys)),
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.publish(records: records)

    wait(for: [cacheSubscriberExpectation], timeout: Self.defaultWaitTimeout)
  }

  func testSubscriberIsNotifiedOfStoreRemoveForKey() throws {
    let key = "QUERY_ROOT"
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let _ = try cache.merge(records: records)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"], records.storage["QUERY_ROOT"]!)

    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let transactionSuccessExpectation = XCTestExpectation(description: "transaction completed successfully")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .removeRecord(for: key)),
        .did(perform: .removeRecord(for: key), outcome: .success),
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.withinReadWriteTransaction { transaction in
      try transaction.removeObject(for: key)
    } completion: { result in
        switch result {
        case .success:
            transactionSuccessExpectation.fulfill()
        case .failure(let error):
            XCTFail(String(describing: error))
        }
    }

    wait(for: [cacheSubscriberExpectation, transactionSuccessExpectation], timeout: Self.defaultWaitTimeout)

    XCTAssertNil(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"])
  }

  func testSubscriberIsNotifiedOfStoreRemoveMatchingPattern() throws {
    let pattern = "_ROOT"
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ],
      "MUTATION_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let _ = try cache.merge(records: records)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"], records.storage["QUERY_ROOT"]!)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["MUTATION_ROOT"]))["MUTATION_ROOT"], records.storage["MUTATION_ROOT"]!)

    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let transactionSuccessExpectation = XCTestExpectation(description: "transaction completed successfully")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .removeRecords(matching: "NADA")),
        .did(perform: .removeRecords(matching: "NADA"), outcome: .success),
        .will(perform: .removeRecords(matching: pattern)),
        .did(perform: .removeRecords(matching: pattern), outcome: .success),
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.withinReadWriteTransaction { transaction in
      try transaction.removeObjects(matching: "NADA")
    }
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"], records.storage["QUERY_ROOT"]!)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["MUTATION_ROOT"]))["MUTATION_ROOT"], records.storage["MUTATION_ROOT"]!)

    store.withinReadWriteTransaction { transaction in
      try transaction.removeObjects(matching: pattern)
    } completion: { result in
        switch result {
        case .success:
            transactionSuccessExpectation.fulfill()
        case .failure(let error):
            XCTFail(String(describing: error))
        }
    }

    wait(for: [cacheSubscriberExpectation, transactionSuccessExpectation], timeout: Self.defaultWaitTimeout, enforceOrder: true)

    XCTAssertNil(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"])
    XCTAssertNil(try cache.loadRecords(forKeys: Set(["MUTATION_ROOT"]))["MUTATION_ROOT"])
  }

  func testSubscriberIsNotifiedOfStoreClear() throws {
    let records: RecordSet = [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ],
      "MUTATION_ROOT": [
        "__typename": "Hero",
        "name": "Han Solo"
      ]
    ]
    let _ = try cache.merge(records: records)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"], records.storage["QUERY_ROOT"]!)
    XCTAssertEqual(try cache.loadRecords(forKeys: Set(["MUTATION_ROOT"]))["MUTATION_ROOT"], records.storage["MUTATION_ROOT"]!)

    let cacheSubscriberExpectation = XCTestExpectation(description: "Subscriber is notified of all expected activities")
    let cacheClearExpectation = XCTestExpectation(description: "clear cache completed")
    let expectedActivitiesSet: Set<ApolloStore.Activity> = [
        .will(perform: .clear),
        .did(perform: .clear, outcome: .success),
    ]
    let subscriber = AdvancedSubscriber(cacheSubscriberExpectation, expectedActivitiesSet)

    store.subscribe(subscriber)
    addTeardownBlock { self.store.unsubscribe(subscriber) }

    store.clearCache { result in
        switch result {
        case .success:
            cacheClearExpectation.fulfill()
        case .failure(let error):
            XCTFail(String(describing: error))
        }
    }

    wait(for: [cacheSubscriberExpectation, cacheClearExpectation], timeout: Self.defaultWaitTimeout, enforceOrder: true)

    XCTAssertNil(try cache.loadRecords(forKeys: Set(["QUERY_ROOT"]))["QUERY_ROOT"])
    XCTAssertNil(try cache.loadRecords(forKeys: Set(["MUTATION_ROOT"]))["MUTATION_ROOT"])
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
