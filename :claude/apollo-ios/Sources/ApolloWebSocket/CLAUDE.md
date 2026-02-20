# ApolloWebSocket

## Architecture

`WebSocketTransport` is a Swift `actor` implementing the `graphql-transport-ws` protocol. Key types:

- **`WebSocketTransport`** — Main entry point. Manages connection lifecycle (state machine: `notStarted` → `connecting` → `connected` / `disconnected`), subscriber registry, and message routing.
- **`WebSocketConnection`** — Wraps a `WebSocketTask`, handles `openConnection()` (returns `AsyncThrowingStream` of messages) and `send()`.
- **`WebSocketTask`** protocol — Abstraction over `URLSessionWebSocketTask` for testability. Defined in `WebSocketURLSession.swift`.
- **`Message.Incoming` / `Message.Outgoing`** — Enums in `WebSocketMessage.swift` for all `graphql-transport-ws` message types. Outgoing serializes to `.data` (not `.string`). Incoming deserializes from both `.string` and `.data`.

## Connection Lifecycle

`ensureConnected()` handles all four states:
- `notStarted`: Opens connection, spawns receive loop, waits for `connection_ack`
- `connecting`: Suspends caller via `CheckedContinuation` until ack arrives
- `connected`: Returns immediately
- `disconnected`: Creates fresh `WebSocketConnection` with new task, reconnects

Connection waiters use `[CheckedContinuation<Void, any Error>]` array pattern (same as `AsyncReadWriteLock`).

## Subscriber Registry

- Keyed by `OperationID` (auto-incrementing `Int`)
- Each subscriber gets an `AsyncThrowingStream<JSONObject, Error>.Continuation`
- `didReceive(message:)` routes `next` payloads to subscriber by ID, `complete` finishes the stream
- On disconnect, all subscribers are finished (with error if connection failed)

## Testing

Tests live in `Tests/ApolloTests/WebSocket/`. Mock infrastructure in `Tests/ApolloInternalTestHelpers/`:

- **`MockWebSocketTask`** — Uses `AsyncStreamMocker<URLSessionWebSocketTask.Message>` for server→client messaging. API: `emit()` to send messages, `finish()` to end stream, `throw()` to inject errors. `clientSentMessages` captures outgoing messages for assertions.
- **`MockWebSocketTaskFactory`** — Vends fresh `MockWebSocketTask` instances sequentially for reconnection tests.
- **`MockURLSession`** — Conforms to `WebSocketURLSession`. Accepts optional factory; defaults to single shared `mockWebSocketTask`.

### Test pattern

```swift
// 1. Buffer server messages before subscribing
mockTask.emit(.string(#"{"type":"connection_ack"}"#))
mockTask.emit(.string(#"{"type":"next","id":"1","payload":{...}}"#))
mockTask.emit(.string(#"{"type":"complete","id":"1"}"#))

// 2. Subscribe and collect results
let sub = try client.subscribe(subscription: MockSubscription<MyData>())
let results = try await sub.getAllValues()

// 3. Assert with Nimble
expect(results.count).to(equal(1))
```

### Running WebSocket tests

```bash
xcodebuild test \
  -workspace ApolloDev.xcworkspace \
  -scheme ApolloTests \
  -testPlan Apollo-UnitTestPlan \
  -destination 'platform=macOS' \
  -only-testing:"ApolloTests/WebSocketTests"
```
