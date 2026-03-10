import XCTest
import Nimble
@testable @_spi(Execution) import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
@testable @_spi(Execution) import ApolloWebSocket

class WebSocketTests: XCTestCase, MockResponseProvider {
  var networkTransport: WebSocketTransport!
  var client: ApolloClient!
  var session: MockURLSession!
  var factory: MockWebSocketTaskFactory!

  var mockTask: MockWebSocketTask { factory.tasks[0] }

  static let endpointURL = TestURL.mockWebSocket.url

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

    factory = MockWebSocketTaskFactory([MockWebSocketTask()])
    session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)
  }

  override func tearDown() async throws {
    await WebSocketTests.cleanUpRequestHandlers()

    factory = nil
    session = nil
    networkTransport = nil
    client = nil

    try await super.tearDown()
  }

  // MARK: - Test Helpers

  /// Builds a `next` message payload matching the `ReviewAddedData` selection set.
  static func reviewAddedPayload(
    stars: Int,
    commentary: String?,
    episode: String? = nil
  ) -> [String: Any] {
    var reviewAdded: [String: Any] = [
      "__typename": "ReviewAdded",
      "stars": stars,
      "commentary": commentary as Any,
    ]
    if let episode { reviewAdded["episode"] = episode }
    return ["data": ["reviewAdded": reviewAdded]]
  }

  /// Creates a subscription, waits for its subscribe message to arrive on the mock task,
  /// and returns the subscription stream along with the server-assigned operation ID.
  ///
  /// This helper ensures deterministic operation ID assignment when creating multiple
  /// subscriptions by waiting for each subscribe message to be processed before returning.
  /// Without this sequencing, concurrent inner Tasks race to register on the actor, making
  /// ID assignment non-deterministic and causing tests that reference specific IDs to be flaky.
  ///
  /// ```swift
  /// let (sub1, id1) = try await subscribe(on: mockTask, using: client)
  /// let (sub2, id2) = try await subscribe(on: mockTask, using: client)
  /// // sub1 is guaranteed to have id1, sub2 is guaranteed to have id2
  /// ```
  private func subscribe(
    on mockTask: MockWebSocketTask,
    using client: ApolloClient,
    file: FileString = #filePath,
    line: UInt = #line
  ) async throws -> (
    stream: SubscriptionStream<GraphQLResponse<MockSubscription<ReviewAddedData>>>,
    operationID: String
  ) {
    let index = mockTask.clientSentMessages(ofType: "subscribe").count
    let stream = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    await expect(file: file, line: line, mockTask.clientSentMessages(ofType: "subscribe").count)
      .toEventually(equal(index + 1))
    let operationID = mockTask.subscribeOperationID(at: index)
    return (stream, operationID)
  }

  // MARK: - Connecting Payload

  func testConnectionInit__withDefaultConfiguration__shouldSendNoPayload() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // The connection_init message should have been sent with no payload.
    let initMessages = mockTask.clientSentMessages(ofType: "connection_init")
    expect(initMessages.count).to(equal(1))
    expect(initMessages.first?["payload"]).to(beNil())

    _ = subscription
  }

  func testConnectionInit__withConnectingPayload__shouldSendPayloadInConnectionInit() async throws {
    factory.tasks.append(MockWebSocketTask())
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(connectingPayload: [
        "authToken": "my-secret-token",
        "version": 2,
      ])
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    factory.currentTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: factory.currentTask, using: client)

    // Verify the connection_init message includes the connecting payload.
    let initMessages = factory.currentTask.clientSentMessages(ofType: "connection_init")
    expect(initMessages.count).to(equal(1))

    let payload = initMessages.first?["payload"] as? [String: Any]
    expect(payload?["authToken"] as? String).to(equal("my-secret-token"))
    expect(payload?["version"] as? Int).to(equal(2))

    _ = subscription
  }

  func testConnectionInit__withConnectingPayload__shouldResendPayloadOnReconnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        reconnectionInterval: 0,
        connectingPayload: ["authToken": "reconnect-token"]
      )
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Establish initial connection.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Verify first connection_init has the payload.
    let initMessages1 = task1.clientSentMessages(ofType: "connection_init")
    expect(initMessages1.count).to(equal(1))
    let payload1 = initMessages1.first?["payload"] as? [String: Any]
    expect(payload1?["authToken"] as? String).to(equal("reconnect-token"))

    // Disconnect — triggers reconnection.
    task1.finish()

    // The reconnection task reconnects (pre-buffered messages are consumed when the transport picks up task2).
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Verify the reconnection's connection_init also has the payload.
    let initMessages2 = task2.clientSentMessages(ofType: "connection_init")
    expect(initMessages2.count).to(equal(1))
    let payload2 = initMessages2.first?["payload"] as? [String: Any]
    expect(payload2?["authToken"] as? String).to(equal("reconnect-token"))

    _ = subscription
  }

  // MARK: - Single Subscription (notStarted → connected)

  func testLocalSingleSubscription() async throws {

    // Buffer messages before subscribing — they'll be consumed when the receive loop starts.
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "A great movie", episode: "JEDI")))
    mockTask.emit(.complete(id: "1"))
    mockTask.finish()

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.stars).to(equal(5))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("A great movie"))
  }

  // MARK: - Concurrent Subscriptions (connecting state)

  func testConcurrentSubscriptions__whileConnecting__bothReceiveData() async throws {

    // Start two subscriptions concurrently BEFORE emitting connection_ack.
    // Both should wait for the connection to be established.
    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Now emit connection_ack — both waiters should be resumed.
    mockTask.emit(.connectionAck(payload: nil))

    // Emit data for both subscriptions (IDs 1 and 2).
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "First")))
    mockTask.emit(.complete(id: "1"))
    mockTask.emit(.next(id: "2", payload: Self.reviewAddedPayload(stars: 3, commentary: "Second")))
    mockTask.emit(.complete(id: "2"))

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

    // Start the first subscription and get through the connection handshake.
    mockTask.emit(.connectionAck(payload: nil))

    let (sub1, _) = try await subscribe(on: mockTask, using: client)

    // Now start a second subscription — the connection is already established,
    // so ensureConnected() should return immediately without reconnecting.
    let (sub2, _) = try await subscribe(on: mockTask, using: client)

    // Only one connection_init should have been sent (no reconnect).
    expect(self.mockTask.clientSentMessages(ofType: "connection_init").count).to(equal(1))

    _ = (sub1, sub2)
  }

  // MARK: - Reconnection (disconnected state)

  func testSubscription__afterDisconnect__shouldReconnectWithNewTask() async throws {
    let task2 = MockWebSocketTask()
    factory.tasks.append(task2)

    // First subscription on mockTask — buffer all messages including the stream close
    // so the receive loop processes the disconnection as part of the same iteration batch.
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "First connection")))
    mockTask.emit(.complete(id: "1"))
    mockTask.finish()

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results1 = try await sub1.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("First connection"))

    // Second subscription should trigger reconnection on task2.
    task2.emit(.connectionAck(payload: nil))
    task2.emit(.next(id: "2", payload: Self.reviewAddedPayload(stars: 3, commentary: "Second connection")))
    task2.emit(.complete(id: "2"))

    let sub2 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results2 = try await sub2.getAllValues()

    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Second connection"))

    // Both tasks should have been resumed (started).
    expect(self.mockTask.isResumed).to(beTrue())
    expect(task2.isResumed).to(beTrue())
  }

  // MARK: - Connection Failure

  func testSubscription__whenConnectionFailsBeforeAck__shouldThrowError() async throws {

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

  // MARK: - Client-Side Cancellation

  func testSubscription__whenCancelledBeforeConnectionAck__shouldNotSendSubscribe() async throws {

    // Do NOT emit connection_ack — the inner task will be stuck at ensureConnected().
    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    await expect { await self.networkTransport.subscriberCount }.toEventually(equal(1))

    // Consume in a cancellable task.
    let task = Task {
      for try await _ in subscription {}
    }

    // Cancel before connection_ack arrives.
    task.cancel()
    await expect { await self.networkTransport.subscriberCount }.toEventually(equal(0))

    // Since the subscription was cancelled before connection_ack, no subscribe
    // should have been sent yet.
    expect(self.mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(0))

    // Now emit connection_ack — this unblocks the inner task which was waiting at
    // ensureConnected(). Because the task was already cancelled, checkCancellation()
    // should throw before sendSubscribeMessage is reached.
    mockTask.emit(.connectionAck(payload: nil))

    // No subscribe message should have been sent — the inner task detected cancellation
    // after ensureConnected() returned and bailed out before sending subscribe.
    await expect(self.mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(0))
  }

  func testSubscription__whenTaskCancelled__shouldSendCompleteToServer() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    // Start a subscription and get its dynamic ID.
    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    // Now consume the subscription in a task we can cancel.
    let task = Task {
      for try await _ in subscription {}
    }

    // Cancel the consuming task — this should trigger onTermination → complete message.
    task.cancel()

    // Verify a complete message was sent for the operation.
    // Cancellation propagates through an actor hop, so use toEventually.
    await expect(self.mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(self.mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal(operationID))
  }

  func testSubscription__whenServerCompletes__shouldNotSendCompleteBack() async throws {
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "Great")))
    // Server sends complete — the client should NOT echo a complete back.
    mockTask.emit(.complete(id: "1"))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))

    // Wait a bit then verify no complete messages were sent by the client.
    // Use toEventually to give any potential onTermination handler time to fire,
    // while asserting that the count stays at 0.
    await expect(self.mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(0))
  }

  // MARK: - Server Error Messages

  func testSubscription__whenServerSendsError__shouldThrowGraphQLErrors() async throws {
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.error(id: "1", payload: [["message": "Something went wrong"]]))

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
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    // Server sends error — the subscription is terminated server-side, so client should not
    // send a complete message back.
    mockTask.emit(.error(id: operationID, payload: [["message": "Unauthorized"]]))

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(WebSocketTransport.Error.self))
    }

    // Verify no complete messages were sent by the client.
    await expect(self.mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(0))
  }

  func testSubscription__whenServerSendsError__shouldOnlyAffectTargetedSubscription() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (sub1, id1) = try await subscribe(on: mockTask, using: client)
    let (sub2, id2) = try await subscribe(on: mockTask, using: client)

    // Server sends error only for sub1.
    mockTask.emit(.error(id: id1, payload: [["message": "Failed"]]))

    // Sub2 should still receive data normally.
    mockTask.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 4, commentary: "Still works")))
    mockTask.emit(.complete(id: id2))

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
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "First result")))
    mockTask.emit(.error(id: "1", payload: [["message": "Stream failed"]]))

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
    mockTask.emit(.connectionAck(payload: nil))

    // Create subscriptions sequentially — the helper waits for each subscribe
    // message to arrive, guaranteeing deterministic ID assignment.
    let (sub1, id1) = try await subscribe(on: mockTask, using: client)
    let (sub2, id2) = try await subscribe(on: mockTask, using: client)

    // Consume sub1 in a cancellable task.
    let task1 = Task {
      for try await _ in sub1 {}
    }

    // Cancel only sub1.
    task1.cancel()

    // A complete message should have been sent for sub1.
    await expect(self.mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(self.mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal(id1))

    // Sub2 should still work — send it data and complete from server.
    mockTask.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 3, commentary: "Still alive")))
    mockTask.emit(.complete(id: id2))

    let results2 = try await sub2.getAllValues()
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Still alive"))
  }

  // MARK: - Auto-Reconnection

  func testSubscription__whenConnectionDropsWithReconnect__shouldContinueReceivingData() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Establish connection and subscribe.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result on task1.
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Before disconnect")))

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // The reconnection task should be connected and re-subscribed.
    task2.emit(.connectionAck(payload: nil))

    // Wait for the re-subscribe message on the reconnection task.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    expect(task2.clientSentMessages(ofType: "subscribe").first?["id"] as? String).to(equal(operationID))

    // Deliver a result on the new connection and complete.
    task2.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 3, commentary: "After reconnect")))
    task2.emit(.complete(id: operationID))

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
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    // Start sub1 and wait for its subscribe, then sub2.
    let (sub1, id1) = try await subscribe(on: task1, using: client)
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // Reconnection task: connection_ack triggers re-subscribe of both active subscriptions.
    task2.emit(.connectionAck(payload: nil))

    // Wait for both re-subscribe messages on the reconnection task.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Verify both IDs were re-subscribed.
    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set([id1, id2])))

    // Deliver data and complete for both on the new connection.
    task2.emit(.next(id: id1, payload: Self.reviewAddedPayload(stars: 5, commentary: "Sub1 reconnected")))
    task2.emit(.complete(id: id1))
    task2.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 3, commentary: "Sub2 reconnected")))
    task2.emit(.complete(id: id2))

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
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Disconnect task1 — triggers reconnection attempt on task2.
    task1.finish()

    // The reconnection task fails immediately before connection_ack — reconnection fails.
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
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect, subscribe, get data, and complete — leaving no active subscribers.
    task1.emit(.connectionAck(payload: nil))
    task1.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "Done")))
    task1.emit(.complete(id: "1"))

    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))

    // Now disconnect — no subscribers remain, so no reconnection should happen.
    task1.finish()

    // Wait a bit for any potential reconnection attempt.
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.disconnected))

    // Task2 should NOT have been resumed (no reconnection attempt).
    expect(task2.isResumed).to(beFalse())
  }

  func testSubscription__whenCancelledDuringReconnect__shouldNotResubscribe() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0.1)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Consume in a cancellable task.
    let consumeTask = Task {
      for try await _ in subscription {}
    }

    // Disconnect task1 — transport starts reconnection with 0.1s delay.
    task1.finish()

    // Cancel the subscription during the reconnection delay.
    consumeTask.cancel()

    // Wait for subscriber to be removed from the transport.
    await expect { await self.networkTransport.subscriberCount }.toEventually(equal(0))

    // Now let the reconnection task connect — even if reconnection proceeds, no subscribers remain to re-subscribe.
    task2.emit(.connectionAck(payload: nil))

    // Give time for any potential re-subscribe to happen.
    try await Task.sleep(nanoseconds: 200_000_000)

    // No subscribe messages should have been sent on the reconnection task.
    expect(task2.clientSentMessages(ofType: "subscribe").count).to(equal(0))
  }

  // MARK: - Transport Errors

  func testSubscription__whenTransportErrorWithReconnect__shouldContinueReceivingData() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result on task1.
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Before error")))

    // Simulate a transport error (e.g. network failure) — not a graceful close.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // The reconnection task reconnects and re-subscribes.
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    task2.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 3, commentary: "After error")))
    task2.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()

    guard results.count == 2 else {
      fail("Expected 2 results but got \(results.count)")
      return
    }
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Before error"))
    expect(results[1].data?.reviewAdded?.commentary).to(equal("After error"))
  }

  func testSubscription__whenTransportErrorWithReconnectDisabled__shouldTerminateWithError() async throws {
    let task2 = MockWebSocketTask()
    factory.tasks.append(task2)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    // Deliver one result then hit a transport error.
    mockTask.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Only result")))

    struct MockTransportError: Swift.Error {}
    mockTask.throw(MockTransportError())

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
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (sub1, id1) = try await subscribe(on: task1, using: client)
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    // Transport error kills the connection.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // The reconnection task reconnects — both subscriptions should be re-subscribed.
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set([id1, id2])))

    // Deliver data and complete for both.
    task2.emit(.next(id: id1, payload: Self.reviewAddedPayload(stars: 5, commentary: "Sub1 recovered")))
    task2.emit(.complete(id: id1))
    task2.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 3, commentary: "Sub2 recovered")))
    task2.emit(.complete(id: id2))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Sub1 recovered"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Sub2 recovered"))
  }

  // MARK: - Ping / Pong

  func testPing__whenServerSendsPing__shouldReplyWithPong() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a ping — transport should reply with a pong.
    mockTask.emit(.ping(payload: nil))

    await expect(self.mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(1))

    // The pong should have no payload.
    let pongMessage = mockTask.clientSentMessages(ofType: "pong").first
    expect(pongMessage?["payload"]).to(beNil())

    _ = subscription
  }

  func testPing__whenServerSendsPingWithPayload__shouldReplyWithPongWithoutPayload() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a ping with payload — transport should reply with a pong (no payload).
    mockTask.emit(.ping(payload: ["hello": "world"]))

    await expect(self.mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(1))

    // The pong should have no payload — we don't echo the ping's payload.
    let pongMessage = mockTask.clientSentMessages(ofType: "pong").first
    expect(pongMessage?["payload"]).to(beNil())

    _ = subscription
  }

  func testPong__whenServerSendsPong__shouldNotReply() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends an unsolicited pong — transport should NOT reply.
    mockTask.emit(.pong(payload: nil))

    // Give time for any potential response to be sent.
    try await Task.sleep(nanoseconds: 100_000_000)

    // No ping or pong messages should have been sent by the client.
    expect(self.mockTask.clientSentMessages(ofType: "ping").count).to(equal(0))
    expect(self.mockTask.clientSentMessages(ofType: "pong").count).to(equal(0))

    _ = subscription
  }

  func testPing__whenServerSendsMultiplePings__shouldReplyToEach() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends multiple pings — transport should reply to each.
    mockTask.emit(.ping(payload: nil))
    mockTask.emit(.ping(payload: ["seq": 2]))
    mockTask.emit(.ping(payload: ["seq": 3]))

    await expect(self.mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(3))

    _ = subscription
  }

  // MARK: - Client-Initiated Ping Keepalive

  func testPingInterval__whenConfigured__shouldSendPeriodicPings() async throws {
    factory = MockWebSocketTaskFactory([MockWebSocketTask()])
    session = MockURLSession(responseProvider: Self.self, taskFactory: factory)

    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(pingInterval: 0.1)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    factory.currentTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: factory.currentTask, using: client)

    // Wait for at least 2 pings to be sent.
    await expect(self.factory.currentTask.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(2), timeout: .seconds(1))

    _ = subscription
  }

  func testPingInterval__whenNotConfigured__shouldNotSendPings() async throws {
    // Default configuration has no pingInterval.
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Wait a bit to ensure no pings are sent.
    try await Task.sleep(nanoseconds: 300_000_000)

    expect(self.mockTask.clientSentMessages(ofType: "ping").count).to(equal(0))

    _ = subscription
  }

  func testPingInterval__shouldStopOnDisconnect() async throws {
    factory = MockWebSocketTaskFactory([MockWebSocketTask()])
    session = MockURLSession(responseProvider: Self.self, taskFactory: factory)

    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(pingInterval: 0.1)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    factory.currentTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: factory.currentTask, using: client)

    // Wait for at least one ping.
    await expect(self.factory.currentTask.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(1), timeout: .seconds(2))

    // Disconnect — pings should stop.
    factory.currentTask.finish()

    // Record the count after disconnect and wait to confirm it doesn't grow.
    try await Task.sleep(nanoseconds: 200_000_000)
    let countAfterDisconnect = factory.currentTask.clientSentMessages(ofType: "ping").count
    try await Task.sleep(nanoseconds: 300_000_000)
    expect(self.factory.currentTask.clientSentMessages(ofType: "ping").count).to(equal(countAfterDisconnect))

    _ = subscription
  }

  func testPingInterval__shouldStopOnPause__andRestartOnResume() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory = MockWebSocketTaskFactory([task1, task2])
    session = MockURLSession(responseProvider: Self.self, taskFactory: factory)

    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(pingInterval: 0.1)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Wait for at least one ping on task1.
    await expect(task1.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(1), timeout: .seconds(2))

    // Pause — pings should stop on task1.
    await networkTransport.pause()

    // Resume — should start a new connection on the next task.
    await networkTransport.resume()
    task2.emit(.connectionAck(payload: nil))

    // Pings should now arrive on the resumed task.
    await expect(task2.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(1), timeout: .seconds(2))

    _ = subscription
  }

  func testPingInterval__shouldRestartOnReconnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory = MockWebSocketTaskFactory([task1, task2])
    session = MockURLSession(responseProvider: Self.self, taskFactory: factory)

    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0, pingInterval: 0.1)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Wait for at least one ping on task1.
    await expect(task1.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(1), timeout: .seconds(2))

    // Disconnect task1 — triggers auto-reconnect.
    task1.finish()
    task2.emit(.connectionAck(payload: nil))

    // Pings should now arrive on the reconnection task.
    await expect(task2.clientSentMessages(ofType: "ping").count)
      .toEventually(beGreaterThanOrEqualTo(1), timeout: .seconds(2))

    _ = subscription
  }

  // MARK: - Unrecognized Messages

  func testSubscription__whenServerSendsUnrecognizedMessage__shouldTerminateWithError() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a message with an unknown type.
    mockTask.emit(.string(#"{"type":"unknown_garbage"}"#))

    do {
      _ = try await subscription.getAllValues()
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(matchError(WebSocketTransport.Error.unrecognizedMessage))
    }
  }

  // MARK: - Graceful Disconnection (reconnect disabled)

  func testSubscription__whenReconnectDisabled__shouldTerminateOnDisconnect() async throws {
    let task2 = MockWebSocketTask()
    factory.tasks.append(task2)

    // Default configuration has reconnectionInterval = -1 (disabled).
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    // Deliver one result.
    mockTask.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Only result")))

    // Disconnect — with reconnection disabled, stream should terminate.
    mockTask.finish()

    let results = try await subscription.getAllValues()

    // Should have received the one result before the stream ended.
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Only result"))

    // Task2 should NOT have been used (no reconnection).
    expect(task2.isResumed).to(beFalse())
  }

  // MARK: - Queries

  func testQuery__shouldReceiveSingleResult() async throws {
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "Query result")))
    mockTask.emit(.complete(id: "1"))

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .networkOnly
    )

    expect(result.data?.reviewAdded?.stars).to(equal(5))
    expect(result.data?.reviewAdded?.commentary).to(equal("Query result"))

    // Should have sent a subscribe message (graphql-ws uses subscribe for all operation types).
    expect(self.mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(1))
  }

  func testQuery__whenServerSendsError__shouldThrow() async throws {
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.error(id: "1", payload: [["message": "Query failed"]]))

    do {
      _ = try await client.fetch(
        query: MockQuery<ReviewAddedData>(),
        cachePolicy: .networkOnly
      )
      fail("Expected an error to be thrown")
    } catch {
      guard case WebSocketTransport.Error.graphQLErrors(let errors) = error else {
        fail("Expected graphQLErrors but got \(error)")
        return
      }
      expect(errors.count).to(equal(1))
      expect(errors[0].message).to(equal("Query failed"))
    }
  }

  func testQuery__whenConnectionDropsWithReconnect__shouldNotRetry() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    // Start a query — it blocks waiting for the response.
    let client = self.client!
    let queryTask = Task {
      try await client.fetch(
        query: MockQuery<ReviewAddedData>(),
        cachePolicy: .networkOnly
      )
    }

    // Wait for the subscribe message to arrive.
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Disconnect — query should be terminated immediately, NOT retried.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    do {
      _ = try await queryTask.value
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(MockTransportError.self))
    }
  }

  // MARK: - Mutations

  func testMutation__shouldReceiveSingleResult() async throws {
    mockTask.emit(.connectionAck(payload: nil))
    mockTask.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 3, commentary: "Mutation result")))
    mockTask.emit(.complete(id: "1"))

    let result = try await client.perform(mutation: MockMutation<ReviewAddedData>())

    expect(result.data?.reviewAdded?.stars).to(equal(3))
    expect(result.data?.reviewAdded?.commentary).to(equal("Mutation result"))

    expect(self.mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(1))
  }

  func testMutation__whenConnectionDropsWithReconnect__shouldNotRetry() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let client = self.client!
    let mutationTask = Task {
      try await client.perform(mutation: MockMutation<ReviewAddedData>())
    }

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Disconnect — mutation should be terminated immediately, NOT retried.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    do {
      _ = try await mutationTask.value
      fail("Expected an error to be thrown")
    } catch {
      expect(error).to(beAKindOf(MockTransportError.self))
    }
  }

  // MARK: - Mixed Operations and Reconnection

  func testQueryAndSubscription__whenConnectionDropsWithReconnect__shouldOnlyResubscribeSubscription() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    // Start a subscription first.
    let (subscription, subscriptionID) = try await subscribe(on: task1, using: client)

    // Start a query — it blocks waiting for the response.
    let client = self.client!
    let queryTask = Task {
      try await client.fetch(
        query: MockQuery<ReviewAddedData>(),
        cachePolicy: .networkOnly
      )
    }
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Disconnect — triggers reconnection for the subscription.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // The query should terminate immediately with the transport error.
    do {
      _ = try await queryTask.value
      fail("Expected an error to be thrown for the query")
    } catch {
      expect(error).to(beAKindOf(MockTransportError.self))
    }

    // The subscription should survive — the reconnection task reconnects.
    task2.emit(.connectionAck(payload: nil))

    // Only the subscription should be re-subscribed on the reconnection task (not the query).
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver data on the new connection and complete.
    task2.emit(.next(id: subscriptionID, payload: Self.reviewAddedPayload(stars: 4, commentary: "After reconnect")))
    task2.emit(.complete(id: subscriptionID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("After reconnect"))
  }

  // MARK: - Custom Operation Message ID Creator

  func testSubscription__withCustomOperationMessageIdCreator__shouldUseCustomIds() async throws {
    struct FixedIdCreator: OperationMessageIdCreator {
      mutating func requestId() -> String {
        return "custom-id-123"
      }
    }

    factory.tasks.append(MockWebSocketTask())
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(operationMessageIdCreator: FixedIdCreator())
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    factory.currentTask.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: factory.currentTask, using: client)

    // The subscribe message should use the custom ID.
    expect(operationID).to(equal("custom-id-123"))

    // Server responds using the custom ID.
    factory.currentTask.emit(.next(id: "custom-id-123", payload: Self.reviewAddedPayload(stars: 5, commentary: "Custom ID works")))
    factory.currentTask.emit(.complete(id: "custom-id-123"))

    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Custom ID works"))
  }

  // MARK: - Delegate

  func testDelegate__whenConnectionEstablished__shouldCallDidConnect() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    expect(delegate.events).to(contain(.didConnect))
    expect(delegate.events).toNot(contain(.didReconnect))

    _ = subscription
  }

  func testDelegate__whenReconnected__shouldCallDidReconnectNotDidConnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Establish initial connection.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Disconnect — triggers reconnection.
    task1.finish()

    // Reconnect.
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Should have: didConnect, didDisconnect, didReconnect (in that order).
    await expect(delegate.events).toEventually(contain(.didReconnect))
    expect(delegate.events.filter { $0 == .didConnect }.count).to(equal(1))
    expect(delegate.events.filter { $0 == .didReconnect }.count).to(equal(1))

    _ = subscription
  }

  func testDelegate__whenDisconnectedWithError__shouldCallDidDisconnectWithError() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Disconnect with an error.
    struct MockDisconnectError: Error {}
    mockTask.throw(MockDisconnectError())

    do {
      _ = try await subscription.getAllValues()
    } catch {}

    await expect(delegate.events).toEventually(contain(.didDisconnect(hasError: true)))
  }

  func testDelegate__whenDisconnectedCleanly__shouldCallDidDisconnectWithNilError() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Clean disconnect (stream ends without error).
    mockTask.finish()

    _ = try? await subscription.getAllValues()

    await expect(delegate.events).toEventually(contain(.didDisconnect(hasError: false)))
  }

  func testDelegate__whenPingReceived__shouldCallDidReceivePing() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a ping without payload.
    mockTask.emit(.ping(payload: nil))

    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: false)))

    // Server sends a ping with payload.
    mockTask.emit(.ping(payload: ["key": "value"]))

    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: true)))

    _ = subscription
  }

  func testDelegate__whenPongReceived__shouldCallDidReceivePong() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a pong without payload.
    mockTask.emit(.pong(payload: nil))

    await expect(delegate.events).toEventually(contain(.didReceivePong(hasPayload: false)))

    // Server sends a pong with payload.
    mockTask.emit(.pong(payload: ["data": "test"]))

    await expect(delegate.events).toEventually(contain(.didReceivePong(hasPayload: true)))

    _ = subscription
  }

  func testDelegate__fullLifecycle__shouldReceiveEventsInOrder() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Receive a ping.
    task1.emit(.ping(payload: nil))
    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: false)))

    // Disconnect.
    task1.finish()

    // Reconnect.
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Complete the subscription to let the test finish.
    task2.emit(.complete(id: operationID))
    _ = try? await subscription.getAllValues()

    // Verify the full sequence of events.
    let events = delegate.events
    expect(events).to(contain(.didConnect))
    expect(events).to(contain(.didReceivePing(hasPayload: false)))
    expect(events).to(contain(.didDisconnect(hasError: false)))
    expect(events).to(contain(.didReconnect))

    // Verify ordering: didConnect before didDisconnect, didDisconnect before didReconnect.
    if let connectIdx = events.firstIndex(of: .didConnect),
       let disconnectIdx = events.firstIndex(of: .didDisconnect(hasError: false)),
       let reconnectIdx = events.firstIndex(of: .didReconnect) {
      expect(connectIdx).to(beLessThan(disconnectIdx))
      expect(disconnectIdx).to(beLessThan(reconnectIdx))
    } else {
      fail("Expected all lifecycle events to be present")
    }
  }

  func testSubscription__withSequencedCreatorStartingAtCustomNumber__shouldUseSequentialIds() async throws {
    factory.tasks.append(MockWebSocketTask())
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        operationMessageIdCreator: ApolloSequencedOperationMessageIdCreator(startAt: 100)
      )
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    factory.currentTask.emit(.connectionAck(payload: nil))

    // Start first subscription — should get ID "100".
    let (sub1, id1) = try await subscribe(on: factory.currentTask, using: client)

    // Start second subscription — should get ID "101".
    let (sub2, id2) = try await subscribe(on: factory.currentTask, using: client)

    expect(id1).to(equal("100"))
    expect(id2).to(equal("101"))

    _ = (sub1, sub2)
  }

  // MARK: - updateHeaderValues

  func testUpdateHeaderValues__whenReconnectIfConnected__whenConnected__shouldReconnect() async throws {
    factory.tasks.append(MockWebSocketTask())

    // Connect on mockTask.
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Update headers with reconnect — should create a new connection on the next task.
    await networkTransport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )

    // The reconnection task should be resumed (new connection started).
    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    // The reconnection request should contain the updated header.
    let reconnectRequest = factory.capturedRequests.last!
    expect(reconnectRequest.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer token123"))

    // The Sec-WebSocket-Protocol header should be preserved.
    expect(reconnectRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
      .to(equal("graphql-transport-ws"))

    _ = subscription
  }

  func testUpdateHeaderValues__withoutReconnect__whenConnected__shouldNotReconnect() async throws {
    // Connect on mockTask.
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Update headers without reconnect (default).
    await networkTransport.updateHeaderValues(["Authorization": "Bearer token123"])

    // Should still be connected — only 1 task was created (the init task).
    expect(self.factory.capturedRequests.count).to(equal(1))
    await expect { await self.networkTransport.connectionState }.to(equal(.connected))

    _ = subscription
  }

  func testUpdateHeaderValues__withReconnect__whenNotConnected__shouldNotReconnect() async throws {
    // Transport is in .notStarted state — no connection established.
    await networkTransport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )

    // No reconnection should happen — still only the init task.
    expect(self.factory.capturedRequests.count).to(equal(1))
  }

  func testUpdateHeaderValues__withNilValue__shouldRemoveHeader() async throws {
    factory.tasks.append(contentsOf: [MockWebSocketTask(), MockWebSocketTask()])

    // Connect on mockTask.
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Add a header and reconnect to the next task.
    await networkTransport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )
    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    // Verify the header was set.
    let request2 = factory.capturedRequests[1]
    expect(request2.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer token123"))

    // Ack on the current task so we're connected again.
    factory.currentTask.emit(.connectionAck(payload: nil))
    await expect(self.factory.currentTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Now remove the header by passing nil and reconnect to the next task.
    await networkTransport.updateHeaderValues(
      ["Authorization": nil],
      reconnectIfConnected: true
    )
    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    // Verify the header was removed.
    let request3 = factory.capturedRequests[2]
    expect(request3.value(forHTTPHeaderField: "Authorization")).to(beNil())

    // Protocol header should still be there.
    expect(request3.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
      .to(equal("graphql-transport-ws"))

    _ = subscription
  }

  func testUpdateHeaderValues__withMultipleHeaders__shouldApplyAll() async throws {
    factory.tasks.append(MockWebSocketTask())

    // Connect on mockTask.
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Update multiple headers at once.
    await networkTransport.updateHeaderValues([
      "Authorization": "Bearer token123",
      "X-Custom-Header": "custom-value",
    ], reconnectIfConnected: true)

    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    let reconnectRequest = factory.capturedRequests.last!
    expect(reconnectRequest.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer token123"))
    expect(reconnectRequest.value(forHTTPHeaderField: "X-Custom-Header")).to(equal("custom-value"))
    expect(reconnectRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
      .to(equal("graphql-transport-ws"))

    _ = subscription
  }

  func testUpdateHeaderValues__shouldPersistAcrossReconnections() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))
    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Set a header without reconnecting — just stores it on the request.
    await networkTransport.updateHeaderValues(["Authorization": "Bearer persistent"])

    // Disconnect task1 — triggers auto-reconnection.
    task1.finish()
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // The auto-reconnection request should include the previously set header.
    let reconnectRequest = factory.capturedRequests[2]
    expect(reconnectRequest.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer persistent"))

    // Complete the subscription so it doesn't block.
    task2.emit(.complete(id: operationID))
    _ = try await subscription.getAllValues()
  }

  // MARK: - updateConnectingPayload

  func testUpdateConnectingPayload__whenReconnectIfConnected__whenConnected__shouldReconnect() async throws {
    factory.tasks.append(MockWebSocketTask())

    // Connect on mockTask.
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Update payload with reconnect — should create a new connection on the next task.
    await networkTransport.updateConnectingPayload(
      ["authToken": "new-token"],
      reconnectIfConnected: true
    )

    // The reconnection task should be resumed (new connection started).
    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    // Ack the new connection and verify the connection_init payload.
    factory.currentTask.emit(.connectionAck(payload: nil))
    await expect(self.factory.currentTask.clientSentMessages(ofType: "connection_init").count).toEventually(equal(1))

    let initMessages = factory.currentTask.clientSentMessages(ofType: "connection_init")
    let payload = initMessages.first?["payload"] as? [String: Any]
    expect(payload?["authToken"] as? String).to(equal("new-token"))

    _ = subscription
  }

  func testUpdateConnectingPayload__withoutReconnect__whenConnected__shouldNotReconnect() async throws {
    factory.tasks.append(MockWebSocketTask())
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(connectingPayload: ["authToken": "old-token"])
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on the factory's current task.
    factory.currentTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: factory.currentTask, using: client)

    // Update payload without reconnect (default).
    await networkTransport.updateConnectingPayload(["authToken": "new-token"])

    // Should still be connected — no reconnection triggered.
    expect(self.factory.capturedRequests.count).to(equal(2))
    await expect { await self.networkTransport.connectionState }.to(equal(.connected))

    _ = subscription
  }

  func testUpdateConnectingPayload__withReconnect__whenNotConnected__shouldNotReconnect() async throws {
    // Transport is in .notStarted state — no connection established.
    await networkTransport.updateConnectingPayload(
      ["authToken": "new-token"],
      reconnectIfConnected: true
    )

    // No reconnection should happen — still only the init task.
    expect(self.factory.capturedRequests.count).to(equal(1))
  }

  func testUpdateConnectingPayload__withNilPayload__shouldClearPayload() async throws {
    factory.tasks.append(contentsOf: [MockWebSocketTask(), MockWebSocketTask(), MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(connectingPayload: ["authToken": "initial-token"])
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on the factory's current task.
    factory.currentTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: factory.currentTask, using: client)

    // Verify initial payload was sent.
    let initMessages1 = factory.currentTask.clientSentMessages(ofType: "connection_init")
    let payload1 = initMessages1.first?["payload"] as? [String: Any]
    expect(payload1?["authToken"] as? String).to(equal("initial-token"))

    // Clear payload by passing nil and reconnect to the next task.
    await networkTransport.updateConnectingPayload(nil, reconnectIfConnected: true)
    await expect(self.factory.currentTask.isResumed).toEventually(beTrue())

    // Ack on the current task.
    factory.currentTask.emit(.connectionAck(payload: nil))
    await expect(self.factory.currentTask.clientSentMessages(ofType: "connection_init").count).toEventually(equal(1))

    // Verify connection_init has no payload.
    let initMessages2 = factory.currentTask.clientSentMessages(ofType: "connection_init")
    expect(initMessages2.first?["payload"]).to(beNil())

    _ = subscription
  }

  func testUpdateConnectingPayload__shouldPersistAcrossReconnections() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))
    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Set a payload without reconnecting — just stores it in configuration.
    await networkTransport.updateConnectingPayload(["authToken": "persistent-token"])

    // Disconnect task1 — triggers auto-reconnection.
    task1.finish()
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // The auto-reconnection's connection_init should include the updated payload.
    let initMessages = task2.clientSentMessages(ofType: "connection_init")
    expect(initMessages.count).to(equal(1))
    let payload = initMessages.first?["payload"] as? [String: Any]
    expect(payload?["authToken"] as? String).to(equal("persistent-token"))

    // Complete the subscription so it doesn't block.
    task2.emit(.complete(id: operationID))
    _ = try await subscription.getAllValues()
  }

  // MARK: - Pause / Resume

  func testPause__whenConnected__shouldTransitionToPausedAndPreserveSubscribers() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Pause while connected.
    await networkTransport.pause()

    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    // The subscriber should still be registered — not finished.
    await expect { await self.networkTransport.subscriberCount }.to(equal(1))

    // The underlying WebSocket task should have been cancelled.
    expect(self.mockTask.cancelCode).to(equal(.goingAway))

    _ = subscription
  }

  func testPause__whenNotStarted__shouldBeNoop() async throws {
    // Transport is in .notStarted state — pause should be a no-op.
    await networkTransport.pause()

    await expect { await self.networkTransport.connectionState }.to(equal(.notStarted))
  }

  func testPause__whenAlreadyPaused__shouldBeNoop() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Pause once.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    // Pause again — should be a no-op.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.to(equal(.paused))
    await expect { await self.networkTransport.subscriberCount }.to(equal(1))

    _ = subscription
  }

  func testPause__shouldNotTriggerDidDisconnectDelegate() async throws {
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)

    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    expect(delegate.events).to(contain(.didConnect))

    // Pause.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    // Give time for any potential delegate callback.
    try await Task.sleep(nanoseconds: 100_000_000)

    // didDisconnect should NOT have been called — pause is intentional.
    expect(delegate.events).toNot(contain(.didDisconnect(hasError: false)))
    expect(delegate.events).toNot(contain(.didDisconnect(hasError: true)))

    _ = subscription
  }

  func testResume__whenPaused__shouldReconnectAndResubscribe() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result before pause.
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Before pause")))

    // Pause — closes connection, preserves subscriber.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    // Resume — creates new connection on the next task.
    await networkTransport.resume()

    // Acknowledge the new connection.
    factory.currentTask.emit(.connectionAck(payload: nil))

    // The subscription should be re-subscribed on the new connection.
    await expect(self.factory.currentTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // The re-subscribe should use the same operation ID.
    let resubscribedID = factory.currentTask.subscribeOperationID(at: 0)
    expect(resubscribedID).to(equal(operationID))

    // Deliver data on the new connection and complete.
    factory.currentTask.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 3, commentary: "After resume")))
    factory.currentTask.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()

    // Should have received data from both before pause and after resume.
    guard results.count == 2 else {
      fail("Expected 2 results but got \(results.count)")
      return
    }
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Before pause"))
    expect(results[1].data?.reviewAdded?.commentary).to(equal("After resume"))
  }

  func testResume__whenPaused__shouldFireDidReconnectDelegate() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await networkTransport.setDelegate(delegate)
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    expect(delegate.events).to(contain(.didConnect))

    // Pause and resume.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    await networkTransport.resume()
    factory.currentTask.emit(.connectionAck(payload: nil))

    // Should fire didReconnect (not didConnect) since hasBeenConnected is true.
    await expect(delegate.events).toEventually(contain(.didReconnect))

    // Only one didConnect (the initial one).
    expect(delegate.events.filter { $0 == .didConnect }.count).to(equal(1))

    _ = subscription
  }

  func testResume__whenNotStarted__shouldOpenConnection() async throws {
    // Transport starts in .notStarted state. Resume should open the connection eagerly.
    await networkTransport.resume()

    // The mock task should have been resumed (connection opened).
    await expect(self.mockTask.isResumed).toEventually(beTrue())

    // State should transition to .connecting.
    await expect { await self.networkTransport.connectionState }.to(equal(.connecting))

    // Acknowledge the connection.
    mockTask.emit(.connectionAck(payload: nil))
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.connected))

    // Now a subscribe call should reuse this connection (no extra connection_init).
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Only one connection_init should have been sent total.
    expect(self.mockTask.clientSentMessages(ofType: "connection_init").count).to(equal(1))

    _ = subscription
  }

  func testResume__whenDisconnected__shouldOpenConnection() async throws {
    factory.tasks.append(MockWebSocketTask())

    // Connect and disconnect (reconnection disabled by default).
    mockTask.emit(.connectionAck(payload: nil))
    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Disconnect — finishes all subscribers since reconnection is disabled.
    mockTask.finish()
    _ = try? await subscription.getAllValues()

    await expect { await self.networkTransport.connectionState }.toEventually(equal(.disconnected))

    // Resume from disconnected state — should open a new connection.
    await networkTransport.resume()

    factory.currentTask.emit(.connectionAck(payload: nil))
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.connected))

    // New subscribe call should work on the new connection.
    let (subscription2, operationID2) = try await subscribe(on: factory.currentTask, using: client)

    factory.currentTask.emit(.next(id: operationID2, payload: Self.reviewAddedPayload(stars: 4, commentary: "After resume")))
    factory.currentTask.emit(.complete(id: operationID2))

    let results = try await subscription2.getAllValues()
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("After resume"))
  }

  func testResume__whenConnected__shouldBeNoop() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Already connected — resume should be a no-op.
    await networkTransport.resume()

    await expect { await self.networkTransport.connectionState }.to(equal(.connected))

    // No additional connection_init should have been sent.
    expect(self.mockTask.clientSentMessages(ofType: "connection_init").count).to(equal(1))

    _ = subscription
  }

  func testPause__withMultipleSubscribers__shouldPreserveAll() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))

    let (sub1, id1) = try await subscribe(on: task1, using: client)
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    // Pause — both subscribers should be preserved.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))
    await expect { await self.networkTransport.subscriberCount }.to(equal(2))

    // Resume on the next task.
    await networkTransport.resume()
    factory.currentTask.emit(.connectionAck(payload: nil))

    // Both subscriptions should be re-subscribed.
    await expect(self.factory.currentTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    let resubscribedIDs = Set(factory.currentTask.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set([id1, id2])))

    // Deliver data and complete for both.
    factory.currentTask.emit(.next(id: id1, payload: Self.reviewAddedPayload(stars: 5, commentary: "Sub1 resumed")))
    factory.currentTask.emit(.complete(id: id1))
    factory.currentTask.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 3, commentary: "Sub2 resumed")))
    factory.currentTask.emit(.complete(id: id2))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Sub1 resumed"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Sub2 resumed"))
  }

  // MARK: - Subscription State

  func testSubscriptionState__shouldBePending__beforeConnectionAck() async throws {
    // Don't emit connectionAck yet — subscribe while the connection is still being established.
    let stream = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    expect(stream.state).to(equal(.pending))

    // Now acknowledge so the subscription can proceed — then complete it so cleanup runs.
    mockTask.emit(.connectionAck(payload: nil))
    await expect(self.mockTask.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = mockTask.subscribeOperationID(at: 0)
    mockTask.emit(.complete(id: operationID))

    _ = try await stream.getAllValues()
  }

  func testSubscriptionState__shouldBecomeActive__afterSubscribeMessageSent() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, operationID) = try await subscribe(on: mockTask, using: client)

    // After subscribe message has been sent, state should be active.
    expect(stream.state).to(equal(.active))

    // Complete the subscription.
    mockTask.emit(.complete(id: operationID))
    _ = try await stream.getAllValues()
  }

  func testSubscriptionState__shouldBeFinishedCompleted__afterServerComplete() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, operationID) = try await subscribe(on: mockTask, using: client)
    expect(stream.state).to(equal(.active))

    // Server completes the subscription.
    mockTask.emit(.complete(id: operationID))
    _ = try await stream.getAllValues()

    expect(stream.state).to(equal(.finished(.completed)))
  }

  func testSubscriptionState__shouldBeFinishedError__afterServerError() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, operationID) = try await subscribe(on: mockTask, using: client)
    expect(stream.state).to(equal(.active))

    // Server sends an error for this subscription.
    mockTask.emit(.error(id: operationID, payload: [["message": "Something went wrong"]]))

    do {
      _ = try await stream.getAllValues()
      fail("Expected stream to throw")
    } catch {
      // Expected
    }

    expect(stream.state).to(equal(.finished(.error(WebSocketTransport.Error.graphQLErrors([])))))
  }

  func testSubscriptionState__shouldBeFinishedCancelled__whenClientCancels() async throws {
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, _) = try await subscribe(on: mockTask, using: client)
    expect(stream.state).to(equal(.active))

    // Cancel the subscription by wrapping iteration in a task and cancelling it.
    let iterationTask = Task {
      for try await _ in stream {}
    }
    iterationTask.cancel()

    // Wait for cancellation to propagate.
    _ = try? await iterationTask.value

    await expect(stream.state).toEventually(equal(.finished(.cancelled)))
  }

  func testSubscriptionState__shouldBecomeReconnecting__onDisconnectWithReconnectEnabled() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))
    let (stream, operationID) = try await subscribe(on: task1, using: client)
    expect(stream.state).to(equal(.active))

    // Disconnect — should trigger reconnection.
    task1.finish()

    await expect(stream.state).toEventually(equal(.reconnecting))

    // Complete reconnection.
    task2.emit(.connectionAck(payload: nil))
    await expect(stream.state).toEventually(equal(.active))

    // Complete the subscription.
    task2.emit(.complete(id: operationID))
    _ = try await stream.getAllValues()
  }

  func testSubscriptionState__shouldBecomePaused__whenTransportPaused() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, MockWebSocketTask()])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))
    let (stream, operationID) = try await subscribe(on: task1, using: client)
    expect(stream.state).to(equal(.active))

    // Pause the transport.
    await networkTransport.pause()
    expect(stream.state).to(equal(.paused))

    // Resume — should reconnect and restore active.
    await networkTransport.resume()
    factory.currentTask.emit(.connectionAck(payload: nil))
    await expect(stream.state).toEventually(equal(.active))

    // Complete the subscription.
    factory.currentTask.emit(.complete(id: operationID))
    _ = try await stream.getAllValues()
  }

  func testSubscriptionState__shouldBeFinishedCompleted__whenDisconnectWithReconnectDisabled() async throws {
    // Default configuration has reconnectionInterval = -1 (disabled).
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, operationID) = try await subscribe(on: mockTask, using: client)
    expect(stream.state).to(equal(.active))

    // Deliver one result then disconnect.
    mockTask.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Before disconnect")))
    mockTask.finish()

    _ = try await stream.getAllValues()

    // Without error, disconnect finishes with .completed.
    expect(stream.state).to(equal(.finished(.completed)))
  }

  func testSubscriptionState__shouldBeFinishedError__whenDisconnectWithError() async throws {
    // Default configuration has reconnectionInterval = -1 (disabled).
    mockTask.emit(.connectionAck(payload: nil))

    let (stream, _) = try await subscribe(on: mockTask, using: client)
    expect(stream.state).to(equal(.active))

    // Disconnect with an error.
    mockTask.throw(URLError(.networkConnectionLost))

    do {
      _ = try await stream.getAllValues()
      fail("Expected stream to throw")
    } catch {
      // Expected
    }

    expect(stream.state).to(equal(.finished(.error(URLError(.networkConnectionLost)))))
  }

  func testPause__duringReconnectionDelay__shouldStopReconnection() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0.5)
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Disconnect — triggers reconnection with 0.5s delay.
    task1.finish()

    // Pause during the reconnection delay.
    // Wait briefly to ensure we're in the reconnection delay.
    try await Task.sleep(nanoseconds: 50_000_000)
    await networkTransport.pause()

    // Wait for the reconnection delay to expire.
    try await Task.sleep(nanoseconds: 600_000_000)

    // Task2 should NOT have been used for auto-reconnection because we paused.
    expect(task2.isResumed).to(beFalse())

    // State should be .paused.
    await expect { await self.networkTransport.connectionState }.to(equal(.paused))

    // Subscriber should still be alive.
    await expect { await self.networkTransport.subscriberCount }.to(equal(1))

    // Resume — consumes task2 (auto-reconnection was suppressed, so task2 is still available).
    await networkTransport.resume()
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    _ = subscription
  }

  func testSubscription__whilePaused__shouldWaitForResume() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))

    let (sub1, id1) = try await subscribe(on: task1, using: client)

    // Pause.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    // Start a new subscription while paused — it should wait.
    let client = self.client!
    let sub2Task = Task {
      try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    }

    // Give time for the subscribe to register but not complete.
    try await Task.sleep(nanoseconds: 100_000_000)

    // Resume on task2.
    await networkTransport.resume()
    task2.emit(.connectionAck(payload: nil))

    // The original subscription should be re-subscribed, and the new one should also subscribe.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    let sub2 = try await sub2Task.value
    let id2 = task2.subscribeOperationID(at: 1)

    // Deliver data for both.
    task2.emit(.next(id: id1, payload: Self.reviewAddedPayload(stars: 5, commentary: "Existing sub")))
    task2.emit(.complete(id: id1))
    task2.emit(.next(id: id2, payload: Self.reviewAddedPayload(stars: 3, commentary: "New sub")))
    task2.emit(.complete(id: id2))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Existing sub"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("New sub"))
  }

  func testMultiplePauseResumeCycles__shouldPreserveSubscriptions() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let task3 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2, task3])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Connect on task1.
    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // First pause/resume cycle.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    await networkTransport.resume()
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Second pause/resume cycle.
    await networkTransport.pause()
    await expect { await self.networkTransport.connectionState }.toEventually(equal(.paused))

    await networkTransport.resume()
    task3.emit(.connectionAck(payload: nil))
    await expect(task3.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver data on the final connection and complete.
    task3.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 4, commentary: "After two cycles")))
    task3.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("After two cycles"))
  }

  // MARK: - Client Awareness Headers

  func testClientAwarenessHeaders__withMetadata__shouldApplyHeadersToConnectionRequest() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        clientAwarenessMetadata: ClientAwarenessMetadata(
          clientApplicationName: "test-app",
          clientApplicationVersion: "1.2.3"
        )
      )
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Verify the client awareness headers were applied to the captured request.
    let capturedRequest = factory.capturedRequests.last!
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("test-app"))
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("1.2.3"))

    task1.emit(.complete(id: operationID))
    _ = subscription
  }

  func testClientAwarenessHeaders__withoutMetadata__shouldNotApplyHeaders() async throws {
    // Default setUp creates a transport with no clientAwarenessMetadata.
    mockTask.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    let capturedRequest = factory.capturedRequests.last!
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(beNil())
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(beNil())

    mockTask.emit(.complete(id: operationID))
    _ = subscription
  }

  func testClientAwarenessHeaders__withNameOnly__shouldApplyOnlyNameHeader() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        clientAwarenessMetadata: ClientAwarenessMetadata(
          clientApplicationName: "my-app",
          clientApplicationVersion: nil
        )
      )
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    let capturedRequest = factory.capturedRequests.last!
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("my-app"))
    expect(capturedRequest.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(beNil())

    task1.emit(.complete(id: operationID))
    _ = subscription
  }

  func testClientAwarenessHeaders__shouldPersistAcrossReconnection() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    factory.tasks.append(contentsOf: [task1, task2])
    let store = ApolloStore.mock()
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        reconnectionInterval: 0,
        clientAwarenessMetadata: ClientAwarenessMetadata(
          clientApplicationName: "reconnect-app",
          clientApplicationVersion: "2.0.0"
        )
      )
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Verify headers on initial connection.
    let initialRequest = factory.capturedRequests.last!
    expect(initialRequest.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("reconnect-app"))
    expect(initialRequest.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("2.0.0"))

    // Simulate disconnect → triggers auto-reconnection.
    task1.finish()

    // Wait for the reconnected connection's subscribe message.
    task2.emit(.connectionAck(payload: nil))
    await expect(task2.clientSentMessages(ofType: "subscribe").count)
      .toEventually(equal(1))

    // Verify headers persisted on the reconnection request.
    let reconnectRequest = factory.capturedRequests.last!
    expect(reconnectRequest.value(forHTTPHeaderField: "apollographql-client-name"))
      .to(equal("reconnect-app"))
    expect(reconnectRequest.value(forHTTPHeaderField: "apollographql-client-version"))
      .to(equal("2.0.0"))

    task2.emit(.complete(id: task2.subscribeOperationID(at: 0)))
    let results = try await subscription.getAllValues()
    _ = results
  }

  // MARK: - Subscription Cache Read

  func testSubscription__cacheThenNetwork__cacheHit__yieldsCacheThenServerResults() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Pre-populate the cache with subscription data.
    try await store.publish(records: [
      "SUBSCRIPTION_ROOT": ["reviewAdded": CacheReference("SUBSCRIPTION_ROOT.reviewAdded")],
      "SUBSCRIPTION_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 3,
        "commentary": "Cached review",
      ],
    ])

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .cacheThenNetwork
    )

    // Wait for the subscribe message, then send a server result and complete.
    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Server review")))
    task1.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(2))

    // First result from cache
    expect(results[0].source).to(equal(.cache))
    expect(results[0].data?.reviewAdded?.stars).to(equal(3))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Cached review"))

    // Second result from server
    expect(results[1].source).to(equal(.server))
    expect(results[1].data?.reviewAdded?.stars).to(equal(5))
    expect(results[1].data?.reviewAdded?.commentary).to(equal("Server review"))
  }

  func testSubscription__cacheThenNetwork__cacheMiss__yieldsOnlyServerResults() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Do not populate cache — cache miss.

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .cacheThenNetwork
    )

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Server only")))
    task1.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(1))
    expect(results[0].source).to(equal(.server))
    expect(results[0].data?.reviewAdded?.stars).to(equal(5))
  }

  func testSubscription__networkOnly__doesNotReadCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Pre-populate the cache — but networkOnly should not read it.
    try await store.publish(records: [
      "SUBSCRIPTION_ROOT": ["reviewAdded": CacheReference("SUBSCRIPTION_ROOT.reviewAdded")],
      "SUBSCRIPTION_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 3,
        "commentary": "Cached review",
      ],
    ])

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .networkOnly
    )

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Server review")))
    task1.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(1))
    expect(results[0].source).to(equal(.server))
    expect(results[0].data?.reviewAdded?.stars).to(equal(5))
  }

  // MARK: - Subscription Cache Write

  func testSubscription__writeResultsToCache__writesServerResponsesToStore() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .networkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: true)
    )

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 4, commentary: "Written to cache")))
    task1.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.stars).to(equal(4))

    // Verify data was written to the cache.
    let cachedResponse = try await store.load(MockSubscription<ReviewAddedData>())
    expect(cachedResponse).toNot(beNil())
    expect(cachedResponse?.data?.reviewAdded?.stars).to(equal(4))
    expect(cachedResponse?.data?.reviewAdded?.commentary).to(equal("Written to cache"))
  }

  func testSubscription__writeResultsToCache_false__doesNotWriteToStore() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .networkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 4, commentary: "Not cached")))
    task1.emit(.complete(id: operationID))

    let results = try await subscription.getAllValues()
    expect(results.count).to(equal(1))

    // Verify data was NOT written to the cache.
    let cachedResponse = try await store.load(MockSubscription<ReviewAddedData>())
    expect(cachedResponse).to(beNil())
  }

  // MARK: - Query Cache Behaviors (over WebSocket)

  func testQuery__cacheFirst__cacheHit__returnsCacheWithoutWebSocketMessage() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Pre-populate cache with query data.
    try await store.publish(records: [
      "QUERY_ROOT": ["reviewAdded": CacheReference("QUERY_ROOT.reviewAdded")],
      "QUERY_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 3,
        "commentary": "Cached query",
      ],
    ])

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .cacheFirst
    )

    expect(result.source).to(equal(.cache))
    expect(result.data?.reviewAdded?.stars).to(equal(3))
    expect(result.data?.reviewAdded?.commentary).to(equal("Cached query"))

    // No WebSocket subscribe message should have been sent.
    expect(task1.clientSentMessages(ofType: "subscribe").count).to(equal(0))
  }

  func testQuery__cacheFirst__cacheMiss__fetchesViaWebSocket() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Empty cache — cache miss triggers network fetch.
    // Messages are pre-emitted and queued by MockWebSocketTask. The operation ID "1" relies on
    // ApolloSequencedOperationMessageIdCreator starting at 1 (the default).
    task1.emit(.connectionAck(payload: nil))
    task1.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "Server query")))
    task1.emit(.complete(id: "1"))

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .cacheFirst
    )

    expect(result.source).to(equal(.server))
    expect(result.data?.reviewAdded?.stars).to(equal(5))
    expect(task1.clientSentMessages(ofType: "subscribe").count).to(equal(1))
  }

  func testQuery__cacheOnly__cacheHit__returnsCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    try await store.publish(records: [
      "QUERY_ROOT": ["reviewAdded": CacheReference("QUERY_ROOT.reviewAdded")],
      "QUERY_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 2,
        "commentary": "Cache only hit",
      ],
    ])

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .cacheOnly
    )

    expect(result).toNot(beNil())
    expect(result?.source).to(equal(.cache))
    expect(result?.data?.reviewAdded?.stars).to(equal(2))

    // No WebSocket connection should have been opened.
    expect(task1.clientSentMessages(ofType: "subscribe").count).to(equal(0))
    expect(task1.clientSentMessages(ofType: "connection_init").count).to(equal(0))
  }

  func testQuery__cacheOnly__cacheMiss__returnsNil() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .cacheOnly
    )

    expect(result).to(beNil())
    expect(task1.clientSentMessages(ofType: "subscribe").count).to(equal(0))
  }

  func testQuery__networkOnly__writeResultsToCache__populatesCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))
    task1.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 5, commentary: "Cached by write")))
    task1.emit(.complete(id: "1"))

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .networkOnly,
      requestConfiguration: RequestConfiguration(writeResultsToCache: true)
    )

    expect(result.source).to(equal(.server))
    expect(result.data?.reviewAdded?.stars).to(equal(5))

    // Verify the result was written to the cache.
    let cachedResponse = try await store.load(MockQuery<ReviewAddedData>())
    expect(cachedResponse).toNot(beNil())
    expect(cachedResponse?.data?.reviewAdded?.stars).to(equal(5))
    expect(cachedResponse?.data?.reviewAdded?.commentary).to(equal("Cached by write"))
  }

  // MARK: - Mutation Cache Write (over WebSocket)

  func testMutation__writeResultsToCache__populatesCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))
    task1.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 4, commentary: "Mutation cached")))
    task1.emit(.complete(id: "1"))

    let result = try await client.perform(
      mutation: MockMutation<ReviewAddedData>(),
      requestConfiguration: RequestConfiguration(writeResultsToCache: true)
    )

    expect(result.data?.reviewAdded?.stars).to(equal(4))

    // Verify the result was written to the cache.
    let cachedResponse = try await store.load(MockMutation<ReviewAddedData>())
    expect(cachedResponse).toNot(beNil())
    expect(cachedResponse?.data?.reviewAdded?.stars).to(equal(4))
  }

  func testMutation__writeResultsToCache_false__doesNotPopulateCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))
    task1.emit(.next(id: "1", payload: Self.reviewAddedPayload(stars: 4, commentary: "Not cached")))
    task1.emit(.complete(id: "1"))

    let result = try await client.perform(
      mutation: MockMutation<ReviewAddedData>(),
      requestConfiguration: RequestConfiguration(writeResultsToCache: false)
    )

    expect(result.data?.reviewAdded?.stars).to(equal(4))

    // Verify the result was NOT written to the cache.
    let cachedResponse = try await store.load(MockMutation<ReviewAddedData>())
    expect(cachedResponse).to(beNil())
  }

  // MARK: - Network Failure Cache Fallback

  func testQuery__networkFirst__connectionFailure__fallsBackToCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Pre-populate the cache with query data.
    try await store.publish(records: [
      "QUERY_ROOT": ["reviewAdded": CacheReference("QUERY_ROOT.reviewAdded")],
      "QUERY_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 3,
        "commentary": "Cached fallback",
      ],
    ])

    // Connection fails before ack — transport error.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .networkFirst
    )

    // Should fall back to cached data on transport failure.
    expect(result.source).to(equal(.cache))
    expect(result.data?.reviewAdded?.stars).to(equal(3))
    expect(result.data?.reviewAdded?.commentary).to(equal("Cached fallback"))
  }

  func testQuery__networkFirst__graphQLError__doesNotFallBackToCache() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    // Pre-populate the cache so fallback data is available if incorrectly triggered.
    try await store.publish(records: [
      "QUERY_ROOT": ["reviewAdded": CacheReference("QUERY_ROOT.reviewAdded")],
      "QUERY_ROOT.reviewAdded": [
        "__typename": "ReviewAdded",
        "stars": 99,
        "commentary": "Should not see this",
      ],
    ])

    // Messages are pre-emitted and queued. ID "1" relies on the default sequenced ID creator.
    task1.emit(.connectionAck(payload: nil))
    task1.emit(.error(id: "1", payload: [["message": "Validation failed"]]))

    // Should propagate the GraphQL error, NOT fall back to cache.
    do {
      _ = try await client.fetch(
        query: MockQuery<ReviewAddedData>(),
        cachePolicy: .networkFirst
      )
      fail("Expected a GraphQL error to be thrown")
    } catch {
      expect(error).to(matchError(WebSocketTransport.Error.graphQLErrors([])))
    }
  }

  // MARK: - Cache Write Failure Propagation

  func testSubscription__writeResultsToCache__cacheWriteFailure__terminatesStream() async throws {
    let task1 = MockWebSocketTask()
    factory.tasks.append(task1)

    // A cache that throws on writes but works for reads.
    let failingCache = FailingWriteCache()
    let store = ApolloStore(cache: failingCache)
    networkTransport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    client = ApolloClient(networkTransport: networkTransport!, store: store)

    task1.emit(.connectionAck(payload: nil))

    let subscription = try client.subscribe(
      subscription: MockSubscription<ReviewAddedData>(),
      cachePolicy: .networkOnly
    )

    await expect(task1.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    let operationID = task1.subscribeOperationID(at: 0)

    // Server sends valid data, but the cache write will fail.
    task1.emit(.next(id: operationID, payload: Self.reviewAddedPayload(stars: 5, commentary: "Will fail write")))

    // The stream should terminate with the cache write error.
    do {
      _ = try await subscription.getAllValues()
      fail("Expected a cache write error to be thrown")
    } catch {
      expect(error).to(beAKindOf(FailingWriteCache.WriteError.self))
    }
  }
}

// MARK: - Test Helpers

/// A ``NormalizedCache`` that always throws on write operations (merge).
/// Used to verify that cache write errors propagate correctly.
private final class FailingWriteCache: NormalizedCache, @unchecked Sendable {
  struct WriteError: Swift.Error, Equatable {}

  func loadRecords(forKeys keys: Set<CacheKey>) async throws -> [CacheKey: Record] {
    return [:]
  }

  func merge(records: RecordSet) async throws -> Set<CacheKey> {
    throw WriteError()
  }

  func removeRecord(for key: CacheKey) async throws {}
  func removeRecords(matching pattern: CacheKey) async throws {}
  func clear() async throws {}
}
