<p align="center">
  <img src="https://user-images.githubusercontent.com/146856/124335690-fc7ecd80-db4f-11eb-93fa-dcf4469bb07b.png" alt="Apollo GraphQL"/>
</p>

<p align="center">
  <a href="https://github.com/apollographql/apollo-ios-dev/actions/workflows/ci-tests.yml">
    <img src="https://github.com/apollographql/apollo-ios-dev/actions/workflows/ci-tests.yml/badge.svg?branch=main" alt="GitHub Action Status">
  </a>
  <a href="https://raw.githubusercontent.com/apollographql/apollo-ios/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg?maxAge=2592000" alt="MIT license">
  </a>
  <a href="https://github.com/apple/swift">
    <img src="https://img.shields.io/badge/Swift-5.7-orange.svg" alt="Swift 5.7 supported">
  </a>
</p>

| ☑️  Apollo Clients User Survey |
| :----- |
| What do you like best about Apollo iOS? What needs to be improved? Please tell us by taking a [one-minute survey](https://docs.google.com/forms/d/e/1FAIpQLSczNDXfJne3ZUOXjk9Ursm9JYvhTh1_nFTDfdq3XBAFWCzplQ/viewform?usp=pp_url&entry.1170701325=Apollo+iOS&entry.204965213=Readme). Your responses will help us understand Apollo iOS usage and allow us to serve you better. |

### Apollo iOS Dev

This repo contains the development environment for working on and contributing to the Apollo iOS ecosystem. This repo uses a git subtree setup to include the following repos for development:

- [apollo-ios](https://github.com/apollographql/apollo-ios)
- [apollo-ios-codegen](https://github.com/apollographql/apollo-ios-codegen)

All code changes are pushed out to their respective repos whenever a PR is merged. This allows us to provide a cohesive development environment while also providing packages to users that contain less overall files and dependencies, such as things only really used for development and testing.

## Getting Started

To get started contributing to Apollo iOS, the first step you need to take is to fork this (apollo-ios-dev) repo. Once you have forked and cloned the repo the next step is to generate the Xcode Workspace that you will use for development.

### Tuist

This project uses [Tuist](https://tuist.io/) to handle generation of the Xcode workspace for development. In order to use Tuist run the following command in terminal to ensure you have it installed:

```
curl -Ls https://install.tuist.io | bash
```

In order to generate the project/workspace you will need to run the [tuist generate](https://docs.tuist.io/commands/generate) command from the project root.

There is also a githook setup to auto-run `tuist generate` whenever a branch is checked out, in order for git to find and use the hook run the following make command to ensure the git config is pointing to the correct location:

```
make repo-setup
```

> Note: This will update the local git config in your checkout of the repo by running the following command: `git config core.hooksPath .githooks`

A [Get started](https://docs.tuist.io/tutorial/get-started) guide for Tuist along with [other documentation](https://tuist.github.io/tuist/main/documentation/projectdescription/project) is also available for reference.

After you have run the `tuist generate` command you should see both an `ApolloDev.xcodeproj` and `ApolloDev.xcworkspace` in the projects root directory. You should only use the Xcode Workspace for development as it includes the `ApolloDev.xcodeproj` as well as the SPM packages for the subtree projects so that everything can be developed in the same workspace.

### Submitting Changes

After working and making changes in the `ApolloDev.xcworkspace` you can commit your changes as normal and submit a PR to the `main` branch of the `apollo-ios-dev` repo for review.

## Issues

To report an issue, bug, or feature request ou can do so in the [apollo-ios](https://github.com/apollographql/apollo-ios/issues) repo.

## Roadmap

The [roadmap](https://github.com/apollographql/apollo-ios/blob/main/ROADMAP.md) is a high-level document that describes the next major steps or milestones for this project. We are always open to feature requests, and contributions from the community.

## Contributing

This project is being developed using Xcode 15 and Swift 5.9.

Some of the tests run against [a simple GraphQL server serving the Star Wars example schema](https://github.com/apollographql/starwars-server) (see installation instructions there).

For further information on contributing, reporting issues, suggesting features, etc please see our [Apollo Contributor Guide](https://github.com/apollographql/apollo-ios-dev/blob/main/CONTRIBUTING.md) guide.

## Maintainers

- [@AnthonyMDev](https://github.com/AnthonyMDev)
- [@calvincestari](https://github.com/calvincestari)
- [@bignimbus](https://github.com/bignimbus)
- [@bobafetters](https://github.com/bobafetters)

## Who is Apollo?

[Apollo](https://apollographql.com/) builds open-source software and a graph platform to unify GraphQL across your apps and services. We help you ship faster with:

- [Apollo Studio](https://www.apollographql.com/studio/develop/) – A free, end-to-end platform for managing your GraphQL lifecycle. Track your GraphQL schemas in a hosted registry to create a source of truth for everything in your graph. Studio provides an IDE (Apollo Explorer) so you can explore data, collaborate on queries, observe usage, and safely make schema changes.
- [Apollo Federation](https://www.apollographql.com/apollo-federation) – The industry-standard open architecture for building a distributed graph. Use Apollo’s gateway to compose a unified graph from multiple subgraphs, determine a query plan, and route requests across your services.
- [Apollo Client](https://www.apollographql.com/apollo-client/) – The most popular GraphQL client for the web. Apollo also builds and maintains [Apollo iOS](https://github.com/apollographql/apollo-ios) and [Apollo Kotlin](https://github.com/apollographql/apollo-kotlin).
- [Apollo Server](https://www.apollographql.com/docs/apollo-server/) – A production-ready JavaScript GraphQL server that connects to any microservice, API, or database. Compatible with all popular JavaScript frameworks and deployable in serverless environments.

## Learn how to build with Apollo

Check out the [Odyssey](https://odyssey.apollographql.com/) learning platform, the perfect place to start your GraphQL journey with videos and interactive code challenges. Join the [Apollo Community](https://community.apollographql.com/) to interact with and get technical help from the GraphQL community.
