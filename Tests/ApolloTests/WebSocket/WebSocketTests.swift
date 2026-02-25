import XCTest
import Nimble
@testable import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
@testable import ApolloWebSocket

#warning("Rewrite when websocket is implemented")

/// A mock delegate that records lifecycle events from ``WebSocketTransport`` for test assertions.
///
/// Delegate methods are `isolated` to the `WebSocketTransport` actor, so writes to the
/// internal event list are serialized through the actor. Reads from the test thread are
/// protected by an `NSLock` to prevent data races with `toEventually` polling.
final class MockWebSocketTransportDelegate: WebSocketTransportDelegate, @unchecked Sendable {
  enum Event: Equatable, CustomStringConvertible {
    case didConnect
    case didReconnect
    case didDisconnect(hasError: Bool)
    case didReceivePing(hasPayload: Bool)
    case didReceivePong(hasPayload: Bool)

    var description: String {
      switch self {
      case .didConnect: return "didConnect"
      case .didReconnect: return "didReconnect"
      case .didDisconnect(let hasError): return "didDisconnect(hasError: \(hasError))"
      case .didReceivePing(let hasPayload): return "didReceivePing(hasPayload: \(hasPayload))"
      case .didReceivePong(let hasPayload): return "didReceivePong(hasPayload: \(hasPayload))"
      }
    }
  }

  private let lock = NSLock()
  private var _events: [Event] = []

  var events: [Event] {
    lock.lock()
    defer { lock.unlock() }
    return _events
  }

  private func record(_ event: Event) {
    lock.lock()
    _events.append(event)
    lock.unlock()
  }

  func webSocketTransportDidConnect(_ webSocketTransport: isolated WebSocketTransport) {
    record(.didConnect)
  }

  func webSocketTransportDidReconnect(_ webSocketTransport: isolated WebSocketTransport) {
    record(.didReconnect)
  }

  func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didDisconnectWithError error: (any Error)?
  ) {
    record(.didDisconnect(hasError: error != nil))
  }

  func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didReceivePingWithPayload payload: JSONObject?
  ) {
    record(.didReceivePing(hasPayload: payload != nil))
  }

  func webSocketTransport(
    _ webSocketTransport: isolated WebSocketTransport,
    didReceivePongWithPayload payload: JSONObject?
  ) {
    record(.didReceivePong(hasPayload: payload != nil))
  }
}

class WebSocketTests: XCTestCase, MockResponseProvider {
  var networkTransport: WebSocketTransport!
  var client: ApolloClient!
  var session: MockURLSession!

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

  // MARK: - Test Helpers

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
    stream: AsyncThrowingStream<GraphQLResponse<MockSubscription<ReviewAddedData>>, any Error>,
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
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // The connection_init message should have been sent with no payload.
    let initMessages = mockTask.clientSentMessages(ofType: "connection_init")
    expect(initMessages.count).to(equal(1))
    expect(initMessages.first?["payload"]).to(beNil())

