import XCTest

/// Computes a `URL` for a temporary directory that is unique to a given test.
///
/// This does not create the directory, it only handles computing a directory path.
///
/// To create a directory and write files to it during a unit test, use `TestIsolatedFileManager`,
/// which uses this object internally for computing it's temporary directory.
public struct TestFilePathBuilder: Sendable {

  let testName: String
  public let testIsolatedOutputFolder: URL

  public init(test: XCTestCase) {
    let testName =
    test.name
      .trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
      .replacingOccurrences(of: " ", with: "_")

    let directoryURL: URL
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
      directoryURL = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
    } else {
      directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    let outputFolderURL = directoryURL
      .appendingPathComponent(testName, isDirectory: true)

    self.testName = testName
    self.testIsolatedOutputFolder = outputFolderURL
  }

  public var schemaOutputURL: URL {
    testIsolatedOutputFolder.appendingPathComponent("schema.graphqls")
  }

}
