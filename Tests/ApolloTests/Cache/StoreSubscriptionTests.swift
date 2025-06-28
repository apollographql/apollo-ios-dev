import Nimble
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

  func testSubscriberIsNotifiedOfStoreUpdate() async throws {
    let expectedChangeKeySet: Set<String> = ["QUERY_ROOT.__typename", "QUERY_ROOT.name"]
    let subscriber = SimpleSubscriber(expectedChangeKeySet)

    let subscriptionToken = store.subscribe(subscriber)
    addTeardownBlock { [store] in store!.unsubscribe(subscriptionToken) }

    try await store.publish(
      records: [
        "QUERY_ROOT": [
          "__typename": "Hero",
          "name": "Han Solo"
        ]
      ]
    )

    await expect { await subscriber.changeSet }.toEventually(beEmpty())
  }

  func testUnsubscribeRemovesSubscriberFromApolloStore() throws {
    let subscriber = SimpleSubscriber([])

    for _ in 0..<10 {
      let subscriptionToken = store.subscribe(subscriber)

      store.unsubscribe(subscriptionToken)
    }

    expect(self.store.subscribers).toEventually(beEmpty())
  }

  /// Fufills the provided expectation when all expected keys have been observed.
  internal actor SimpleSubscriber: ApolloStoreSubscriber {
    var changeSet: Set<String>

    init(_ changeSet: Set<String>) {
      self.changeSet = changeSet
    }

    func isolatedDo(_ block: @escaping (isolated SimpleSubscriber) -> Void) {
      block(self)
    }

    nonisolated func store(_ store: ApolloStore, didChangeKeys changedKeys: Set<CacheKey>) {
      Task {
        await self.isolatedDo {
          $0.changeSet.subtract(changedKeys)
        }
      }
    }
  }
}
