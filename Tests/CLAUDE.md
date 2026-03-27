# Tests

## Conventions

- **Test naming**: `test<Feature>__<condition>__<expectedBehavior>` (double underscores separate sections)
- **Assertions**: Use Nimble (`expect`/`to`) over XCTAssert
- **SPI imports**: Test files use `@_spi(Execution)` and `@_spi(Unsafe)` to access internal APIs
- **Cache SPI imports**: Tests using `CacheReference`, `RecordSet`, or other cache internals need `@testable @_spi(Execution) import Apollo` — not just `@testable import Apollo`
- **Sendable**: Mock/test classes use `@unchecked Sendable` when actor isolation isn't practical
- **Test helpers**: Shared mock infrastructure lives in `ApolloInternalTestHelpers/` (separate target from test APIs in `Sources/`)
- **Mock operations**: `MockQuery`, `MockMutation`, `MockSubscription` in `ApolloInternalTestHelpers/MockOperation.swift` — subclass to customize `operationDocument`, `__selections`, etc.
- **Mock selection sets**: Use `MockSelectionSet` (typealias for `AbstractMockSelectionSet<NoFragments, MockSchemaMetadata>`) with `@dynamicMemberLookup` for field access
- **MockWebSocketTask cancel behavior**: `cancel()` calls `serverMessages.finish()` to match real `URLSessionWebSocketTask` — cancelling the task ends the receive stream. This matters for tests involving `pause()` or connection teardown.
- **HTTP subscription testing requires multipart format**: `AsyncHTTPResponseChunkSequence` buffers ALL bytes until stream end for non-multipart responses — transient states (`.active`) are unobservable. Use `Content-Type: multipart/mixed;boundary=graphql;subscriptionSpec=1.0` and format each event as `\r\n--graphql\r\ncontent-type: application/json\r\n\r\n{"payload":{"data":{...}}}\r\n--graphql` for chunk-by-chunk delivery.
- **MockURLProtocol defer bug**: `defer { urlProtocolDidFinishLoading }` fires before catch blocks, so throwing errors on the data stream sends contradictory signals to URLSession. For error testing, use multipart error events (`"errors"` field) instead of stream throws.
- **Mock response helpers**: `MockResponseProvider` supports `MultiResponseHandler` (returns `AsyncThrowingStream<Data, any Error>`) and `SingleResponseHandler`. `HTTPURLResponse.mock(headerFields:)` accepts custom headers. `AsyncStreamMocker<Data>` provides direct stream control for parser-level tests.
- **Avoid `async let` in tests**: `async let` captures `self` (XCTestCase), triggering "Sending 'self' risks causing data races." Use MockWebSocketTask's message queueing (pre-emit before await) or `Task {}` with captured locals instead.

## Generated Test API Files

The `Sources/` directory contains generated GraphQL API targets (AnimalKingdomAPI, StarWarsAPI, GitHubAPI, SubscriptionAPI, UploadAPI) used to verify code generation output.

**NEVER manually edit files in `Sources/*API/` directories.** Always regenerate them by running `./scripts/run-codegen.sh`. This includes "editable" files like `SchemaConfiguration.swift` and custom scalar files — if they need to change due to a template update, delete them first and re-run codegen so they are recreated from the updated template.
