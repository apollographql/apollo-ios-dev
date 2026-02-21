# apollo-ios

Core Apollo iOS SDK providing networking, caching, and the client API for GraphQL operations.

## Modules

- **Apollo** (`Sources/Apollo/`) — Core networking, caching, and client. Main public API is `ApolloClient`.
- **ApolloAPI** (`Sources/ApolloAPI/`) — Protocols and types that generated code conforms to (SelectionSet, DataDict, GraphQLOperation, etc.).
- **ApolloSQLite** (`Sources/ApolloSQLite/`) — SQLite-backed normalized cache implementation.
- **ApolloWebSocket** (`Sources/ApolloWebSocket/`) — WebSocket transport for subscriptions using `graphql-transport-ws` protocol.
- **ApolloTestSupport** (`Sources/ApolloTestSupport/`) — Public test utilities and mock helpers.

## Architecture

### Request Chain (Interceptor Pattern)
The networking layer uses a chain-of-responsibility pattern in `Sources/Apollo/RequestChain/`:
- `RequestChainNetworkTransport` creates a `RequestChain` for each operation
- Four interceptor types: `GraphQLInterceptor` (pre/post-flight on GraphQLRequest/Response), `HTTPInterceptor` (pre/post-flight on URLRequest/HTTPResponse), `CacheInterceptor` (cache reads/writes), `ResponseParsingInterceptor` (parses HTTPResponse chunks into GraphQLResponse)
- Custom interceptors implement the appropriate protocol; `InterceptorProvider` supplies them to the chain
- `DefaultInterceptorProvider` provides: `MaxRetryInterceptor`, `AutomaticPersistedQueryInterceptor` (GraphQL), `ResponseCodeInterceptor` (HTTP), `DefaultCacheInterceptor` (cache), `JSONResponseParsingInterceptor` (parser)

### Normalized Cache
Cache system in `Sources/Apollo/Caching/`:
- `ApolloStore` provides type-safe read/write access
- `NormalizedCache` protocol with `InMemoryNormalizedCache` (default) and `SQLiteNormalizedCache` implementations
- Records stored by cache key; enables efficient updates and watching

### Response Parsing
`Sources/Apollo/ResponseParsing/` handles JSON, multipart, incremental (deferred), and subscription responses.

### Generated Code Integration
`ApolloAPI` defines the protocols (`SelectionSet`, `GraphQLOperation`, etc.) that codegen-produced types conform to. `DataDict` provides type-safe access to response data.

## Key Entry Points
- `Sources/Apollo/ApolloClient.swift` — Main public API
- `Sources/Apollo/RequestChain/RequestChainNetworkTransport.swift` — Request execution
- `Sources/Apollo/Caching/ApolloStore.swift` — Cache management
- `Sources/ApolloAPI/SelectionSet.swift` — Core protocol for generated code

## Testing
Tests live in the parent `apollo-ios-dev` repo under `Tests/`. Use the `ApolloTests` scheme with `Apollo-UnitTestPlan`.

## Platform Support
iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. Swift 6.1 with Swift 5 backward compatibility.
