import ProjectDescription

extension Target {
    
    public static func apolloCodegenTests() -> Target {
        let target: ApolloTarget = .apolloCodegenTests
        
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
                    .glob(pattern: "Tests/\(target.name)/Resources/*.json")
                ]
            ),
            dependencies: [
                .target(name: ApolloTarget.apolloCodegenInternalTestHelpers.name),
                .target(name: ApolloTarget.apolloCodegenLibWrapper.name),
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .package(product: "OrderedCollections"),
                .package(product: "Nimble")
            ],
            settings: .forTarget(target)
        )
    }
    
}

extension Scheme {
    
    public static func apolloCodegenTests() -> Scheme {
        let target: ApolloTarget = .apolloCodegenTests
        
        return Scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
                TargetReference(projectPath: nil, target: target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.codegenTest.path,
                ApolloTestPlan.codegenCITest.path
            ])
        )
    }
    
}
