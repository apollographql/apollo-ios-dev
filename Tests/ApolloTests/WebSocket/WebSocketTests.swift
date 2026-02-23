import XCTest
import Nimble
@testable import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
@testable import ApolloWebSocket

#warning("Rewrite when websocket is implemented")

class WebSocketTests: XCTestCase, MockResponseProvider {
  var networkTransport: WebSocketTransport!
  var client: ApolloClient!
  var session: MockURLSession!

  static let endpointURL = TestURL.mockWebSocket.url

//  struct CustomOperationMessageIdCreator: OperationMessageIdCreator {
//    func requestId() -> String {
//      return "12345678"
//    }
//  }
//
  class ReviewAddedData: MockSelectionSet, @unchecked Sendable {
    override class var __selections: [Selection] { [
      .field("reviewAdded", ReviewAdded.self),
    ]}

    class ReviewAdded: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("__typename", String.self),
        .field("stars", Int.self),
        .field("commentary", String?.self),
      ] }
    }
  }

  override func setUpWithError() throws {
    try super.setUpWithError()

    session = MockURLSession(responseProvider: Self.self)
    let store = ApolloStore.mock()
    try networkTransport = WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )

    client = ApolloClient(networkTransport: networkTransport!, store: store)
  }

  override func tearDown() async throws {
    await WebSocketTests.cleanUpRequestHandlers()

    session = nil
    networkTransport = nil
    client = nil

    try await super.tearDown()
  }

  // MARK: - Single Subscription (notStarted → connected)

  func testLocalSingleSubscription() async throws {
    let mockTask = session.mockWebSocketTask

    // Buffer messages before subscribing — they'll be consumed when the receive loop starts.
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","episode":"JEDI","stars":5,"commentary":"A great movie"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))
    mockTask.finish()

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.stars).to(equal(5))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("A great movie"))
  }

  // MARK: - Concurrent Subscriptions (connecting state)

  func testConcurrentSubscriptions__whileConnecting__bothReceiveData() async throws {
    let mockTask = session.mockWebSocketTask

    // Start two subscriptions concurrently BEFORE emitting connection_ack.
    // Both should wait for the connection to be established.
    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Now emit connection_ack — both waiters should be resumed.
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    // Emit data for both subscriptions (IDs 1 and 2).
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"First"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Second"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"2"}"#))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    // Both subscriptions should receive exactly one result each.
    expect(results1.count).to(equal(1))
    expect(results2.count).to(equal(1))

    // The order in which the inner Tasks call registerSubscriber() on the actor
    // is non-deterministic, so sub1 may get ID 1 or ID 2. Assert that both
    // commentaries are present without assuming which subscription received which.
    let commentaries = Set<String?>([
      results1[0].data?.reviewAdded?.commentary,
      results2[0].data?.reviewAdded?.commentary,
    ])
    expect(commentaries).to(equal(Set(["First", "Second"])))
  }

  // MARK: - Second Subscription (connected state)

  func testSecondSubscription__whenAlreadyConnected__shouldNotReconnect() async throws {
    let mockTask = session.mockWebSocketTask

    // Start the first subscription and get through the connection handshake.
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    await expect { await self.networkTransport.connectionState }.toEventually(equal(.connected))

    // Now start a second subscription — the connection is already established,
    // so ensureConnected() should return immediately without reconnecting.
    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Emit data for both and complete.
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"First"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Second"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"2"}"#))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.stars).to(equal(5))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.stars).to(equal(3))

    // Only one connection_init should have been sent (no reconnect).
    expect(mockTask.clientSentMessages(ofType: "connection_init").count).to(equal(1))
  }

  // MARK: - Reconnection (disconnected state)

  func testSubscription__afterDisconnect__shouldReconnectWithNewTask() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // First subscription on task1 — buffer all messages including the stream close
    // so the receive loop processes the disconnection as part of the same iteration batch.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"First connection"}}}}"#
    ))
    task1.emit(.string(#"{"type":"complete","id":"1"}"#))
    task1.finish()

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results1 = try await sub1.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("First connection"))

    // Second subscription should trigger reconnection on task2.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    task2.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Second connection"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"2"}"#))

    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results2 = try await sub2.getAllValues()

    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Second connection"))

    // Both tasks should have been resumed (started).
    expect(task1.isResumed).to(beTrue())
    expect(task2.isResumed).to(beTrue())
  }

  // MARK: - Connection Failure

  func testSubscription__whenConnectionFailsBeforeAck__shouldThrowError() async throws {
    let mockTask = session.mockWebSocketTask

    // Simulate an error before connection_ack.
    struct MockConnectionError: Error, Equatable {}
    mockTask.throw(MockConnectionError())

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(MockConnectionError.self))
    }
  }

  func testSubscription__whenStreamEndsBeforeAck__shouldThrowConnectionClosed() async throws {
    let mockTask = session.mockWebSocketTask

    // Finish the stream without ever sending connection_ack.
    mockTask.finish()

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(matchError(WebSocketTransport.Error.connectionClosed))
    }
  }

  // MARK: - Missing Query Document

  func testSubscription__whenDefinitionIsNil__shouldThrowMissingQueryDocument() async throws {
    /// A mock subscription whose `operationDocument` has no `definition`,
    /// simulating a persisted-queries-only configuration.
    class MockSubscriptionWithoutDefinition<SelectionSet: RootSelectionSet>:
      MockSubscription<SelectionSet>, @unchecked Sendable
    {
      override class var operationDocument: OperationDocument {
        .init(operationIdentifier: "abc123", definition: nil)
      }
    }

    let mockTask = session.mockWebSocketTask
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(
      subscription: MockSubscriptionWithoutDefinition<ReviewAddedData>()
    )

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(matchError(WebSocketTransport.Error.missingQueryDocument))
    }
  }

  // MARK: - Client-Side Cancellation

  func testSubscription__whenCancelledBeforeConnectionAck__shouldNotSendSubscribe() async throws {
    let mockTask = session.mockWebSocketTask

    // Do NOT emit connection_ack — the inner task will be stuck at ensureConnected().
    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    await expect { await self.networkTransport.subscribers.count }.toEventually(equal(1))

    // Consume in a cancellable task.
    let task = Task {
      for try await _ in subscription {}
    }

    // Cancel before connection_ack arrives.
    task.cancel()
    await expect { await self.networkTransport.subscribers.count }.toEventually(equal(0))

    // Since the subscription was cancelled before connection_ack, no subscribe
    // should have been sent yet.
    expect(mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(0))

    // Now emit connection_ack — this unblocks the inner task which was waiting at
    // ensureConnected(). Because the task was already cancelled, checkCancellation()
    // should throw before sendSubscribeMessage is reached.
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    // No subscribe message should have been sent — the inner task detected cancellation
    // after ensureConnected() returned and bailed out before sending subscribe.
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(0))
  }

  func testSubscription__whenTaskCancelled__shouldSendCompleteToServer() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    // Start a subscription in a cancellable task.
    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Wait for the subscribe message to arrive (multiple actor hops).
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Now consume the subscription in a task we can cancel.
    let task = Task {
      for try await _ in subscription {}
    }

    // Cancel the consuming task — this should trigger onTermination → complete message.
    task.cancel()

    // Verify a complete message was sent for operation ID 1.
    // Cancellation propagates through an actor hop, so use toEventually.
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal("1"))
  }

  func testSubscription__whenServerCompletes__shouldNotSendCompleteBack() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Great"}}}}"#
    ))
    // Server sends complete — the client should NOT echo a complete back.
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))

    // Wait a bit then verify no complete messages were sent by the client.
    // Use toEventually to give any potential onTermination handler time to fire,
    // while asserting that the count stays at 0.
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(0))
  }

  // MARK: - Server Error Messages

  func testSubscription__whenServerSendsError__shouldThrowGraphQLErrors() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"error","id":"1","payload":[{"message":"Something went wrong"}]}"#
    ))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      guard case WebSocketTransport.Error.graphQLErrors(let errors) = error else {
        fail("Expected graphQLErrors but got \(error)")
        return
      }
      expect(errors.count).to(equal(1))
      expect(errors[0].message).to(equal("Something went wrong"))
    }
  }

  func testSubscription__whenServerSendsError__shouldNotSendCompleteBack() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Wait for subscribe message to arrive.
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Server sends error — the subscription is terminated server-side, so client should not
    // send a complete message back.
    mockTask.emit(.string(
      #"{"type":"error","id":"1","payload":[{"message":"Unauthorized"}]}"#
    ))

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(WebSocketTransport.Error.self))
    }

    // Verify no complete messages were sent by the client.
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(0))
  }

  func testSubscription__whenServerSendsError__shouldOnlyAffectTargetedSubscription() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    // Start sub1 first and wait for its subscribe message to ensure it gets ID 1.
    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Server sends error only for sub1 (ID 1).
    mockTask.emit(.string(
      #"{"type":"error","id":"1","payload":[{"message":"Failed"}]}"#
    ))

    // Sub2 (ID 2) should still receive data normally.
    mockTask.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":4,"commentary":"Still works"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"2"}"#))

    // Sub1 should throw the error.
    do {
      _ = try await sub1.getAllValues()
      fail("Expected an error to be thrown for sub1")
    } catch {
      guard case WebSocketTransport.Error.graphQLErrors(let errors) = error else {
        fail("Expected graphQLErrors but got \(error)")
        return
      }
      expect(errors[0].message).to(equal("Failed"))
    }

    // Sub2 should complete successfully.
    let results2 = try await sub2.getAllValues()
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Still works"))
  }

  func testSubscription__whenServerSendsErrorAfterNext__shouldDeliverDataThenError() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"First result"}}}}"#
    ))
    mockTask.emit(.string(
      #"{"type":"error","id":"1","payload":[{"message":"Stream failed"}]}"#
    ))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    var results: [GraphQLResponse<MockSubscription<ReviewAddedData>>] = []
    do {
      for try await result in subscription {
        results.append(result)
      }
      fail("Expected an error to be thrown")
    } catch {
      guard case WebSocketTransport.Error.graphQLErrors(let errors) = error else {
        fail("Expected graphQLErrors but got \(error)")
        return
      }
      expect(errors[0].message).to(equal("Stream failed"))
    }

    // The next payload should have been delivered before the error.
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("First result"))
  }

  func testSubscription__whenCancelledWithMultipleSubscribers__shouldOnlyCancelOne() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    // Start two subscriptions.
    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Wait for both subscribe messages to arrive.
    await expect(mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Consume sub1 in a cancellable task.
    let task1 = Task {
      for try await _ in sub1 {}
    }

    // Cancel only sub1.
    task1.cancel()

    // A complete message should have been sent for sub1 (id "1").
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal("1"))

    // Sub2 should still work — send it data and complete from server.
    mockTask.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Still alive"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"2"}"#))

    let results2 = try await sub2.getAllValues()
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Still alive"))
  }

  // MARK: - Auto-Reconnection

  func testSubscription__whenConnectionDropsWithReconnect__shouldContinueReceivingData() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Establish connection and subscribe.
    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Wait for the subscribe message on task1.
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver one result on task1.
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Before disconnect"}}}}"#
    ))

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // Task2 should be connected and re-subscribed.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Wait for the re-subscribe message on task2.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    expect(task2.clientSentMessages(ofType: "subscribe").first?["id"] as? String).to(equal("1"))

    // Deliver a result on the new connection and complete.
    task2.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"After reconnect"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"1"}"#))

    let results = try await subscription.getAllValues()

    // Should have received data from both connections seamlessly.
    guard results.count == 2 else {
      fail("Expected 2 results but got \(results.count)")
      return
    }
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Before disconnect"))
    expect(results[1].data?.reviewAdded?.commentary).to(equal("After reconnect"))

    // Both tasks should have been started.
    expect(task1.isResumed).to(beTrue())
    expect(task2.isResumed).to(beTrue())
  }

  func testSubscription__whenConnectionDropsWithReconnect__shouldResubscribeAllActive() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    // Start sub1 and wait for its subscribe, then sub2.
    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // Task2: connection_ack triggers re-subscribe of both active subscriptions.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Wait for both re-subscribe messages on task2.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Verify both IDs were re-subscribed.
    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set(["1", "2"])))

    // Deliver data and complete for both on the new connection.
    task2.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Sub1 reconnected"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"1"}"#))
    task2.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Sub2 reconnected"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"2"}"#))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Sub1 reconnected"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Sub2 reconnected"))
  }

  func testSubscription__whenReconnectionFails__shouldTerminateSubscribers() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Disconnect task1 — triggers reconnection attempt on task2.
    task1.finish()

    // Task2 fails immediately before connection_ack — reconnection fails.
    struct MockReconnectError: Swift.Error {}
    task2.throw(MockReconnectError())

    // The subscription should terminate with an error.
    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      // The error should propagate from the failed reconnection attempt.
      expect(error).to(beAKindOf(MockReconnectError.self))
    }
  }

  func testSubscription__whenConnectionDropsWithNoSubscribers__shouldNotReconnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Connect, subscribe, get data, and complete — leaving no active subscribers.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Done"}}}}"#
    ))
    task1.emit(.string(#"{"type":"complete","id":"1"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))

    // Now disconnect — no subscribers remain, so no reconnection should happen.
    task1.finish()

    // Wait a bit for any potential reconnection attempt.
    await expect { await transport.connectionState }.toEventually(equal(.disconnected))

    // Task2 should NOT have been resumed (no reconnection attempt).
    expect(task2.isResumed).to(beFalse())
  }

  func testSubscription__whenCancelledDuringReconnect__shouldNotResubscribe() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0.1)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Consume in a cancellable task.
    let consumeTask = Task {
      for try await _ in subscription {}
    }

    // Disconnect task1 — transport starts reconnection with 0.1s delay.
    task1.finish()

    // Cancel the subscription during the reconnection delay.
    consumeTask.cancel()

    // Wait for subscriber to be removed from the transport.
    await expect { await transport.subscribers.count }.toEventually(equal(0))

    // Now let task2 connect — even if reconnection proceeds, no subscribers remain to re-subscribe.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Give time for any potential re-subscribe to happen.
    try await Task.sleep(nanoseconds: 200_000_000)

    // No subscribe messages should have been sent on task2.
    expect(task2.clientSentMessages(ofType: "subscribe").count).to(equal(0))
  }

  // MARK: - Transport Errors

  func testSubscription__whenTransportErrorWithReconnect__shouldContinueReceivingData() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver one result on task1.
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Before error"}}}}"#
    ))

    // Simulate a transport error (e.g. network failure) — not a graceful close.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // Task2 reconnects and re-subscribes.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    task2.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"After error"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"1"}"#))

    let results = try await subscription.getAllValues()

    guard results.count == 2 else {
      fail("Expected 2 results but got \(results.count)")
      return
    }
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Before error"))
    expect(results[1].data?.reviewAdded?.commentary).to(equal("After error"))
  }

  func testSubscription__whenTransportErrorWithReconnectDisabled__shouldTerminateWithError() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver one result then hit a transport error.
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Only result"}}}}"#
    ))

    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // The subscription should deliver the first result then throw the transport error.
    var results: [GraphQLResponse<MockSubscription<ReviewAddedData>>] = []
    do {
      for try await result in subscription {
        results.append(result)
      }
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(MockTransportError.self))
    }

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Only result"))

    // No reconnection should have been attempted.
    expect(task2.isResumed).to(beFalse())
  }

  func testSubscription__whenTransportErrorWithMultipleSubscribers__shouldReconnectAll() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Transport error kills the connection.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // Task2 reconnects — both subscriptions should be re-subscribed.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set(["1", "2"])))

    // Deliver data and complete for both.
    task2.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Sub1 recovered"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"1"}"#))
    task2.emit(.string(
      #"{"type":"next","id":"2","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Sub2 recovered"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"2"}"#))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Sub1 recovered"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Sub2 recovered"))
  }

  // MARK: - Graceful Disconnection (reconnect disabled)

  func testSubscription__whenReconnectDisabled__shouldTerminateOnDisconnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    // Default configuration has reconnectionInterval = -1 (disabled).
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver one result.
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Only result"}}}}"#
    ))

    // Disconnect — with reconnection disabled, stream should terminate.
    task1.finish()

    let results = try await subscription.getAllValues()

    // Should have received the one result before the stream ended.
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Only result"))

    // Task2 should NOT have been used (no reconnection).
    expect(task2.isResumed).to(beFalse())
  }

