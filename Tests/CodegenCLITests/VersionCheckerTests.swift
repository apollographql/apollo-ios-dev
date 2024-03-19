import XCTest
import Nimble
import ApolloInternalTestHelpers
@testable import CodegenCLI
import ArgumentParser
@testable import Apollo

class VerifyCLIVersionUpdateTest: XCTestCase {
  /// This test verifies that the `Constants/CLIVersion` is updated when the version of Apollo
  /// changes. It matches the CLI version against the `Apollo Info.plist` version number.
  /// This version number uses the project configurations `CURRENT_PROJECT_VERSION`.
  func test__cliVersion__matchesApolloProjectVersion() {
    // given
    let codegenLibVersion = Apollo.Constants.ApolloVersion

    // when
    let cliVersion = CodegenCLI.Constants.CLIVersion

    // then
    expect(cliVersion).to(equal(codegenLibVersion))
  }
}

class VersionCheckerTests: XCTestCase {

  var fileManager: TestIsolatedFileManager!

  override func setUpWithError() throws {
    try super.setUpWithError()
    fileManager = try self.testIsolatedFileManager()
  }

  override func tearDown() {
    super.tearDown()
    fileManager = nil
  }

  private enum packageResolvedVersion: CaseIterable {
    case v1
    case v2
    case v3

    private var int: Int {
      switch self {
      case .v1: 1
      case .v2: 2
      case .v3: 3
      }
    }

    func fileBody(apolloVersion version: String) -> String {
      switch self {
      case .v1:
        return """
        {
          "object": {
            "pins": [
              {
                "package": "Apollo",
                "repositoryURL": "https://github.com/apollographql/apollo-ios.git",
                "state": {
                  "branch": null,
                  "revision": "5349afb4e9d098776cc44280258edd5f2ae571ed",
                  "version": "\(version)"
                }
              }
            ]
          },
          "version": 1
        }
        """

      case .v2, .v3:
        return """
        {
          "pins": [
            {
              "identity": "apollo-ios",
              "kind" : "remoteSourceControl",
              "location": "https://github.com/apollographql/apollo-ios.git",
              "state": {
                "revision": "5349afb4e9d098776cc44280258edd5f2ae571ed",
                "version": "\(version)"
              }
            }
          ],
          "version": \(self.int)
        }
        """
      }
    }
  }

  // MARK: - Tests

  private func testPackageResolvedFile(
    packageVersion: packageResolvedVersion,
    inDirectory directory: String? = nil,
    apolloVersion: String,
    _ test: (() throws -> Void)
  ) rethrows {
    expect(try self.fileManager.createFile(
      body: packageVersion.fileBody(apolloVersion: apolloVersion),
      named: "Package.resolved",
      inDirectory: directory
    )).notTo(throwError())

    try test()
  }

  func test__matchCLIVersionToApolloVersion__givenNoPackageResolvedFileInProject_returnsNoApolloVersionFound() throws {
    // when
    let result = try VersionChecker.matchCLIVersionToApolloVersion(
      projectRootURL: fileManager.directoryURL
    )

    // then
    expect(result).to(equal(.noApolloVersionFound))
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInProjectRoot_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch() throws {
    // given
    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        apolloVersion: Constants.CLIVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(.versionMatch))
      }
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInProjectRoot_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch() throws {
    // given
    let apolloVersion = "1.0.0.test-1"

    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        apolloVersion: apolloVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(
          .versionMismatch(cliVersion: Constants.CLIVersion, apolloVersion: apolloVersion)
        ))
      }
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspace_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch() throws {
    // given
    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        inDirectory: "MyProject.xcworkspace/xcshareddata/swiftpm",
        apolloVersion: Constants.CLIVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(.versionMatch))
      }
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspace_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch() throws {
    // given
    let apolloVersion = "1.0.0.test-1"

    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        inDirectory: "MyProject.xcworkspace/xcshareddata/swiftpm",
        apolloVersion: apolloVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(
          .versionMismatch(cliVersion: Constants.CLIVersion, apolloVersion: apolloVersion)
        ))
      }
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeProject_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch() throws {
    // given
    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        inDirectory: "MyProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
        apolloVersion: Constants.CLIVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(.versionMatch))
      }
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeProject_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMismatch() throws {
    // given
    let apolloVersion = "1.0.0.test-1"

    for packageVersion in packageResolvedVersion.allCases {
      try testPackageResolvedFile(
        packageVersion: packageVersion,
        inDirectory: "MyProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
        apolloVersion: apolloVersion
      ) {

        // when
        let result = try VersionChecker.matchCLIVersionToApolloVersion(
          projectRootURL: fileManager.directoryURL
        )

        // then
        expect(result).to(equal(
          .versionMismatch(cliVersion: Constants.CLIVersion, apolloVersion: apolloVersion)
        ))
      }
    }
  }
  
  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspaceAndProject_withKnownResolvedFileFormats_hasMatchingVersion_returns_versionMatch_fromWorkspace() throws {
    // given
    for packageVersion in packageResolvedVersion.allCases {
      try fileManager.createFile(
        body: packageVersion.fileBody(apolloVersion: Constants.CLIVersion),
        named: "Package.resolved",
        inDirectory: "MyProject.xcworkspace/xcshareddata/swiftpm"
      )

      try fileManager.createFile(
        body: packageVersion.fileBody(apolloVersion: Constants.CLIVersion),
        named: "Package.resolved",
        inDirectory: "MyProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
      )

      // when
      let result = try VersionChecker.matchCLIVersionToApolloVersion(
        projectRootURL: fileManager.directoryURL
      )

      // then
      expect(result).to(equal(.versionMatch))
    }
  }

  func test__matchCLIVersionToApolloVersion__givenPackageResolvedFileInXcodeWorkspaceAndProject_withKnownResolvedFileFormats_hasNonMatchingVersion_returns_versionMatch_fromWorkspace() throws {
    // given
    for packageVersion in packageResolvedVersion.allCases {
      try fileManager.createFile(
        body: packageVersion.fileBody(apolloVersion: Constants.CLIVersion),
        named: "Package.resolved",
        inDirectory: "MyProject.xcworkspace/xcshareddata/swiftpm"
      )

      let apolloProjectVersion = "1.0.0.test-1"
      try fileManager.createFile(
        body: packageVersion.fileBody(apolloVersion: apolloProjectVersion),
        named: "Package.resolved",
        inDirectory: "MyProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
      )

      // when
      let result = try VersionChecker.matchCLIVersionToApolloVersion(
        projectRootURL: fileManager.directoryURL
      )

      // then
      expect(result).to(equal(.versionMatch))
    }
  }

}

// MARK: - Helpers

fileprivate let ApolloLibraryVersion: String = {
  let codegenInfoDict = Bundle(for: ApolloClient.self).infoDictionary
  return codegenInfoDict?["CFBundleVersion"] as! String
}()
