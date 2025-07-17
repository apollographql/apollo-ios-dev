import ProjectDescription

extension Target {

    public static func apolloPaginationTests() -> Target {
        let target: ApolloTarget = .apolloPaginationTests

      return .target(
            name: target.name,
            destinations: target.destinations,
            product: .unitTests,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            sources: [
                "Tests/\(target.name)/**",
            ],
            dependencies: [
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .package(product: "Apollo"),
                .package(product: "ApolloAPI"),
                .package(product: "ApolloTestSupport"),
                .package(product: "ApolloPagination"),
                .package(product: "Nimble")
            ],
            settings: .forTarget(target)
        )
    }

}

extension Scheme {

    public static func apolloPaginationTests() -> Scheme {
        let target: ApolloTarget = .apolloPaginationTests

      return .scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
              TargetReference.target(target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.paginationTest.path,
            ])
        )
    }

}
