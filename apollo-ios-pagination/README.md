<p align="center">
  <img src="https://raw.githubusercontent.com/apollographql/apollo-client-devtools/main/assets/apollo-wordmark.svg" alt="Apollo GraphQL"/>
</p>

<p align="center">
  <a href="https://github.com/apollographql/apollo-ios-dev/actions/workflows/ci-tests.yml">
    <img src="https://github.com/apollographql/apollo-ios-dev/actions/workflows/ci-tests.yml/badge.svg?branch=main" alt="GitHub Action Status">
  </a>
  <a href="https://raw.githubusercontent.com/apollographql/apollo-ios-pagination/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg?maxAge=2592000" alt="MIT license">
  </a>
    <a href="Platforms">
    <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-333333.svg" alt="Supported Platforms: iOS, macOS, tvOS, watchOS" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/apple/swift">
    <img src="https://img.shields.io/badge/Swift-5.7-orange.svg" alt="Swift 5.7 supported">
  </a>
  <a href="https://swift.org/package-manager/">
    <img src="https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square" alt="Swift Package Manager compatible">
  </a>
</p>

> [!IMPORTANT]
> This library is currently released as a 0.x version and is in active development. The API is subject to breaking changes until the stable 1.0 release.

| ☑️  Apollo Clients User Survey |
| :----- |
| What do you like best about Apollo iOS? What needs to be improved? Please tell us by taking a [one-minute survey](https://docs.google.com/forms/d/e/1FAIpQLSczNDXfJne3ZUOXjk9Ursm9JYvhTh1_nFTDfdq3XBAFWCzplQ/viewform?usp=pp_url&entry.1170701325=Apollo+iOS&entry.204965213=Readme). Your responses will help us understand Apollo iOS usage and allow us to serve you better. |

### Apollo iOS Pagination

This repo provides an API way to handle paginated queries for Apollo iOS.

`ApolloPagination` uses an `ApolloClient` to fetch and cache your paginated query data. It supports:

- Reading/Writing paginated data with an Apollo `NormalizedCache`
- Watching paginated data for changes
- Forward, Reverse, and Bi-directional pagination
- Cursor-based, offset-based, and custom pagination mechanisms  

## Issues

To report an issue, bug, or feature request you can do so in the [apollo-ios](https://github.com/apollographql/apollo-ios/issues) repo.

## Roadmap

The [roadmap](https://github.com/apollographql/apollo-ios/blob/main/ROADMAP.md) is a high-level document that describes the next major steps or milestones for this project. We are always open to feature requests, and contributions from the community.

## Contributing

If you'd like to contribute, please refer to the [Apollo Contributor Guide](https://github.com/apollographql/apollo-ios-dev/blob/main/CONTRIBUTING.md).

## Maintainers

- [@AnthonyMDev](https://github.com/AnthonyMDev)
- [@calvincestari](https://github.com/calvincestari)
- [@bignimbus](https://github.com/bignimbus)
- [@bobafetters](https://github.com/bobafetters)
- [@Iron-Ham](https://github.com/Iron-Ham)

## Who is Apollo?

[Apollo](https://apollographql.com/) builds open-source software and a graph platform to unify GraphQL across your apps and services. We help you ship faster with:

- [Apollo Studio](https://www.apollographql.com/studio/develop/) – A free, end-to-end platform for managing your GraphQL lifecycle. Track your GraphQL schemas in a hosted registry to create a source of truth for everything in your graph. Studio provides an IDE (Apollo Explorer) so you can explore data, collaborate on queries, observe usage, and safely make schema changes.
- [Apollo Federation](https://www.apollographql.com/apollo-federation) – The industry-standard open architecture for building a distributed graph. Use Apollo’s gateway to compose a unified graph from multiple subgraphs, determine a query plan, and route requests across your services.
- [Apollo Client](https://www.apollographql.com/apollo-client/) – The most popular GraphQL client for the web. Apollo also builds and maintains [Apollo iOS](https://github.com/apollographql/apollo-ios) and [Apollo Kotlin](https://github.com/apollographql/apollo-kotlin).
- [Apollo Server](https://www.apollographql.com/docs/apollo-server/) – A production-ready JavaScript GraphQL server that connects to any microservice, API, or database. Compatible with all popular JavaScript frameworks and deployable in serverless environments.

## Learn how to build with Apollo

Check out the [Odyssey](https://odyssey.apollographql.com/) learning platform, the perfect place to start your GraphQL journey with videos and interactive code challenges. Join the [Apollo Community](https://community.apollographql.com/) to interact with and get technical help from the GraphQL community.
