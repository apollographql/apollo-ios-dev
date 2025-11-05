import Foundation
import ProjectDescription

public enum ApolloTarget {
  case animalKingdomAPI
  case apolloCodegenInternalTestHelpers
  case apolloCodegenLibWrapper
  case apolloCodegenTests
  case apolloInternalTestHelpers
  case apolloPaginationTests
  case apolloPerformanceTests
  case apolloTests
  case apolloWrapper
  case codegenCLITests
  case gitHubAPI
  case starWarsAPI
  case subscriptionAPI
  case uploadAPI

  public var name: String {
    switch self {
    case .animalKingdomAPI:
      return "AnimalKingdomAPI"
    case .apolloCodegenInternalTestHelpers:
      return "ApolloCodegenInternalTestHelpers"
    case .apolloCodegenLibWrapper:
      return "ApolloCodegenLibWrapper"
    case .apolloCodegenTests:
      return "ApolloCodegenTests"
    case .apolloInternalTestHelpers:
      return "ApolloInternalTestHelpers"
    case .apolloPaginationTests:
      return "ApolloPaginationTests"
    case .apolloPerformanceTests:
      return "ApolloPerformanceTests"
    case .apolloTests:
      return "ApolloTests"
    case .apolloWrapper:
      return "ApolloWrapper"
    case .codegenCLITests:
      return "CodegenCLITests"
    case .gitHubAPI:
      return "GitHubAPI"
    case .starWarsAPI:
      return "StarWarsAPI"
    case .subscriptionAPI:
      return "SubscriptionAPI"
    case .uploadAPI:
      return "UploadAPI"
    }
  }

  public var xcconfigName: String {
    switch self {
    case .animalKingdomAPI:
      return "Apollo-Target-AnimalKingdomAPI"
    case .apolloCodegenInternalTestHelpers:
      return "Apollo-Target-CodegenInternalTestHelpers"
    case .apolloCodegenLibWrapper:
      return "Apollo-Target-ApolloCodegenLibWrapper"
    case .apolloCodegenTests:
      return "Apollo-Target-CodegenTests"
    case .apolloInternalTestHelpers:
      return "Apollo-Target-InternalTestHelpers"
    case .apolloPaginationTests:
      return "Apollo-Target-PaginationTests"
    case .apolloPerformanceTests:
      return "Apollo-Target-PerformanceTests"
    case .apolloTests:
      return "Apollo-Target-Tests"
    case .apolloWrapper:
      return "Apollo-Target-ApolloWrapper"
    case .codegenCLITests:
      return "Apollo-Target-CodegenCLITests"
    case .gitHubAPI:
      return "Apollo-Target-GitHubAPI"
    case .starWarsAPI:
      return "Apollo-Target-StarWarsAPI"
    case .subscriptionAPI:
      return "Apollo-Target-SubscriptionAPI"
    case .uploadAPI:
      return "Apollo-Target-UploadAPI"
    }
  }

  public var destinations: Destinations {
    switch self {
    case
        .animalKingdomAPI,
        .apolloCodegenLibWrapper,
        .apolloCodegenInternalTestHelpers,
        .apolloCodegenTests,
        .apolloInternalTestHelpers,
        .apolloPaginationTests,
        .apolloPerformanceTests,
        .apolloTests,
        .apolloWrapper,
        .codegenCLITests,
        .gitHubAPI,
        .starWarsAPI,
        .subscriptionAPI,
        .uploadAPI:
      return Destinations([.mac])
    }
  }

  public var deploymentTargets: DeploymentTargets {
    switch self {
    case
        .animalKingdomAPI,
        .apolloWrapper,
        .gitHubAPI,
        .starWarsAPI,
        .subscriptionAPI,
        .uploadAPI:
      return DeploymentTargets(macOS: "10.15")
    case
        .apolloInternalTestHelpers,
        .apolloPerformanceTests,
        .apolloTests,
        .apolloPaginationTests,
        .apolloCodegenInternalTestHelpers,
        .apolloCodegenLibWrapper,
        .apolloCodegenTests,
        .codegenCLITests:
      return DeploymentTargets(macOS: "13.0")
    }
  }
}
