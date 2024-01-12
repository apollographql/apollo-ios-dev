import ProjectDescription

extension Target {
    
    public static func apolloInternalTestHelpersFramework() -> Target {
        let target: ApolloTarget = .apolloInternalTestHelpers
        
        return Target(
            name: target.name,
            destinations: target.destinations,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            sources: [
                "Tests/\(target.name)/**",
            ],
            resources: ResourceFileElements(
                resources: [
                    .glob(pattern: "Tests/\(target.name)/Resources/**/*.txt")
                ]
            ),
            dependencies: [
                .target(name: ApolloTarget.apolloWrapper.name),
                .package(product: "ApolloAPI"),
                .package(product: "ApolloSQLite"),
                .package(product: "ApolloWebSocket")
            ],
            settings: .forTarget(target)
        )
    }
    
}
