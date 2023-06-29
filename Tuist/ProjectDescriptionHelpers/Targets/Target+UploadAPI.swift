import ProjectDescription

extension Target {
    
    public static func uploadFramework() -> Target {
        let target: ApolloTarget = .uploadAPI
        
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
            dependencies: [
                .package(product: "ApolloAPI")
            ],
            settings: .forTarget(target),
            additionalFiles: [
                .folderReference(path: "Sources/\(target.name)/graphql")
            ]
        )
    }
    
}
