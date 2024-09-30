import ProjectDescription
import ProjectDescriptionHelpers

// MARK: - Project

let project = Project(
    name: "ApolloDev",
    organizationName: "apollographql",
    packages: [
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.2.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.1"),
        .package(path: "apollo-ios"),
        .package(path: "apollo-ios-codegen"),
        .package(path: "apollo-ios-pagination"),
    ],
    settings: Settings.settings(configurations: [
        .debug(name: .debug, xcconfig: "Configuration/Apollo/Apollo-Project-Debug.xcconfig"),
        .release(name: .release, xcconfig: "Configuration/Apollo/Apollo-Project-Release.xcconfig"),
        .release(name: .performanceTesting, xcconfig: "Configuration/Apollo/Apollo-Project-Performance-Testing.xcconfig")
    ]),
    targets: [
        .animalKingdomFramework(),
        .starWarsFramework(),
        .gitHubFramework(),
        .uploadFramework(),
        .subscriptionFramework(),
        .apolloWrapperFramework(),
        .apolloCodegenLibWrapperFramework(),
        .apolloInternalTestHelpersFramework(),
        .apolloCodegenInternalTestHelpersFramework(),
        .apolloTests(),
        .apolloPaginationTests(),
        .apolloPerformanceTests(),
        .apolloCodegenTests(),
        .codegenCLITests()
    ],
    schemes: [
        .apolloCodegenTests(),
        .apolloPerformanceTests(),
        .apolloPaginationTests(),        
        .apolloTests(),
        .codegenCLITests()
    ],
    additionalFiles: [
        .glob(pattern: "Tests/TestPlans/**"),
        .folderReference(path: "Sources/\(ApolloTarget.gitHubAPI.name)/graphql"),
        .folderReference(path: "Sources/\(ApolloTarget.subscriptionAPI.name)/graphql"),
        .folderReference(path: "Sources/\(ApolloTarget.uploadAPI.name)/graphql")
    ]
)
