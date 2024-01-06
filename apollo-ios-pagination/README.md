# ApolloPagination

> [!IMPORTANT]
> This library is currently pre-release and in active development. The API is subject to breaking changes until the first stable release.

## `ApolloPagination` is a simple pagination library for iOS that works with Apollo GraphQL queries

It allows you to easily implement pagination in your app by providing a `GraphQLQueryPager` class that you can use to fetch pages of data from your GraphQL API. Additionally, it watches the results of those paginated queries, allowing your cache to remain the source of truth for your data.

## Features

1. Thread-safe
2. Supports different initial and subsequent pagination queries.
3. Supports paginating forwards, backwards, or both.
4. Supports cursor-based pagination and offset-based pagination.
5. Supports custom models as well as the relevant `GraphQLQuery.Data` types.
6. Supports and provides a type erasure.

## Usage

### 1. Create the right `GraphQLQueryPager` for your query

There are several ways of creating a `GraphQLQueryPager` for your query. The simplest way is to use one of the `GraphQLQueryPager.make...` methods, which will create the correct pager based on your needs:

```swift

// Create a pager for a forward-paginated cursor-based query
// Uses the same query for pagination as it does for the initial query
let pager = GraphQLQueryPager.makeForwardCursorQueryPager(
    client: apolloClient,
    queryProvider: { page in
        MyQuery(first: 10, after: page?.cursor ?? .none)
    },
    extractPageInfo: { data in
        CusorBasedPagination.Forward(
            hasNext: data.list.pageInfo?.hasNextPage ?? false,
            endCursor: data.list.pageInfo?.endCursor
        )
    }
)

// Create a pager for a forward-paginated cursor-based query
// Uses different queries for pagination and the initial query
let pager = GraphQLQueryPager.makeForwardCursorQueryPager(
    client: apolloClient,
    initialQuery: MyQuery(first: 10),
    extractInitialPageInfo: { data in
        CusorBasedPagination.Forward(
            hasNext: data.list.pageInfo?.hasNextPage ?? false,
            endCursor: data.list.pageInfo?.endCursor
        )
    },
    extractNextPageInfo: { data in
        CusorBasedPagination.Forward(
            hasNext: data.list.pageInfo?.hasNextPage ?? false,
            endCursor: data.list.pageInfo?.endCursor
        )
    },
    nextPageResolver: { page in
        MyPaginationQuery(first: 10, after: page?.endCursor ?? .none)
    }
)
```

Similarly, there are available convenience methods for reverse pagination as well as bidirectional pagination.

### 2. Subscribe to the pager's results

The pager will automatically update its results as it fetches new pages. You can subscribe to these results by calling `subscribe` on the pager:

```swift
pager.subscribe { result in
    // Handle the result. This closure will be called on the main thread.
}
```

The `subscribe` function manages the subscription for you, and will automatically unsubscribe when the pager is deallocated. If you would like to manage the subscription yourself, you can use the `sink` function:

```swift
pager.sink { result in
    // Handle the result. This closure will be called on the main thread.
}
```

### Fetching pages

There are four primary functions for fetching pages:

1. `loadAll()`: Loads all pages of data. Optionally takes a `fetchFromInitialPage` argument, which defaults to `true`. If `fetchFromInitialPage` is `true`, the pager will discard any state it may have, fetch the initial page of data, and then fetch subsequent pages until there are no more pages to fetch. If `fetchFromInitialPage` is `false`, the pager will only fetch subsequent pages until there are no more pages to fetch. This function is supported in all pagination configurations, whether we are paginating forwards, backwards, or both. This function will remain active until completion.
2. `fetch()`: Fetches the first page of data. When using the pager to fetch individual pages, **this function must be called before calling `fetchNext()` or `fetchPrevious()`**.
3. `refetch()`: Discards pagination state and fetches the first page of data. Optionally takes a `cachePolicy` argument, which defaults to `.fetchIgnoringCacheData`.
4. `fetchNext()`: Fetches the next page of data. This function is only supported when paginating forwards or bidirectionally.
5. `fetchPrevious()`: Fetches the previous page of data. This function is only supported when paginating backwards or bidirectionally.

> [!NOTE]
> The decision to separate `fetch` and `refetch` functions is driven by common design patterns in Apple platform applications. In iOS, for example, a pull-to-refresh operation should remain active until completion, whereas a user-initiated refresh should not. This separation allows you to easily implement these patterns in your app.

### Resetting the pager

You can reset the pager by calling `cancel()` on the pager. This will cancel any in-flight fetches and prevent any subsequent fetches from occurring, as well as reset all pagination state. You can then call `fetch()` to fetch the first page of data again.

### Using your own models via `AnyGraphQLQueryPager`

If you would like to use your own models instead of the `GraphQLQuery.Data` types, you can use the `AnyGraphQLQueryPager` type erasure. This allows you to use your own models with the pager, while still allowing the pager to watch the results of your queries. To use the `AnyGraphQLQueryPager`, you must provide a `GraphQLQueryPager` that uses the same `GraphQLQuery.Data` type as your model. For example:

```swift
let pager = GraphQLQueryPager.makeForwardCursorQueryPager(
    client: apolloClient,
    queryProvider: { page in
        MyQuery(first: 10, after: page?.cursor ?? .none)
    },
    extractPageInfo: { data in
        CusorBasedPagination.Forward(
            hasNext: data.list.pageInfo?.hasNextPage ?? false,
            endCursor: data.list.pageInfo?.endCursor
        )
    }
).eraseToAnyPager(transform: { data in
    // Transform the GraphQLQuery.Data type to your own model
    return data.list.items.map { MyModel(data: $0) }
})
```

## Feedback & Contribution

We welcome any feedback or contributions! Feel free to open an issue or pull request.
