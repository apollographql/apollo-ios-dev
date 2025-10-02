import Foundation
import ApolloCodegenLib
import SwiftScriptHelpers

struct DocumentationGenerator {
  static func main() {
    do {
      try shell(docBuildCommand())
      CodegenLogger.log("Combined Docs Generation Complete!")

    } catch {
      CodegenLogger.log("Error: \(error)", logLevel: .error)
      exit(1)
    }
  }

  // Grab the parent folder of this file on the filesystem
  static let parentFolderOfScriptFile = FileFinder.findParentFolder()

  // Use that to calculate the source root
  static let sourceRootURL = parentFolderOfScriptFile
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // SwiftScripts
    .deletingLastPathComponent() // apollo-ios-dev

  static let doccFolder = sourceRootURL.appendingPathComponent("docs/docc")

  static func docBuildCommand() -> String {
    let outputPath = DocumentationGenerator.doccFolder
      .appendingPathComponent("Apollo")
      .appendingPathExtension("doccarchive")

    return """
    swift package \
    --allow-writing-to-directory \(outputPath) \
    generate-documentation \    
    --target Apollo \
    --target ApolloAPI \
    --target ApolloSQLite \
    --target ApolloCodegenLib \
    --target ApolloPagination \
    --enable-experimental-combined-documentation \
    --enable-inherited-docs \
    --source-service github \
    --source-service-base-url https://github.com/apollographql/apollo-ios-dev/blob/main \
    --checkout-path \(sourceRootURL.relativePath) \
    --disable-indexing \
    --output-path \(outputPath) \
    --hosting-base-path docs/ios/docc
    """
  }

  static func shell(_ command: String) throws {
    let task = Process()
    let pipe = Pipe()
    let outHandle = pipe.fileHandleForReading
    outHandle.readabilityHandler = { pipe in
      if let line = String(data: pipe.availableData, encoding: .utf8), !line.isEmpty {
        CodegenLogger.log(line, logLevel: .debug)
      }
    }

    task.environment = ProcessInfo.processInfo.environment
    task.standardOutput = pipe
    task.standardError = pipe

    task.currentDirectoryURL = sourceRootURL.appendingPathComponent("SwiftScripts")
    task.environment?["OS_ACTIVITY_DT_MODE"] = nil
    task.environment?["DOCC_JSON_PRETTYPRINT"] = "YES"    
    task.arguments = ["-c", command]

    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil
    try task.run()
    task.waitUntilExit()
  }

  enum Error: Swift.Error {
    case rootDocumentationJSONNotFound
  }
}

DocumentationGenerator.main()
