import XCTest
import Nimble
@testable import Apollo
@_spi(Execution) @_spi(Unsafe) import ApolloAPI
@_spi(Execution) import ApolloInternalTestHelpers
@testable import ApolloWebSocket

#warning("Rewrite when websocket is implemented")
//extension WebSocketTransport {
//  func write(message: JSONEncodableDictionary) {
//    let serialized = try! JSONSerializationFormat.serialize(value: message)
//    if let str = String(data: serialized, encoding: .utf8) {
//      self.websocket.write(string: str)
//    }
//  }
//}

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

    // Emit data for both subscriptions (IDs 1 and 2 since they're registered sequentially).
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
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("First"))
    expect(results2.count).to(equal(1))
    expect(results2[0].data?.reviewAdded?.commentary).to(equal("Second"))
  }

  // MARK: - Second Subscription (connected state)

  func testSecondSubscription__whenAlreadyConnected__shouldNotReconnect() async throws {
    let mockTask = session.mockWebSocketTask

    // Start the first subscription and get through the connection handshake.
    mockTask.emit(.string(#"{"type":"connection_ack"}"#))

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    // Give the connection loop time to process connection_ack.
    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

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
    let connectionInits = mockTask.clientSentMessages.filter { message in
      if case .data(let data) = message,
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         json["type"] as? String == "connection_init" {
        return true
      }
      return false
    }
    expect(connectionInits.count).to(equal(1))
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

    // First subscription on task1.
    task1.emit(.string(#"{"type":"connection_ack"}"#))
    task1.emit(.string(
      #"{"type":"next","id":"1","payload":{"data":{"reviewAdded":{"__typename":"ReviewAdded","stars":5,"commentary":"First connection"}}}}"#
    ))
    task1.emit(.string(#"{"type":"complete","id":"1"}"#))

    let sub1 = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())
    let results1 = try await sub1.getAllValues()

    expect(results1.count).to(equal(1))
    expect(results1[0].data?.reviewAdded?.commentary).to(equal("First connection"))

    // Disconnect: finish task1's stream to simulate server closing the connection.
    task1.finish()

    // Give the receive loop time to process the disconnection.
    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

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

  #warning("test client side and server side cancellation of subscription")
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
