# apollo-ios-pagination

Pagination support library for Apollo iOS, providing cursor-based and offset-based pagination with normalized cache integration.

## Module

Single module: **ApolloPagination** (`Sources/ApolloPagination/`)

## Architecture

### Core Types
- `GraphQLQueryPager<Model>` — Main public API. A Combine `Publisher` that manages paginated GraphQL queries with type-erased output.
- `GraphQLQueryPagerCoordinator` — Internal `actor` managing pagination state, watchers, and page storage. Uses `OrderedDictionary` to preserve page order.
- `GraphQLQueryPagerOutput` — Contains `previousPages`, `initialPage`, and `nextPages` arrays.

### Pagination Strategies
All conform to the `PaginationInfo` protocol (`canLoadNext`, `canLoadPrevious`):

**Cursor-based** (`CursorBasedPagination/`):
- `Forward`, `Reverse`, `Bidirectional`

**Offset-based** (`OffsetBasedPagination/`):
- `Forward`, `Reverse`, `Bidirectional`

### API
- `fetch()` — Load initial page
- `loadNext()` / `loadPrevious()` — Paginate in a direction
- `loadAll()` — Load all remaining pages
- `refetch()` / `reset()` — State management
- Subscribe via Combine publisher for reactive updates

### Error Handling
`PaginationError` enum: `missingInitialPage`, `pageHasNoMoreContent`, `loadInProgress`, `noQuery`, `cancellation`, `unknown`.

## Testing
Tests live in the parent `apollo-ios-dev` repo. Use the `ApolloPaginationTests` scheme with `Apollo-PaginationTestPlan`.

## Dependencies
- `apollo-ios` (Apollo, ApolloAPI) and `swift-collections` (OrderedCollections)

## Platform Support
iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. Swift 6.1 with Swift 5 backward compatibility.
