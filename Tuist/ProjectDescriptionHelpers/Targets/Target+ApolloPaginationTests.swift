import ProjectDescription

extension Target {

    public static func apolloPaginationTests() -> Target {
        let target: ApolloTarget = .apolloPaginationTests

        return Target(
            name: target.name,
            platform: .macOS,
            product: .unitTests,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: target.deploymentTarget,
            sources: [
                "Tests/\(target.name)/**",
            ],
            dependencies: [
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .target(name: ApolloTarget.starWarsAPI.name),
                .target(name: ApolloTarget.uploadAPI.name),
                .package(product: "Apollo"),
                .package(product: "ApolloAPI"),
                .package(product: "ApolloTestSupport"),
                .package(product: "Nimble"),
                .package(product: "apollo-ios-pagination")
            ],
            settings: .forTarget(target)
        )
    }

}

extension Scheme {

    public static func apolloPaginationTests() -> Scheme {
        let target: ApolloTarget = .apolloPaginationTests

        return Scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
                TargetReference(projectPath: nil, target: target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.paginationTest.path,
            ])
        )
    }

}
