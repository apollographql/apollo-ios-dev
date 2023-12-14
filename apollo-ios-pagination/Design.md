# Design Principles and Goals

Apollo 1 made many changes to generated code, as well as how cache results are stored. Notably, in Apollo 1.x, cache results are not mutable by default unless a local cache mutation is declared to modify them. This means that the most common strategy for handling pagination in Apollo 0.x is no longer viable: manually appending the results of a new page to the existing cache results. [Our first attempt](https://github.com/apollographql/apollo-ios-pagination/blob/20130d6b01d52a6de3a233b5113055b9215a2b24/Sources/apollo-ios-pagination/GraphQLPaginatedQueryWatcher.swift) at creating a new pagination strategy was to create a set of classes that aimed to handle pagination in a very _clever_ fashion, by trying to internalize as much of the behavior as possible. However, this proved complex to instantiate, error-prone, and confusing.

Afterwards, we decided to try a different approach, and create a new class that would handle pagination in a more straightforward manner. This class would be responsible for handling the logic of fetching new pages, and would expose simple APIs that would allow the caller to interact with the pager in a more straightforward manner. This approach proved to be much more successful, and we were able to implement a new pagination strategy that was much more straightforward to use, and much more robust.

We wanted to ensure that the new pagination API would be as easy to use as possible, and that it met the following goals:

1. The `GraphQLQueryPager` can be used with offset-based pagination as well as cursor-based pagination.
2. The `GraphQLQueryPager` would have to be made thread-safe, as it could be called by and used by many subscribers at once.
3. The `GraphQLQueryPager` would need to be cancellable.
4. The `GraphQLQueryPager` would need to be flexible, and support users paginating in both directions as well as support for different queries for paginating information vs. fetching the initial page.
5. The `GraphQLQueryPager` would need to fit into existing application architectures, and be able to be used with existing code. That means that it would need to have a familiar API.

We found that achieving these design goals was not easy, and required a number of iterations. We initially started with a simple API that was neither thread-safe, nor made use of Swift concurrency. However, as we kept iterating, we found that we needed some way of achieving thread-safety. We explored two paths:

1. By making use of semaphores, operation queues, mutexes, locks, and related APIs.
2. By making use of Swift Concurrency APIs and Swift `actor`s.

We decided that we would use Swift Concurrency and `actor`, as it prevented us from having to manually manage locks, semaphores, and other concurrency primitives. The `actor` API has the added benefit of being able to protect properties from concurrent access, as well as serialize calls to the `actor`'s message queue. This meant that we could ensure that calls to the `GraphQLQueryPager` would be serialized, and that we would not have to worry about concurrent access to the `GraphQLQueryPager`'s properties. Using an `actor` forces the usage of Swift concurrency, as calls to an `actor` must be made from within an asynchronous context. This means that we would have to use `Task`s to interface with the `GraphQLQueryPager`. We decided to namespace the `actor` as `GraphQLQueryPager.Actor`, and expose a `GraphQLQueryPager` class that would be responsible for interfacing with the `Actor`.

Using Swift Concurrency, it allowed us to think about the behavior of a fetch operation. We decided that the `GraphQLQueryPager` would have to suspend execution during a `fetch`, whether we are fetching the next page, the previous page, or the initial page. Concretely, we must leave the caller "waiting" for a response from the `GraphQLQueryPager` when a `fetch` is in progress. Additionally, the `GraphQLQueryPager` may not start another `fetch` until the previous `fetch` has completed. Under the hood, since the `GraphQLQueryPager` is using a `GraphQLQueryWatcher` to fetch pages, we would need to bridge the gap between the `GraphQLQueryPager` and the `GraphQLQueryWatcher` callback. That proved challenging, but we ultimately found that we could use the `withCheckedContinuation` API to bridge the gap between the `GraphQLQueryPager` and the `GraphQLQueryWatcher` callback with some additional logic.

## Details

As the `GraphQLQueryPager.Actor` is an `actor`, that means two things:

1. It operates its own message queue, meaning that calls to the pager are serialized and executed in order.
2. It protects its properties from concurrent access.

This is especially useful when we consider that we want to ensure that there are no parallel `fetch` operations occuring, and that we can check that this is the case without storage of `Task`s or information about in-flight operations. Rather, we can simply store a boolean value indicating whether or not we are actively fetching.

> [!NOTE]
> **Why is it important that there are no parallel fetches?**
> Fetching pages in parallel can lead to a number of issues. For example, if we are fetching both the next and previous page at the same time, we may end up in a situation where we have rapid back-to-back updates of our data, triggering UI refresh. Additionally, it complicates the logic of how we should update our users, the logic of how we should handle errors, and more.

That does mean that we need to use a continuation of some sort in order to await the completion of the `GraphQLQueryWatcher` callback. This is where the `withCheckedContinuation` API comes in handy. We can use this API to `await` the result of the `GraphQLQueryWatcher` callback, and then resume execution once the callback has been called. This was a source of frustration early on, for the following reasons:

- A `Continuation` must be resumed exactly once. Failing to resume a `Continuation` will result in a thread that is forever blocked. Resuming it too many times will result in a runtime error.
- The `GraphQLQueryWatcher` callback is called many times: it's called twice for fetch requests with a `returnCacheDataAndFetch` policy, and once more for every cache update. This means we need to determine the "canonical load" of a `GraphQLQueryWatcher` callback, and only resume the `Continuation` once that canonical load has been called.

> [!NOTE]
> **What is a Continuation?**
> A continuation is the tool that Swift provides us with in order to bridge callback-based APIs into the world of `async`/`await`. There are two types of continuations: checked and unchecked. A checked continuation is a continuation that is checked at runtime to ensure that it is resumed exactly once. An unchecked continuation is a continuation that is not checked at runtime. The checking introduces a slight overhead, but allows us to detect and prevent bugs that would otherwise occur silently in an unchecked continuation. For more information, see the documentation on [CheckedContinuation](https://developer.apple.com/documentation/swift/checkedcontinuation).

Let's take a look at the convenience function that we use to execute queries and await their results and break down how it works:

```swift
private func execute(operation: @escaping (CurrentValueSubject<Void, Never>) async throws -> Void) async {
  // 1
  await withCheckedContinuation { continuation in
    // 2
    Task {
      // 3
      let fetchContainer = FetchContainer()
      let publisher = CurrentValueSubject<Void, Never>(())
      let subscriber = publisher.sink(receiveCompletion: { _ in
        Task { await fetchContainer.cancel() }
      }, receiveValue: { })
      // 4
      await fetchContainer.setValues(subscriber: subscriber, continuation: continuation)
      // 5
      try await withTaskCancellationHandler {
        // 6
        try Task.checkCancellation()
        try await operation(publisher)
      } onCancel: {
        // 7
        Task { await fetchContainer.cancel() }
      }
    }
  }
}
```

This function:

1. Creates a `Continuation` that we can use to `await` the result of the `GraphQLQueryWatcher` callback.
2. Creates a `Task` that will execute the `operation` closure. This is necessary, as `withCheckedContinuation` provides us a synchronous context. Note that this is also the source of `@escaping` in the `operation` closure. Technically speaking, this closure is not escaping -- as it will finish execution prior the `withCheckedContinuation` block finishing execution -- but we need to mark it as escaping as the compiler cannot determine this.
3. Creates a `FetchContainer` that will be used to store the `Continuation` and Combine subscriber, that we will use to resume the `Continuation` once the `GraphQLQueryWatcher` callback has been called. Note the use of `Combine` here is necessary, as we need to be able to suspend this continuation until we've determined the "canonical load". We are defining the "canonical load" as the `GraphQLQueryWatcher` response that allows us to resume the continuation. For most `CachePolicy` types, this it the first response -- but for `returnCacheDataAndFetch`, that is the network-response. The `CurrentValueSubject` -- which is a `Publisher` -- allows us to do this by virtue of its completion handler. A `Publisher`'s completion handler is guaranteed to only respond to being called once, and will prevent the publisher from emitting any more values once it has been called.
4. Sets the `FetchContainer`'s values, which will be used to resume the `Continuation` once the `GraphQLQueryWatcher` callback has been called.
5. Creates a `Task` with a cancellation handler. This cancellation handler will be called if the `Task` is cancelled, and will be used to cancel the `FetchContainer`. This is necessary to support Apollo's transition into Swift concurrency.
6. We manually check for cancellation, as the `Task` will continue execution unless we check for cancellation. Note that in the event of cancellation, the `Task`'s cancellation handler will run concurrently with the operation if we do not manually check for cancellation. This is part of the reason why it's important that the `FetchContainer` is also an `actor`, as it will protect its properties from concurrent access.
7. Cancels the `FetchContainer` if the `Task` is cancelled.

This function is used within the `fetch` and `paginationFetch` functions, and is what allows us to suspend execution until the `GraphQLQueryWatcher` callback has been called. This is also what allows us to ensure that we only resume the `Continuation` once the canonical load has been called.

### Bridging to synchronous APIs

The `GraphQLQueryPager.Actor` is an `actor`, and so all calls to the pager must be made from within an asynchronous context. However, our existing application is by and large synchronous. This means that we need to bridge the gap between the synchronous and asynchronous worlds. To that end, we have made the `GraphQLQueryPager` a class that is responsible for that bridging. It does so by wrapping the asynchronous calls in `Task<_, Never>`. In order to respond to thrown errors, we allow for a callback that exposes an optional `Error`, if there is one. Allowing for this callback also allows us to execute code after the asynchronous call has completed.

> [!NOTE]
>
> #### Why use `Task<_, Never>`?
> There is a notable difference between the behavior of `Task` and `Task<_, Never>`, even though they may look identical! Let's take a look at the following example:
>
> ```swift
> func foo() throws {
>   Task { throw SomeError() }
> }
> ```
>
> This function will throw  an error within the task, but that throw will never be caught by the caller; the `Task` will swallow this error.
>
> A nearly identical function that uses `Task<_, Never>` will behave differently, as it will prevent you from calling the function without handling the error:
>
> ```swift
> func foo() throws {
>   Task<_, Never> {
>     try { throw SomeError() }
>     catch { handle(error: error) }
>   }
> }
> ```
>
> Since the `Task`'s error property is generic over `Never`, the compiler will enforce that you handle the error. This is the behavior that we want, as otherwise we would never be notified of errors thrown within the task.

### Allowing for type erasures

The `GraphQLQueryPager` is a generic type, and so we need to be able to erase its type in order to use it without regard for the underlying query. As we may use multiple queries that resolve to the same model, this is necessary. To that end, we have created a `AnyGraphQLQueryPager` type that wraps the `GraphQLQueryPager` and exposes the same API, but with an erased type.

### Usage of `Combine`

We use `Combine` across these classes for various reasons.

#### Within `GraphQLQueryPager.Actor`

1. We use `Combine` in the `subscribe` function, which allows callers to subscribe to the `GraphQLQueryPager`'s output. This is necessary, as we need to be able to support multiple subscribers on the same `GraphQLQueryPager` output. This is not possible with the existing Swift concurrency APIs, as they do not allow for multiple subscribers on the same `AsyncStream` or `AsyncSequence`.
2. We use `Combine` within the `execute` function in order to suspend the `Continuation` until the `GraphQLQueryWatcher` callback has been called for the canonical load. This is due to the fact that the `GraphQLQueryWatcher`'s callback can be triggered many times, but we only care to suspend continuation during a fetch from the network.
3. We annotate several properties of the `GraphQLQueryPager.Actor` with `@Published`. This allows us to subscribe to changes on these properties and respond to them, without having to initiate a new asynchronous context to access these properties.

#### Within `GraphQLQueryPager`

1. We use `Combine` in the initializer to listen to changes on the `GraphQLQueryWatcher`'s `publishers` property, which allows us to respond to changes on the `GraphQLQueryWatcher`'s internal variables. Note that we don't care about the values emitted by the `GraphQLQueryWatcher`'s `publishers` property, only that it has changed. This is due to the fact that these properties only change as a result of a fetch from the network or cache change, which may impact whether or not we can load more data. We listen to these properties for the sole purpose of setting the `canLoadNext` and `canLoadPrevious` properties, which are computed properties of the `Actor`.

#### Within `AnyGraphQLQueryPager`

1. We declare a `_subject` property that allows us to apply a model transform across the outputs of the `GraphQLQueryPager`. This is necessary, as we may use multiple queries that resolve to the same model, and so we need to be able to erase the type of the `GraphQLQueryPager` and apply a transform to the output. This `_subject` emits the values being subscribed to by the `AnyGraphQLQueryPager`'s subscribers.

## Consequences

The `GraphQLQueryPager` is a powerful tool that allows us to paginate through a GraphQL query. It is also a powerful tool that allows us to bridge the gap between the synchronous and asynchronous worlds. However, it is not without its drawbacks. The `GraphQLQueryPager` is a complex type, and it is not immediately obvious how it works. This is especially true when we consider that it is an `actor`, and so all calls to it must be made from within an asynchronous context -- including calls to constant properties or functions that do not mutate state.

Using an `actor` is not without its added complexity. Because the `actor` operates in an isolated context, any `Task` outside of that context cannot access or modify the `actor`'s properties. If we are to use a `Task` outside of the `actor`'s context, we must ensure that the `actor` makes the modification or that the the modification is made from within the `actor`'s context. The compiler will prevent us from doing otherwise, but we must be aware of this limitation. This leads to declaring specific functions which set or modify the values of an `actor`'s properties.

A further consequence is that the team must learn about Swift Concurrency concepts in order to understand how the `GraphQLQueryPager.Actor` works. By and large, we've avoided having to do so as our application doesn't make use of Swift's concurrency model or APIs. However, as Apple further takes the platform and language in the direction of Swift concurrency, we will need to learn about these concepts as time marches on. Perhaps this may be the start of that journey, and the point where we begin using small `actor` types to solve problems that we may not have been able to easily solve otherwise.

## Alternatives Considered

We considered not using Combine APIs, but quickly discovered that we could not as easily bridge async/await APIs to a synchronous context, and that we additionally could not have mutliple subscribers across the same subscribable output. This is a common point of contention with the current implementation of Swift concurrency, and one that Apple is aware of. An official solution to this problem is in the works, and would be backwards compatible with previous versions of Swift, but it is not yet available. Once it becomes available, we can consider migrating to it.

We considered using existing Foundation and Dispatch APIs, but shied away from the complexity of managing locks, mutexes, operation queues, dispatch queues, and the like. The `actor` provides many of the behaviors that we'd want out of of the box, whereas we with `Foundation` and `Dispatch` APIs, we'd have to implement them ourselves. Specifically, `actor`s provide us with a way to ensure that we are not accessing or modifying state from outside of the `actor`'s context, and that we are not accessing or modifying state from multiple threads. That inherently makes the `actor` thread-safe, which is a huge win for us. An `actor` provides us with a way to suspend a `Task` until a value is available, which is something that we'd have to implement ourselves with `Foundation` and `Dispatch` APIs. And finally, we have to consider the environment that we work in and the direction of our dependencies. Apollo is moving towards Swift concurrency for its networking stack, and so we will need the pager to be thread-safe and to be able to respond-to or initiate `Task` cancellations from within the `GraphQLQueryPager` in order to halt ongoing network requests.

We considered not being thread-safe, but found that to be a quick way to crash an application in SwiftUI. Many of the new SwiftUI APIs open up an `async` context such as `refreshable` and `task`. Apple also [recommends leaning into Swift concurrency when using SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10019), with their example code making heavy use of `async/await`, `Task`, and `actor` types.

## Recommended Reading and WWDC Talks

Reading:

- [Swift Concurrency Manifesto](https://gist.github.com/lattner/31ed37682ef1576b16bca1432ea9f782)
- [Swift Concurrency Roadmap](https://forums.swift.org/t/swift-concurrency-roadmap/41611)
- [Swift Evolution: Async/Await](https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md)
- [Swift Evolution: Continuations for interfacing async tasks with synchronous code](https://github.com/apple/swift-evolution/blob/main/proposals/0300-continuation.md)
- [Swift Evolution: Effectful Read-only Properties](https://github.com/apple/swift-evolution/blob/main/proposals/0310-effectful-readonly-properties.md)

WWDC Talks:

- [WWDC 2021: Meet async/await in Swift](https://developer.apple.com/videos/play/wwdc2021/10132/)
- [WWDC 2021: Explore Structured concurrency in Swift](https://developer.apple.com/videos/play/wwdc2021/10134)
- [WWDC 2021: Meet AsyncSequence](https://developer.apple.com/videos/play/wwdc2021/10058)
- [WWDC 2021: Protect mutable state with Swift actors](https://developer.apple.com/videos/play/wwdc2021/10133)
- [WWDC 2021: Swift Concurrency: Behind the Scenes](https://developer.apple.com/videos/play/wwdc2021/10254)
- [WWDC 2021: Swift Concurrency: Update a sample app](https://developer.apple.com/videos/play/wwdc2021/10194)
- [WWDC 2022: Efficiency Awaits: Backgronds Tasks in SwiftUI](https://developer.apple.com/videos/play/wwdc2022/10142)
- [WWDC 2022: Eliminate Data Races Using Swift Concurrency](https://developer.apple.com/videos/play/wwdc2022/110351)
- [WWDC 2021: Discover Concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10019)
- [WWDC 2022: Visualize and Optimize Swift Concurrency](https://developer.apple.com/videos/play/wwdc2022/110350)
- [WWDC 2023: Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170)
