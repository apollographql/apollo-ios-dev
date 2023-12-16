import ProjectDescription

extension Target {
    
    public static func animalKingdomFramework() -> Target {
        let target: ApolloTarget = .animalKingdomAPI
        
        return Target(
            name: target.name,
            destinations: target.destinations, 
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            infoPlist: .file(path: "Sources/\(target.name)/Info.plist"),
            sources: [
                "Sources/\(target.name)/\(target.name)/Sources/**",
                "Sources/\(target.name)/Resources.swift"
            ],
            resources: ResourceFileElements(
                resources: [
                    .folderReference(path: "Sources/\(target.name)/animalkingdom-graphql")
                ]
            ),
            dependencies: [
                .package(product: "ApolloAPI")
            ],
            settings: .forTarget(target)
        )
    }
    
}