    _ = subscription
  }

  func testConnectionInit__withConnectingPayload__shouldSendPayloadInConnectionInit() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(connectingPayload: [
        "authToken": "my-secret-token",
        "version": 2,
      ])
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Verify the connection_init message includes the connecting payload.
    let initMessages = task1.clientSentMessages(ofType: "connection_init")
    expect(initMessages.count).to(equal(1))

    let payload = initMessages.first?["payload"] as? [String: Any]
    expect(payload?["authToken"] as? String).to(equal("my-secret-token"))
    expect(payload?["version"] as? Int).to(equal(2))

    _ = subscription
  }

  func testConnectionInit__withConnectingPayload__shouldResendPayloadOnReconnect() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        reconnectionInterval: 0,
        connectingPayload: ["authToken": "reconnect-token"]
      )
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Establish initial connection.
    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Verify first connection_init has the payload.
    let initMessages1 = task1.clientSentMessages(ofType: "connection_init")
    expect(initMessages1.count).to(equal(1))
    let payload1 = initMessages1.first?["payload"] as? [String: Any]
    expect(payload1?["authToken"] as? String).to(equal("reconnect-token"))

    // Disconnect — triggers reconnection on task2.
    task1.finish()

    // Task2 reconnects.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
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

    let (sub1, _) = try await subscribe(on: mockTask, using: client)

    // Now start a second subscription — the connection is already established,
    // so ensureConnected() should return immediately without reconnecting.
    let (sub2, _) = try await subscribe(on: mockTask, using: client)

    // Only one connection_init should have been sent (no reconnect).
    expect(mockTask.clientSentMessages(ofType: "connection_init").count).to(equal(1))

    _ = (sub1, sub2)
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

  // MARK: - Client-Side Cancellation

  func testSubscription__whenCancelledBeforeConnectionAck__shouldNotSendSubscribe() async throws {
    let mockTask = session.mockWebSocketTask

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
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal(operationID))
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

    let (subscription, operationID) = try await subscribe(on: mockTask, using: client)

    // Server sends error — the subscription is terminated server-side, so client should not
    // send a complete message back.
    mockTask.emit(.string(
      #"{"type":"error","id":"\#(operationID)","payload":[{"message":"Unauthorized"}]}"#
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

    let (sub1, id1) = try await subscribe(on: mockTask, using: client)
    let (sub2, id2) = try await subscribe(on: mockTask, using: client)

    // Server sends error only for sub1.
    mockTask.emit(.string(
      #"{"type":"error","id":"\#(id1)","payload":[{"message":"Failed"}]}"#
    ))

    // Sub2 should still receive data normally.
    mockTask.emit(.string(
      #"{"type":"next","id":"\#(id2)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":4,"commentary":"Still works"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"\#(id2)"}"#))

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
    await expect(mockTask.clientSentMessages(ofType: "complete").count).toEventually(equal(1))
    expect(mockTask.clientSentMessages(ofType: "complete").first?["id"] as? String).to(equal(id1))

    // Sub2 should still work — send it data and complete from server.
    mockTask.emit(.string(
      #"{"type":"next","id":"\#(id2)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Still alive"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"\#(id2)"}"#))

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

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result on task1.
    task1.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Before disconnect"}}}}"#
    ))

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // Task2 should be connected and re-subscribed.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Wait for the re-subscribe message on task2.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))
    expect(task2.clientSentMessages(ofType: "subscribe").first?["id"] as? String).to(equal(operationID))

    // Deliver a result on the new connection and complete.
    task2.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"After reconnect"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(operationID)"}"#))

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
    let (sub1, id1) = try await subscribe(on: task1, using: client)
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    // Disconnect task1 — triggers reconnection.
    task1.finish()

    // Task2: connection_ack triggers re-subscribe of both active subscriptions.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Wait for both re-subscribe messages on task2.
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    // Verify both IDs were re-subscribed.
    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set([id1, id2])))

    // Deliver data and complete for both on the new connection.
    task2.emit(.string(
      #"{"type":"next","id":"\#(id1)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Sub1 reconnected"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(id1)"}"#))
    task2.emit(.string(
      #"{"type":"next","id":"\#(id2)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Sub2 reconnected"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(id2)"}"#))

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

    let (subscription, _) = try await subscribe(on: task1, using: client)

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
    await expect { await transport.subscriberCount }.toEventually(equal(0))

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

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result on task1.
    task1.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Before error"}}}}"#
    ))

    // Simulate a transport error (e.g. network failure) — not a graceful close.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // Task2 reconnects and re-subscribes.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    task2.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"After error"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(operationID)"}"#))

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

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result then hit a transport error.
    task1.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Only result"}}}}"#
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

    let (sub1, id1) = try await subscribe(on: task1, using: client)
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    // Transport error kills the connection.
    struct MockTransportError: Swift.Error {}
    task1.throw(MockTransportError())

    // Task2 reconnects — both subscriptions should be re-subscribed.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(2))

    let resubscribedIDs = Set(task2.clientSentMessages(ofType: "subscribe").compactMap { $0["id"] as? String })
    expect(resubscribedIDs).to(equal(Set([id1, id2])))

    // Deliver data and complete for both.
    task2.emit(.string(
      #"{"type":"next","id":"\#(id1)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Sub1 recovered"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(id1)"}"#))
    task2.emit(.string(
      #"{"type":"next","id":"\#(id2)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Sub2 recovered"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(id2)"}"#))

    let results1 = try await sub1.getAllValues()
    let results2 = try await sub2.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("Sub1 recovered"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Sub2 recovered"))
  }

  // MARK: - Ping / Pong

  func testPing__whenServerSendsPing__shouldReplyWithPong() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a ping — transport should reply with a pong.
    mockTask.emit(.string(#"{"type":"ping"}"#))

    await expect(mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(1))

    // The pong should have no payload.
    let pongMessage = mockTask.clientSentMessages(ofType: "pong").first
    expect(pongMessage?["payload"]).to(beNil())

    _ = subscription
  }

  func testPing__whenServerSendsPingWithPayload__shouldReplyWithPongWithoutPayload() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends a ping with payload — transport should reply with a pong (no payload).
    mockTask.emit(.string(#"{"type":"ping","payload":{"hello":"world"}}"#))

    await expect(mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(1))

    // The pong should have no payload — we don't echo the ping's payload.
    let pongMessage = mockTask.clientSentMessages(ofType: "pong").first
    expect(pongMessage?["payload"]).to(beNil())

    _ = subscription
  }

  func testPong__whenServerSendsPong__shouldNotReply() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends an unsolicited pong — transport should NOT reply.
    mockTask.emit(.string(#"{"type":"pong"}"#))

    // Give time for any potential response to be sent.
    try await Task.sleep(nanoseconds: 100_000_000)

    // No ping or pong messages should have been sent by the client.
    expect(mockTask.clientSentMessages(ofType: "ping").count).to(equal(0))
    expect(mockTask.clientSentMessages(ofType: "pong").count).to(equal(0))

    _ = subscription
  }

  func testPing__whenServerSendsMultiplePings__shouldReplyToEach() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: mockTask, using: client)

    // Server sends multiple pings — transport should reply to each.
    mockTask.emit(.string(#"{"type":"ping"}"#))
    mockTask.emit(.string(#"{"type":"ping","payload":{"seq":2}}"#))
    mockTask.emit(.string(#"{"type":"ping","payload":{"seq":3}}"#))

    await expect(mockTask.clientSentMessages(ofType: "pong").count).toEventually(equal(3))

    _ = subscription
  }

  // MARK: - Unrecognized Messages

  func testSubscription__whenServerSendsUnrecognizedMessage__shouldTerminateWithError() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

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

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Deliver one result.
    task1.emit(.string(
      #"{"type":"next","id":"\#(operationID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Only result"}}}}"#
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

  // MARK: - Queries

  func testQuery__shouldReceiveSingleResult() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Query result"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))

    let result = try await client.fetch(
      query: MockQuery<ReviewAddedData>(),
      cachePolicy: .networkOnly
    )

    expect(result.data?.reviewAdded?.stars).to(equal(5))
    expect(result.data?.reviewAdded?.commentary).to(equal("Query result"))

    // Should have sent a subscribe message (graphql-ws uses subscribe for all operation types).
    expect(mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(1))
  }

  func testQuery__whenServerSendsError__shouldThrow() async throws {
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"error","id":"1","payload":[{"message":"Query failed"}]}"#
    ))

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

    // Start a query — it blocks waiting for the response.
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
    let mockTask = session.mockWebSocketTask

    mockTask.emit(.string(#"{"type":"connection_ack"}"#))
    mockTask.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":3,"commentary":"Mutation result"}}}}"#
    ))
    mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))

    let result = try await client.perform(mutation: MockMutation<ReviewAddedData>())

    expect(result.data?.reviewAdded?.stars).to(equal(3))
    expect(result.data?.reviewAdded?.commentary).to(equal("Mutation result"))

    expect(mockTask.clientSentMessages(ofType: "subscribe").count).to(equal(1))
  }

  func testMutation__whenConnectionDropsWithReconnect__shouldNotRetry() async throws {
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

    // Start a subscription first.
    let (subscription, subscriptionID) = try await subscribe(on: task1, using: client)

    // Start a query — it blocks waiting for the response.
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

    // The subscription should survive — task2 reconnects.
    task2.emit(.string(#"{"type":"connection_ack"}"#))

    // Only the subscription should be re-subscribed on task2 (not the query).
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Deliver data on the new connection and complete.
    task2.emit(.string(
      #"{"type":"next","id":"\#(subscriptionID)","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":4,"commentary":"After reconnect"}}}}"#
    ))
    task2.emit(.string(#"{"type":"complete","id":"\#(subscriptionID)"}"#))

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

    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(operationMessageIdCreator: FixedIdCreator())
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // The subscribe message should use the custom ID.
    expect(operationID).to(equal("custom-id-123"))

    // Server responds using the custom ID.
    task1.emit(.string(
      #"{"type":"next","id":"custom-id-123","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"Custom ID works"}}}}"#
    ))
    task1.emit(.string(#"{"type":"complete","id":"custom-id-123"}"#))

    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.commentary).to(equal("Custom ID works"))
  }

  // MARK: - Delegate

  func testDelegate__whenConnectionEstablished__shouldCallDidConnect() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    expect(delegate.events).to(contain(.didConnect))
    expect(delegate.events).toNot(contain(.didReconnect))

    _ = subscription
  }

  func testDelegate__whenReconnected__shouldCallDidReconnectNotDidConnect() async throws {
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
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    // Establish initial connection.
    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Disconnect — triggers reconnection on task2.
    task1.finish()

    // Reconnect.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Should have: didConnect, didDisconnect, didReconnect (in that order).
    await expect(delegate.events).toEventually(contain(.didReconnect))
    expect(delegate.events.filter { $0 == .didConnect }.count).to(equal(1))
    expect(delegate.events.filter { $0 == .didReconnect }.count).to(equal(1))

    _ = subscription
  }

  func testDelegate__whenDisconnectedWithError__shouldCallDidDisconnectWithError() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Disconnect with an error.
    struct MockDisconnectError: Error {}
    task1.throw(MockDisconnectError())

    do {
      _ = try await subscription.getAllValues()
    } catch {}

    await expect(delegate.events).toEventually(contain(.didDisconnect(hasError: true)))
  }

  func testDelegate__whenDisconnectedCleanly__shouldCallDidDisconnectWithNilError() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Clean disconnect (stream ends without error).
    task1.finish()

    _ = try? await subscription.getAllValues()

    await expect(delegate.events).toEventually(contain(.didDisconnect(hasError: false)))
  }

  func testDelegate__whenPingReceived__shouldCallDidReceivePing() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Server sends a ping without payload.
    task1.emit(.string(#"{"type":"ping"}"#))

    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: false)))

    // Server sends a ping with payload.
    task1.emit(.string(#"{"type":"ping","payload":{"key":"value"}}"#))

    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: true)))

    _ = subscription
  }

  func testDelegate__whenPongReceived__shouldCallDidReceivePong() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Server sends a pong without payload.
    task1.emit(.string(#"{"type":"pong"}"#))

    await expect(delegate.events).toEventually(contain(.didReceivePong(hasPayload: false)))

    // Server sends a pong with payload.
    task1.emit(.string(#"{"type":"pong","payload":{"data":"test"}}"#))

    await expect(delegate.events).toEventually(contain(.didReceivePong(hasPayload: true)))

    _ = subscription
  }

  func testDelegate__fullLifecycle__shouldReceiveEventsInOrder() async throws {
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
    let delegate = MockWebSocketTransportDelegate()
    await transport.setDelegate(delegate)
    let client = ApolloClient(networkTransport: transport, store: store)

    // Connect.
    task1.emit(.string(#"{"type":"connection_ack"}"#))

    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Receive a ping.
    task1.emit(.string(#"{"type":"ping"}"#))
    await expect(delegate.events).toEventually(contain(.didReceivePing(hasPayload: false)))

    // Disconnect.
    task1.finish()

    // Reconnect.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Complete the subscription to let the test finish.
    task2.emit(.string(#"{"type":"complete","id":"\#(operationID)"}"#))
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
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(
        operationMessageIdCreator: ApolloSequencedOperationMessageIdCreator(startAt: 100)
      )
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    task1.emit(.string(#"{"type":"connection_ack"}"#))

    // Start first subscription — should get ID "100".
    let (sub1, id1) = try await subscribe(on: task1, using: client)

    // Start second subscription — should get ID "101".
    let (sub2, id2) = try await subscribe(on: task1, using: client)

    expect(id1).to(equal("100"))
    expect(id2).to(equal("101"))

    _ = (sub1, sub2)
  }

  // MARK: - updateHeaderValues

  func testUpdateHeaderValues__whenReconnectIfConnected__whenConnected__shouldReconnect() async throws {
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

    // Connect on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Update headers with reconnect — should create a new connection on task2.
    await transport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )

    // Task2 should be resumed (new connection started).
    await expect(task2.isResumed).toEventually(beTrue())

    // The reconnection request should contain the updated header.
    let reconnectRequest = factory.capturedRequests.last!
    expect(reconnectRequest.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer token123"))

    // The Sec-WebSocket-Protocol header should be preserved.
    expect(reconnectRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
      .to(equal("graphql-transport-ws"))

    _ = subscription
  }

  func testUpdateHeaderValues__withoutReconnect__whenConnected__shouldNotReconnect() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Connect on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Update headers without reconnect (default).
    await transport.updateHeaderValues(["Authorization": "Bearer token123"])

    // Should still be connected — only 1 task was created (the init task).
    expect(factory.capturedRequests.count).to(equal(1))
    await expect { await transport.connectionState }.to(equal(.connected))

    _ = subscription
  }

  func testUpdateHeaderValues__withReconnect__whenNotConnected__shouldNotReconnect() async throws {
    let task1 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )

    // Transport is in .notStarted state — no connection established.
    await transport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )

    // No reconnection should happen — still only the init task.
    expect(factory.capturedRequests.count).to(equal(1))
  }

  func testUpdateHeaderValues__withNilValue__shouldRemoveHeader() async throws {
    let task1 = MockWebSocketTask()
    let task2 = MockWebSocketTask()
    let task3 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2, task3])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Connect on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Add a header and reconnect to task2.
    await transport.updateHeaderValues(
      ["Authorization": "Bearer token123"],
      reconnectIfConnected: true
    )
    await expect(task2.isResumed).toEventually(beTrue())

    // Verify the header was set.
    let request2 = factory.capturedRequests[1]
    expect(request2.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer token123"))

    // Ack on task2 so we're connected again.
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // Now remove the header by passing nil and reconnect to task3.
    await transport.updateHeaderValues(
      ["Authorization": nil],
      reconnectIfConnected: true
    )
    await expect(task3.isResumed).toEventually(beTrue())

    // Verify the header was removed.
    let request3 = factory.capturedRequests[2]
    expect(request3.value(forHTTPHeaderField: "Authorization")).to(beNil())

    // Protocol header should still be there.
    expect(request3.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))
      .to(equal("graphql-transport-ws"))

    _ = subscription
  }

  func testUpdateHeaderValues__withMultipleHeaders__shouldApplyAll() async throws {
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

    // Connect on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    let (subscription, _) = try await subscribe(on: task1, using: client)

    // Update multiple headers at once.
    await transport.updateHeaderValues([
      "Authorization": "Bearer token123",
      "X-Custom-Header": "custom-value",
    ], reconnectIfConnected: true)

    await expect(task2.isResumed).toEventually(beTrue())

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
    let task3 = MockWebSocketTask()
    let factory = MockWebSocketTaskFactory([task1, task2, task3])

    let session = MockURLSession(responseProvider: Self.self, taskFactory: factory)
    let store = ApolloStore.mock()
    let transport = try WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: Self.endpointURL,
      configuration: .init(reconnectionInterval: 0)
    )
    let client = ApolloClient(networkTransport: transport, store: store)

    // Connect on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    let (subscription, operationID) = try await subscribe(on: task1, using: client)

    // Set a header without reconnecting — just stores it on the request.
    await transport.updateHeaderValues(["Authorization": "Bearer persistent"])

    // Disconnect task1 — triggers auto-reconnection to task2.
    task1.finish()
    task2.emit(.string(#"{"type":"connection_ack"}"#))
    await expect(task2.clientSentMessages(ofType: "subscribe").count).toEventually(equal(1))

    // The auto-reconnection request (task2) should include the previously set header.
    let reconnectRequest = factory.capturedRequests[1]
    expect(reconnectRequest.value(forHTTPHeaderField: "Authorization")).to(equal("Bearer persistent"))

    // Complete the subscription so it doesn't block.
    task2.emit(.string(#"{"type":"complete","id":"\#(operationID)"}"#))
    _ = try await subscription.getAllValues()
  }
}
