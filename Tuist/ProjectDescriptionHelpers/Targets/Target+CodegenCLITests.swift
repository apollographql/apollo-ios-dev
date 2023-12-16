import ProjectDescription

extension Target {
    
    public static func codegenCLITests() -> Target {
        let target: ApolloTarget = .codegenCLITests
        
        return Target(
            name: target.name,
            destinations: target.destinations,
            product: .unitTests,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            sources: [
                "Tests/\(target.name)/*.swift",
                "Tests/\(target.name)/Commands/**",
                "Tests/\(target.name)/Matchers/**",
                "Tests/\(target.name)/Support/**"
            ],
            dependencies: [
                .target(name: ApolloTarget.apolloInternalTestHelpers.name),
                .package(product: "Apollo"),
                .package(product: "CodegenCLI"),
                .package(product: "Nimble"),
            ],
            settings: .forTarget(target)
        )
    }
    
}

extension Scheme {
    
    public static func codegenCLITests() -> Scheme {
        let target: ApolloTarget = .codegenCLITests
        
        return Scheme(
            name: target.name,
            buildAction: .buildAction(targets: [
                TargetReference(projectPath: nil, target: target.name)
            ]),
            testAction: .testPlans([
                ApolloTestPlan.codegenCLITest.path
            ])
        )
    }
    
}
