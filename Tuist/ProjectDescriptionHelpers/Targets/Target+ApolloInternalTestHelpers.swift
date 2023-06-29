import ProjectDescription

extension Target {
    
    public static func apolloInternalTestHelpersFramework() -> Target {
        let target: ApolloTarget = .apolloInternalTestHelpers
        
        return Target(
            name: target.name,
            platform: .macOS,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: .macOSApollo,
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
