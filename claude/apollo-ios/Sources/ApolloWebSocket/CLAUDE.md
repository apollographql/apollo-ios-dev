# ApolloWebSocket

## Architecture

`WebSocketTransport` is a Swift `actor` implementing the `graphql-transport-ws` protocol for all operation types (queries, mutations, subscriptions). Supports pause/resume lifecycle for app backgrounding. Key types:

- **`WebSocketTransport`** — Main entry point. Manages connection lifecycle (state machine: `notStarted` → `connecting` → `connected` / `disconnected` / `paused`), subscriber registry, and message routing. `pause()` closes the socket without triggering auto-reconnection or terminating subscriber streams; `resume()` re-establishes and re-subscribes.
- **`WebSocketConnection`** — Wraps a `WebSocketTask`, handles `openConnection()` (returns `AsyncThrowingStream` of messages) and `send()`. `close()` explicitly cancels the underlying task (used by `pause()`), separate from `deinit` cancellation.
- **`WebSocketTask`** protocol — Abstraction over `URLSessionWebSocketTask` for testability. Defined in `WebSocketURLSession.swift`.
- **`Message.Incoming` / `Message.Outgoing`** — Enums in `WebSocketMessage.swift` for all `graphql-transport-ws` message types. Outgoing serializes to `.data` (not `.string`). Incoming deserializes from both `.string` and `.data`.
- **`SubscriberRegistry`** — Manages operation subscribers keyed by `OperationID`. Extracted from `WebSocketTransport`.
- **`ConnectionWaiterQueue`** — Manages `CheckedContinuation`s for callers awaiting connection. Extracted from `WebSocketTransport`.

## Connection Lifecycle

`ensureConnected()` handles all five states:
- `notStarted`: Opens connection, spawns receive loop, waits for `connection_ack`
- `connecting`: Suspends caller via `CheckedContinuation` until ack arrives
- `connected`: Returns immediately
- `disconnected`: Creates fresh `WebSocketConnection` with new task, reconnects
- `paused`: Waits for `connection_ack` (blocks until `resume()` is called)

Connection waiters use `[CheckedContinuation<Void, any Error>]` array pattern (same as `AsyncReadWriteLock`).

## Subscriber Registry

- Lives in `SubscriberRegistry.swift`, keyed by `OperationID` (auto-incrementing `Int`)
- Each subscriber gets an `AsyncThrowingStream<JSONObject, Error>.Continuation` and stores the operation type
- `didReceive(message:)` routes `next` payloads to subscriber by ID, `complete` finishes the stream
- On disconnect: non-subscriptions are terminated **immediately** with the actual error (before reconnection), subscriptions survive for re-subscribe
- Unrecognized/unparseable messages throw `Error.unrecognizedMessage` and terminate all subscribers

## Caching

`WebSocketTransport` integrates with `ApolloStore` for cache reads and writes:

- **`readCacheBeforeNetworkIfNeeded()`** — Evaluates `FetchBehavior.cacheRead`/`.networkFetch` to yield cached data before the WebSocket fetch and decide whether the network fetch should proceed.
- **`parseAndCacheResponse()`** — Parses WebSocket JSON payloads via `SingleResponseExecutionHandler`, writes `RecordSet` to store via `store.publish(records:)` when `requestConfiguration.writeResultsToCache` is true. Cache write errors propagate (terminate the stream).
- **`executeOperation()`** — Unified 3-step flow (cache read → network fetch → cache fallback on failure) used by both queries/mutations and subscriptions. Takes optional `SubscriptionStateStorage` for subscription state tracking.
- **GraphQL errors skip cache fallback** — `onNetworkFailure` cache fallback only triggers for transport/connection errors, not `Error.graphQLErrors` (application-level errors should not be masked by stale cache).
- Uses `store.load()` / `store.publish()` directly — does NOT use `CacheInterceptor` (which is tied to `GraphQLRequest` with HTTP-specific requirements like `graphQLEndpoint` and `toURLRequest()`).

## Ping/Pong

- Application-level JSON messages (separate from WebSocket-frame-level ping/pong)
- On receiving `ping`: reply with `pong(payload: nil)` immediately — do NOT echo the ping's payload
- On receiving `pong`: no action (break)
- Client-initiated pings: `Configuration.pingInterval` (default `nil`/disabled). Timer starts after `connection_ack`, stops on disconnect/pause, restarts on reconnect. Implemented via `pingTimerTask` (`Task`) that captures the current `connection`.

## Testing

Tests live in `Tests/ApolloTests/WebSocket/`. Mock infrastructure in `Tests/ApolloInternalTestHelpers/`:

- **`MockWebSocketTask`** (`MockWebSocketTask.swift`) — Uses `AsyncStreamMocker<URLSessionWebSocketTask.Message>` for server→client messaging. API: `emit()` to send messages, `finish()` to end stream, `throw()` to inject errors. `clientSentMessages` captures outgoing messages for assertions.
- **`MockWebSocketTaskFactory`** (`MockURLSession.swift`) — Vends fresh `MockWebSocketTask` instances sequentially via internal index. `tasks` is a `var` so tests can append additional tasks for reconnection scenarios.
- **`MockURLSession`** (`MockURLSession.swift`) — Conforms to `WebSocketURLSession`. Delegates task creation to a `MockWebSocketTaskFactory`.

### WebSocketTests setup pattern

`setUp()` creates a factory with one default task, a session, transport, and client. Tests access the default task via the `mockTask` computed property. Three patterns:
- **Default config**: Use setUp's transport directly; append extra tasks to `factory.tasks` if reconnection is needed
- **Custom config**: Recreate `factory` (with a fresh `MockWebSocketTaskFactory`) and `session` before creating new `networkTransport` and `client`. The setUp transport consumes factory index 0, so reusing the old session causes the new transport to get the wrong task or crash.
- **`self.` requirement**: `mockTask` is a computed property — use `self.mockTask` inside `expect()` closures. Capture `self.client!` in a local `let` before `Task { }` closures to avoid `sending` parameter data race errors.

### Running WebSocket tests

Use the Xcode MCP `RunSomeTests` tool (see root CLAUDE.md "Tool Preferences"). Target: `ApolloTests`, test identifier: `WebSocketTests`.