//
//  func testLocalErrorMissingId() throws {
//    let expectation = self.expectation(description: "Missing id for subscription")
//
//    let subject = client.subscribe(subscription: MockSubscription<ReviewAddedData>()) { result in
//      defer { expectation.fulfill() }
//
//      switch result {
//      case .success:
//        XCTFail("This should have caused an error!")
//      case .failure(let error):
//        if let webSocketError = error as? WebSocketError {
//          switch webSocketError.kind {
//          case .unprocessedMessage:
//            // Correct!
//            break
//          default:
//            XCTFail("Unexpected websocket error: \(error)")
//          }
//        } else {
//          XCTFail("Unexpected error: \(error)")
//        }
//      }
//    }
//
//    // Message data below has missing 'id' and should notify all subscribers of the error
//    let message : JSONEncodableDictionary = [
//      "type": "data",
//      "payload": [
//        "data": [
//          "reviewAdded": [
//            "__typename": "ReviewAdded",
//            "episode": "JEDI",
//            "stars": 5,
//            "commentary": "A great movie"
//          ]
//        ]
//      ]
//    ]
//
//    networkTransport.write(message: message)
//
//    waitForExpectations(timeout: 2, handler: nil)
//
//    subject.cancel()
//  }
//
//  func testSingleSubscriptionWithCustomOperationMessageIdCreator() throws {
//    let expectation = self.expectation(description: "Single Subscription with Custom Operation Message Id Creator")
//
//    let store = ApolloStore.mock()
//    let websocket = MockWebSocket(
//      request:URLRequest(url: TestURL.mockServer.url),
//      protocol: .graphql_ws
//    )
//    networkTransport = WebSocketTransport(
//      websocket: websocket,
//      store: store,
//      config: .init(
//        operationMessageIdCreator: CustomOperationMessageIdCreator()
//      ))
//    client = ApolloClient(networkTransport: networkTransport!, store: store)
//
//    let subject = client.subscribe(subscription: MockSubscription<ReviewAddedData>()) { result in
//      defer { expectation.fulfill() }
//      switch result {
//      case .success(let graphQLResult):
//        XCTAssertEqual(graphQLResult.data?.reviewAdded?.stars, 5)
//      case .failure(let error):
//        XCTFail("Unexpected error: \(error)")
//      }
//    }
//
//    let message : JSONEncodableDictionary = [
//      "type": "data",
//      "id": "12345678", // subscribing on id = 12345678 from custom operation id
//      "payload": [
//        "data": [
//          "reviewAdded": [
//            "__typename": "ReviewAdded",
//            "episode": "JEDI",
//            "stars": 5,
//            "commentary": "A great movie"
//          ]
//        ]
//      ]
//    ]
//
//    networkTransport.write(message: message)
//
//    waitForExpectations(timeout: 2, handler: nil)
//
//    subject.cancel()
//  }
}
