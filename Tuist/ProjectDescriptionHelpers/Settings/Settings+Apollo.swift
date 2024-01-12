import ProjectDescription

extension Settings {
    
    static func forTarget(_ target: ApolloTarget) -> Settings {
        let configPath = Path("Configuration/Apollo/\(target.xcconfigName).xcconfig")
        let debugConfig = Configuration.debug(name: .debug, xcconfig: configPath)
        let releaseConfig = Configuration.release(name: .release, xcconfig: configPath)
        let performanceTestingConfig = Configuration.release(name: .performanceTesting, xcconfig: configPath)
        let settings = Settings.settings(
        configurations: [
            debugConfig,
            releaseConfig,
            performanceTestingConfig
        ],
        defaultSettings: .none
        )
        return settings
    }
    
}
