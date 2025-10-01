---
title: Mutations
---

In addition to fetching data using queries, Apollo iOS also handles GraphQL mutations. Mutations are identical to queries in syntax, the only difference being that you use the keyword `mutation` instead of `query` to indicate that the root fields on this query are going to be performing writes to the backend.

For more information on GraphQL mutations, we recommend [reading this guide](https://graphql.org/learn/queries/#mutations).

GraphQL mutations represent two things in one operation:

1. The mutation field name with arguments, which represents the actual operation to be done on the server.
2. The fields you want back from the result of the mutation to update the client.

All business logic involved in mutating data is handled by the server. The client has no direct knowledge of how data will be mutated. Just like any other field, each mutation in a schema returns a type. If that type is an object type, you may query fields on that type, which can be used to fetch the new state of the mutated object.

In this example, we define a mutation called `UpvotePost`, which performs the schema's `upvotePost(postId:)` mutation.

```graphql
mutation UpvotePost($postId: Int!) {
  upvotePost(postId: $postId) {
    id
    votes
  }
}
```

The server implements the `upvotePost(postId:)` mutation to add an upvote to the post with the given `postId` and return that post. The above mutation selects the `id` and `votes` fields on the returned `Post` object.

The result might be:

```
{
  "data": {
    "upvotePost": {
      "id": "123",
      "votes": 5
    }
  }
}
```

## Performing mutations

Similar to queries, mutations are represented by instances of generated classes, conforming to the `GraphQLMutation` protocol. Operation arguments are generated used to define mutation variables. For more information on passing arguments to a mutation see ["Operation arguments"](./operation-arguments)

You pass a mutation object to `ApolloClient.perform(mutation:)` to send the mutation to the server, execute it, and receive typed results.

```swift
Task {
  do {
    let response = try await apollo.perform(mutation: UpvotePostMutation(postId: postId))
    print(response.data?.upvotePost?.votes)
  } catch {
    print("Error performing mutation: \(error)")
  }
}
```

## Using fragments in mutation results

In many cases, you'll want to use mutation results to update your UI. Fragments can be a great way of sharing result handling between queries and mutations:

```graphql
mutation UpvotePost($postId: Int!) {
  upvotePost(postId: $postId) {
    ...PostDetails
  }
}
```

```swift
Task {
  do {
    let response = try await client.perform(mutation: UpvotePostMutation(postId: postId))
    self.configure(with: response.data?.upvotePost?.fragments.postDetails)
  } catch {
    print("Error performing mutation: \(error)")
  }
}
```

<Note>

Remember to dispatch your UI updates on the `MainActor`! `ApolloClient` will be called `async`, but will return a response to the `async` context where it is called.

</Note>

## Passing input objects

The GraphQL type system includes [input objects](http://graphql.org/learn/schema/#input-types) as a way to pass complex values to fields. Input objects are often defined as mutation variables, because they give you a compact way to pass in objects to be created:

```graphql
mutation CreateReviewForEpisode($episode: Episode!, $review: ReviewInput!) {
  createReview(episode: $episode, review: $review) {
    stars
    commentary
  }
}
```

```swift
let review = ReviewInput(stars: 5, commentary: "This is a great movie!")
Task {
  do {
    let response = try await apollo.perform(mutation: CreateReviewForEpisodeMutation(episode: .jedi, review: review))
    // Handle response as needed
  } catch {
    print("Error creating review: \(error)")
  }
}
```
