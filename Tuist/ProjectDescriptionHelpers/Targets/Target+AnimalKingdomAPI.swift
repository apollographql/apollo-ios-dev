import ProjectDescription

extension Target {
    
    public static func animalKingdomFramework() -> Target {
        let target: ApolloTarget = .animalKingdomAPI
        
        return Target(
            name: target.name,
            platform: .macOS,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: .macOSApollo,
            infoPlist: .file(path: "Sources/\(target.name)/Info.plist"),
            sources: [
                "Sources/\(target.name)/\(target.name)/Sources/**",
                "Sources/\(target.name)/Resources.swift"
            ],
            resources: ResourceFileElements(
                resources: [
                    .glob(pattern: "Sources/\(target.name)/animalkingdom-graphql/**")
                ]
            ),
            dependencies: [
                .package(product: "ApolloAPI")
            ],
            settings: .forTarget(target)
        )
    }
    
}
