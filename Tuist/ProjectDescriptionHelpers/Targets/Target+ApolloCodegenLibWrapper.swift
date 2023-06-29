import ProjectDescription

extension Target {
    
    public static func apolloCodegenLibWrapperFramework() -> Target {
        let target: ApolloTarget = .apolloCodegenLibWrapper
        
        return Target(
            name: target.name,
            platform: .macOS,
            product: .framework,
            bundleId: "com.apollographql.\(target.name.lowercased())",
            deploymentTarget: .macOSApollo,
            infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
            dependencies: [
                .package(product: "ApolloCodegenLib")
            ],
            settings: .forTarget(target)
        )
    }
    
}
