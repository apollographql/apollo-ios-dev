import ProjectDescription

extension Target {
    
    public static func apolloPerformanceTests() -> Target {
        let target: ApolloTarget = .apolloPerformanceTests
        
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
            resources: ResourceFileElements(
                resources: [
                    .glob(pattern: "Tests/\(target.name)/Responses/**/*.json")
                ]
            ),
            dependencies: [
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .target(name: ApolloTarget.animalKingdomAPI.name),
                .target(name: ApolloTarget.gitHubAPI.name),
                .package(product: "Apollo"),
                .package(product: "Nimble")
            ],
            settings: .forTarget(target)
        )
    }
    
}

extension Scheme {
    
    public static func apolloPerformanceTests() -> Scheme {
        let target: ApolloTarget = .apolloPerformanceTests
        
        return Scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
                TargetReference(projectPath: nil, target: target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.performanceTest.path
            ],
            configuration: .performanceTesting
            )
        )
    }
    
}
