import Foundation

enum ApolloTarget {
    case animalKingdomAPI
    case apolloCodegenInternalTestHelpers
    case apolloCodegenLibWrapper
    case apolloCodegenTests
    case apolloInternalTestHelpers
    case apolloPerformanceTests
    case apolloServerIntegrationTests
    case apolloTests
    case apolloWrapper
    case codegenCLITests
    case gitHubAPI
    case starWarsAPI
    case subscriptionAPI
    case uploadAPI
    
    var name: String {
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
        case .apolloPerformanceTests:
            return "ApolloPerformanceTests"
        case .apolloServerIntegrationTests:
            return "ApolloServerIntegrationTests"
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
    
    var xcconfigName: String {
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
        case .apolloPerformanceTests:
            return "Apollo-Target-PerformanceTests"
        case .apolloServerIntegrationTests:
            return "Apollo-Target-ServerIntegrationTests"
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
}
