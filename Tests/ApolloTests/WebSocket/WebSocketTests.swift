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
    
  func testLocalSingleSubscription() async throws {
    let subscription = try client.subscribe(subscription: MockSubscription<ReviewAddedData>())

    let results = try await subscription.getAllValues()

    expect(results.count).to(equal(1))
    expect(results[0].data?.reviewAdded?.stars).to(equal(5))

    let message : JSONEncodableDictionary = [
      "type": "data",
      "id": "1",
      "payload": [
        "data": [
          "reviewAdded": [
            "__typename": "ReviewAdded",
            "episode": "JEDI",
            "stars": 5,
            "commentary": "A great movie"
          ]
        ]
      ]
    ]
        
//    networkTransport.write(message: message)
  }
  #warning("test client side and server side cancellation of subscription")
//
//  func testLocalMissingSubscription() throws {
//    let expectation = self.expectation(description: "Missing subscription")
//    expectation.isInverted = true
//
//    let subject = client.subscribe(subscription: MockSubscription<ReviewAddedData>()) { _ in
//      expectation.fulfill()
//    }
//    
//    waitForExpectations(timeout: 2, handler: nil)
//
//    subject.cancel()
//  }
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
