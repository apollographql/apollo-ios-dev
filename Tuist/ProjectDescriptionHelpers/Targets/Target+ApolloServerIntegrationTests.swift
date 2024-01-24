import ProjectDescription

extension Target {
    
    public static func apolloServerIntegrationTests() -> Target {
        let target: ApolloTarget = .apolloServerIntegrationTests
        
        return Target(
            name: target.name,
            destinations: target.destinations,
            product: .unitTests,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            sources: [
                "Tests/\(target.name)/**",
            ],
            dependencies: [
                .target(name: ApolloTarget.apolloCodegenInternalTestHelpers.name),
                .target(name: ApolloTarget.apolloCodegenLibWrapper.name),
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .target(name: ApolloTarget.starWarsAPI.name),
                .target(name: ApolloTarget.subscriptionAPI.name),
                .target(name: ApolloTarget.uploadAPI.name),
                .package(product: "Apollo"),
                .package(product: "ApolloSQLite"),
                .package(product: "ApolloWebSocket"),
                .package(product: "Nimble")
            ],
            settings: .forTarget(target)
        )
    }
    
}

extension Scheme {
    
    public static func apolloServerIntegrationTests() -> Scheme {
        let target: ApolloTarget = .apolloServerIntegrationTests
        
        return Scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
                TargetReference(projectPath: nil, target: target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.integrationTest.path
            ])
        )
    }
    
}
