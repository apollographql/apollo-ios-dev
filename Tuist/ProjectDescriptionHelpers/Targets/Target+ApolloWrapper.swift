import ProjectDescription

extension Target {
    
    public static func apolloWrapperFramework() -> Target {
        let target: ApolloTarget = .apolloWrapper
        
        return Target(
            name: target.name,
            platform: .macOS,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: target.deploymentTarget,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            dependencies: [
                .package(product: "Apollo")
            ],
            settings: .forTarget(target)
        )
    }
    
}
