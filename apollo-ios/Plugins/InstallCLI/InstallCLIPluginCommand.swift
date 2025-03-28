import Foundation
import PackagePlugin
import os

@main
struct InstallCLIPluginCommand: CommandPlugin {

  enum Error: Swift.Error {
    case CannotDetermineXcodeVersion
  }

  func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
    let dependencies = context.package.dependencies
    try dependencies.forEach { dep in
      if dep.package.displayName == "Apollo" {
        let process = Process()
        let path = try context.tool(named: "sh").path
        process.executableURL = URL(fileURLWithPath: path.string)
        process.arguments = ["\(dep.package.directory)/scripts/download-cli.sh", context.package.directory.string]
        try process.run()
        process.waitUntilExit()
      }
    }
  }

}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension InstallCLIPluginCommand: XcodeCommandPlugin {

  /// 👇 This entry point is called when operating on an Xcode project.
  func performCommand(context: XcodePluginContext, arguments: [String]) throws {
    let process = Process()
    let toolPath = try context.tool(named: "sh").path
    process.executableURL = URL(fileURLWithPath: toolPath.string)

    let downloadScriptPath = try downloadScriptPath(context: context)
    process.arguments = [downloadScriptPath, context.xcodeProject.directory.string]

    try process.run()
    process.waitUntilExit()
  }

  /// Used to get the location of the CLI download script.
  ///
  /// - Parameter context: Contextual information based on the plugin's stated intent and requirements.
  /// - Returns: The path to the download script used to fetch the CLI binary.
  private func downloadScriptPath(context: XcodePluginContext) throws -> String {
    let xcodeVersion = try xcodeVersion(context: context)
    let relativeScriptPath = "SourcePackages/checkouts/apollo-ios/scripts/download-cli.sh"
    let absoluteScriptPath: String

    if xcodeVersion.lexicographicallyPrecedes("16.3") {
      absoluteScriptPath = "\(context.pluginWorkDirectory)/../../../\(relativeScriptPath)"
    } else {
      absoluteScriptPath = "\(context.pluginWorkDirectory)/../../../../\(relativeScriptPath)"
    }

    return absoluteScriptPath
  }

  /// Used to get a string representation of Xcode in the current toolchain.
  ///
  /// - Parameter context: Contextual information based on the plugin's stated intent and requirements.
  /// - Returns: A string representation of the Xcode version.
  private func xcodeVersion(context: XcodePluginContext) throws -> String {
    let process = Process()
    let toolPath = try context.tool(named: "xcrun").path
    process.executableURL = URL(fileURLWithPath: toolPath.string)
    process.arguments = ["xcodebuild", "-version"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe

    try process.run()
    process.waitUntilExit()

    guard
      let outputData = try outputPipe.fileHandleForReading.readToEnd(),
      let output = String(data: outputData, encoding: .utf8)
    else {
      throw Error.CannotDetermineXcodeVersion
    }

    let xcodeVersionString = output.components(separatedBy: "\n")[0]
    guard !xcodeVersionString.isEmpty else {
      throw Error.CannotDetermineXcodeVersion
    }

    let versionString = xcodeVersionString
      .components(separatedBy: CharacterSet.decimalDigits.inverted)
      .compactMap({ $0.isEmpty ? nil : $0 })
      .joined(separator: ".")

    return versionString
  }

}
#endif
