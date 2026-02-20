# Tests

## Conventions

- **Test naming**: `test<Feature>__<condition>__<expectedBehavior>` (double underscores separate sections)
- **Assertions**: Use Nimble (`expect`/`to`) over XCTAssert
- **SPI imports**: Test files use `@_spi(Execution)` and `@_spi(Unsafe)` to access internal APIs
- **Sendable**: Mock/test classes use `@unchecked Sendable` when actor isolation isn't practical
- **Test helpers**: Shared mock infrastructure lives in `ApolloInternalTestHelpers/` (separate target from test APIs in `Sources/`)
- **Mock operations**: `MockQuery`, `MockMutation`, `MockSubscription` in `ApolloInternalTestHelpers/MockOperation.swift` — subclass to customize `operationDocument`, `__selections`, etc.
- **Mock selection sets**: Use `MockSelectionSet` (typealias for `AbstractMockSelectionSet<NoFragments, MockSchemaMetadata>`) with `@dynamicMemberLookup` for field access
