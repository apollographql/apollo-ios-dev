import ProjectDescription

extension Target {
    
    public static func subscriptionFramework() -> Target {
        let target: ApolloTarget = .subscriptionAPI
        
        return Target(
            name: target.name,
            platform: .macOS,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: .macOSApollo,
            infoPlist: .file(path: "Sources/\(target.name)/Info.plist"),
            sources: [
                "Sources/\(target.name)/\(target.name)/Sources/**"
            ],
            resources: ResourceFileElements(
                resources: [
                    .glob(pattern: "Sources/\(target.name)/graphql/**")
                ]
            ),
            dependencies: [
                .package(product: "ApolloAPI")
            ],
            settings: .forTarget(target)
        )
    }
    
}
