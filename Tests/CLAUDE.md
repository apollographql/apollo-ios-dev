# Tests

## Conventions

- **Test naming**: `test<Feature>__<condition>__<expectedBehavior>` (double underscores separate sections)
- **Assertions**: Use Nimble (`expect`/`to`) over XCTAssert
- **SPI imports**: Test files use `@_spi(Execution)` and `@_spi(Unsafe)` to access internal APIs
- **Sendable**: Mock/test classes use `@unchecked Sendable` when actor isolation isn't practical
- **Test helpers**: Shared mock infrastructure lives in `ApolloInternalTestHelpers/` (separate target from test APIs in `Sources/`)
- **Mock operations**: `MockQuery`, `MockMutation`, `MockSubscription` in `ApolloInternalTestHelpers/MockOperation.swift` — subclass to customize `operationDocument`, `__selections`, etc.
- **Mock selection sets**: Use `MockSelectionSet` (typealias for `AbstractMockSelectionSet<NoFragments, MockSchemaMetadata>`) with `@dynamicMemberLookup` for field access
- **MockWebSocketTask cancel behavior**: `cancel()` calls `serverMessages.finish()` to match real `URLSessionWebSocketTask` — cancelling the task ends the receive stream. This matters for tests involving `pause()` or connection teardown.
- **HTTP subscription testing requires multipart format**: `AsyncHTTPResponseChunkSequence` buffers ALL bytes until stream end for non-multipart responses — transient states (`.active`) are unobservable. Use `Content-Type: multipart/mixed;boundary=graphql;subscriptionSpec=1.0` and format each event as `\r\n--graphql\r\ncontent-type: application/json\r\n\r\n{"payload":{"data":{...}}}\r\n--graphql` for chunk-by-chunk delivery.
- **MockURLProtocol defer bug**: `defer { urlProtocolDidFinishLoading }` fires before catch blocks, so throwing errors on the data stream sends contradictory signals to URLSession. For error testing, use multipart error events (`"errors"` field) instead of stream throws.
- **Mock response helpers**: `MockResponseProvider` supports `MultiResponseHandler` (returns `AsyncThrowingStream<Data, any Error>`) and `SingleResponseHandler`. `HTTPURLResponse.mock(headerFields:)` accepts custom headers. `AsyncStreamMocker<Data>` provides direct stream control for parser-level tests.
