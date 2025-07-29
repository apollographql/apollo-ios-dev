import ProjectDescription

extension Target {

  public static func uploadFramework() -> Target {
    let target: ApolloTarget = .uploadAPI

    return .target(
      name: target.name,
      destinations: target.destinations,
      product: .framework,
      bundleId: "com.apollographql.\(target.name.lowercased())",
      deploymentTargets: target.deploymentTargets,
      infoPlist: .file(path: "Sources/\(target.name)/Info.plist"),
      sources: [
        "Sources/\(target.name)/\(target.name)/Sources/**"
      ],
      dependencies: [
        .package(product: "ApolloAPI")
      ],
      settings: .forTarget(target)
    )
  }

}
