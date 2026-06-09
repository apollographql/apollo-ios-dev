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
    let expectedChangeKeySet: Set<CacheDependentKey> = [
      CacheDependentKey(cacheKey: "QUERY_ROOT", fieldName: "__typename"),
      CacheDependentKey(cacheKey: "QUERY_ROOT", fieldName: "name"),
    ]
    let subscriber = SimpleSubscriber(expectedChangeKeySet)

    let subscriptionToken = await store.subscribe(subscriber)
    addTeardownBlock { [store] in store!.unsubscribe(subscriptionToken) }

    try await store.publish(
      records: [
        "QUERY_ROOT": [
          "__typename": "Hero",
          "name": "Han Solo"
        ]
      ]
    )

    await expect { await subscriber.changeSet }.toEventually(beEmpty(), timeout: .seconds(2))
  }

  func testUnsubscribeRemovesSubscriberFromApolloStore() async throws {
    let subscriber = SimpleSubscriber([])

    for _ in 0..<10 {
      let subscriptionToken = await store.subscribe(subscriber)

      store.unsubscribe(subscriptionToken)
    }

    await expect(self.store.subscribers).toEventually(beEmpty())
  }

  internal actor SimpleSubscriber: ApolloStoreSubscriber {
    var changeSet: Set<CacheDependentKey>

    init(_ changeSet: Set<CacheDependentKey>) {
      self.changeSet = changeSet
    }

    func isolatedDo(_ block: @Sendable @escaping (isolated SimpleSubscriber) -> Void) {
      block(self)
    }

    nonisolated func store(_ store: ApolloStore, didChangeKeys changedKeys: Set<CacheDependentKey>) {
      Task(priority: .high) {
        await self.isolatedDo {
          $0.changeSet.subtract(changedKeys)
        }
      }
    }
  }
}
