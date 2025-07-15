import ProjectDescription

extension Target {

  public static func apolloCodegenLibWrapperFramework() -> Target {
    let target: ApolloTarget = .apolloCodegenLibWrapper

    return .target(
      name: target.name,
      destinations: target.destinations,
      product: .framework,
      bundleId: "com.apollographql.\(target.name.lowercased())",
      deploymentTargets: target.deploymentTargets,
      infoPlist: .file(path: "Tests/\(target.name)/Info.plist"),
      dependencies: [
        .package(product: "ApolloCodegenLib")
      ],
      settings: .forTarget(target)
    )
  }

}
