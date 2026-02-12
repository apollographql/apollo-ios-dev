import XCTest
import Nimble
@_spi(Internal) import Apollo
@_spi(Internal) import ApolloAPI
@testable import ApolloWebSocket

class WebSocketMessageSerializationTests: XCTestCase {

  // MARK: - Helpers

  /// Extracts the raw `Data` bytes from a `.data` message.
  private func messageData(
    _ message: URLSessionWebSocketTask.Message
  ) throws -> Data {
    guard case .data(let data) = message else {
      fail("Expected .data message, got .string")
      return Data()
    }
    return data
  }

  /// Deserializes a `.data` WebSocket message into a JSON dictionary.
  private func deserialize(
    _ message: URLSessionWebSocketTask.Message
  ) throws -> [String: Any] {
    let data = try messageData(message)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dict = object as? [String: Any] else {
      fail("Expected JSON dictionary, got \(type(of: object))")
      return [:]
    }
    return dict
  }

  // MARK: - connectionInit

  func test__connectionInit__withNilPayload__shouldSerializeTypeOnly() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .connectionInit(payload: nil)
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("connection_init"))
    expect(json["payload"]).to(beNil())
    expect(json).to(haveCount(1))
  }

  func test__connectionInit__withEmptyPayload__shouldSerializeTypeAndEmptyPayload() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .connectionInit(payload: [:])
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("connection_init"))
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload).to(beEmpty())
  }

  func test__connectionInit__withPayload__shouldSerializeTypeAndPayload() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .connectionInit(payload: ["token": "abc123"])
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("connection_init"))
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["token"] as? String).to(equal("abc123"))
  }

  func test__connectionInit__withNestedPayload__shouldSerializeNestedValues() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .connectionInit(payload: [
        "auth": ["user": "admin", "pass": "secret"] as [String: String]
      ])
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("connection_init"))
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    let auth = try XCTUnwrap(payload["auth"] as? [String: Any])
    expect(auth["user"] as? String).to(equal("admin"))
    expect(auth["pass"] as? String).to(equal("secret"))
  }

  // MARK: - ping

  func test__ping__withNilPayload__shouldSerializeTypeOnly() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .ping(payload: nil)
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("ping"))
    expect(json["payload"]).to(beNil())
    expect(json).to(haveCount(1))
  }

  func test__ping__withPayload__shouldSerializeTypeAndPayload() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .ping(payload: ["seq": 42])
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("ping"))
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["seq"] as? Int).to(equal(42))
  }

  // MARK: - pong

  func test__pong__withNilPayload__shouldSerializeTypeOnly() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .pong(payload: nil)
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("pong"))
    expect(json["payload"]).to(beNil())
    expect(json).to(haveCount(1))
  }

  func test__pong__withPayload__shouldSerializeTypeAndPayload() throws {
    let message = try WebSocketTransport.Message.Outgoing
      .pong(payload: ["seq": 42])
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("pong"))
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["seq"] as? Int).to(equal(42))
  }

  // MARK: - subscribe

  func test__subscribe__withQueryOnly__shouldSerializeMinimalSubscription() throws {
    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: nil,
      query: "subscription { onMessage { text } }",
      variables: nil,
      extensions: nil
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 1, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("subscribe"))
    expect(json["id"] as? String).to(equal("1"))

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["query"] as? String).to(equal("subscription { onMessage { text } }"))
    expect(payload["operationName"]).to(beNil())
    expect(payload["variables"]).to(beNil())
    expect(payload["extensions"]).to(beNil())
  }

  func test__subscribe__withOperationName__shouldIncludeOperationName() throws {
    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: "OnMessage",
      query: "subscription OnMessage { onMessage { text } }",
      variables: nil,
      extensions: nil
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 5, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)

    expect(json["type"] as? String).to(equal("subscribe"))
    expect(json["id"] as? String).to(equal("5"))

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["query"] as? String).to(equal("subscription OnMessage { onMessage { text } }"))
    expect(payload["operationName"] as? String).to(equal("OnMessage"))
  }

  func test__subscribe__withVariables__shouldIncludeSerializedVariables() throws {
    let variables: GraphQLOperation.Variables = [
      "channel": "general",
      "limit": 10,
    ]

    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: "OnMessage",
      query: "subscription OnMessage($channel: String!, $limit: Int) { onMessage(channel: $channel, limit: $limit) { text } }",
      variables: variables,
      extensions: nil
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 3, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    let vars = try XCTUnwrap(payload["variables"] as? [String: Any])
    expect(vars["channel"] as? String).to(equal("general"))
    expect(vars["limit"] as? Int).to(equal(10))
  }

  func test__subscribe__withExtensions__shouldIncludeExtensions() throws {
    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: nil,
      query: "subscription { onMessage { text } }",
      variables: nil,
      extensions: [
        "persistedQuery": [
          "sha256Hash": "abc123",
          "version": 1,
        ] as JSONValue
      ]
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 7, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)

    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    let extensions = try XCTUnwrap(payload["extensions"] as? [String: Any])
    let persistedQuery = try XCTUnwrap(extensions["persistedQuery"] as? [String: Any])
    expect(persistedQuery["sha256Hash"] as? String).to(equal("abc123"))
    expect(persistedQuery["version"] as? Int).to(equal(1))
  }

  func test__subscribe__withAllFields__shouldIncludeAllFields() throws {
    let variables: GraphQLOperation.Variables = [
      "episode": "JEDI",
    ]

    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: "OnReview",
      query: "subscription OnReview($episode: Episode!) { onReview(episode: $episode) { stars commentary } }",
      variables: variables,
      extensions: ["version": 1]
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 42, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)

    // Top-level fields
    expect(json["type"] as? String).to(equal("subscribe"))
    expect(json["id"] as? String).to(equal("42"))

    // Payload fields
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["query"] as? String).to(equal(
      "subscription OnReview($episode: Episode!) { onReview(episode: $episode) { stars commentary } }"
    ))
    expect(payload["operationName"] as? String).to(equal("OnReview"))

    let vars = try XCTUnwrap(payload["variables"] as? [String: Any])
    expect(vars["episode"] as? String).to(equal("JEDI"))

    let extensions = try XCTUnwrap(payload["extensions"] as? [String: Any])
    expect(extensions["version"] as? Int).to(equal(1))
  }

  // MARK: - subscribe (edge cases)

  func test__subscribe__withSpecialCharactersInQuery__shouldEscapeProperly() throws {
    let queryWithSpecialChars = "subscription { onMessage(filter: \"hello\\nworld\") { text } }"

    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: nil,
      query: queryWithSpecialChars,
      variables: nil,
      extensions: nil
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 1, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)
    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
    expect(payload["query"] as? String).to(equal(queryWithSpecialChars))
  }

  func test__subscribe__withLargeOperationId__shouldSerializeCorrectly() throws {
    let subscribePayload = WebSocketTransport.SubscribePayload(
      operationName: nil,
      query: "subscription { onEvent { id } }",
      variables: nil,
      extensions: nil
    )

    let message = try WebSocketTransport.Message.Outgoing
      .subscribe(id: 999999, payload: subscribePayload)
      .toWebSocketMessage()

    let json = try deserialize(message)
    expect(json["id"] as? String).to(equal("999999"))
  }

  // MARK: - Output format

  func test__allMessages__shouldReturnDataFormat() throws {
    let messages: [WebSocketTransport.Message.Outgoing] = [
      .connectionInit(payload: nil),
      .ping(payload: nil),
      .pong(payload: nil),
      .subscribe(
        id: 1,
        payload: WebSocketTransport.SubscribePayload(
          operationName: nil,
          query: "{ __typename }",
          variables: nil,
          extensions: nil
        )
      ),
    ]

    for outgoing in messages {
      let message = try outgoing.toWebSocketMessage()
      guard case .data = message else {
        fail("Expected .data message for \(outgoing), got .string")
        return
      }
    }
  }

  func test__allMessages__shouldProduceValidJSON() throws {
    let messages: [WebSocketTransport.Message.Outgoing] = [
      .connectionInit(payload: ["key": "value"]),
      .ping(payload: ["key": "value"]),
      .pong(payload: ["key": "value"]),
      .subscribe(
        id: 1,
        payload: WebSocketTransport.SubscribePayload(
          operationName: "Op",
          query: "subscription Op { onEvent { id } }",
          variables: ["a": "b"],
          extensions: ["x": "y"]
        )
      ),
    ]

    for outgoing in messages {
      let message = try outgoing.toWebSocketMessage()
      let data = try messageData(message)
      let object = try JSONSerialization.jsonObject(with: data)
      expect(object).to(beAKindOf([String: Any].self))
    }
  }
}
