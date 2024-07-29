import ProjectDescription

extension Target {
    
    public static func apolloWrapperFramework() -> Target {
        let target: ApolloTarget = .apolloWrapper
        
        return Target(
            name: target.name,
            destinations: target.destinations,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTargets: target.deploymentTargets,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            dependencies: [
                .package(product: "Apollo")
            ],
            settings: .forTarget(target)
        )
    }
    
}
