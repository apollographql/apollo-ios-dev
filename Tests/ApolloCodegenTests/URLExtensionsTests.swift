import Foundation
import XCTest
import Nimble
import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers
@testable import ApolloCodegenLib

class URLExtensionsTests: XCTestCase {
 
  func testGettingParentFolderURL() {
    let apolloCodegenTests = FileFinder.findParentFolder()
    
    let expectedParent = TestFileHelper.sourceRootURL()
      .appendingPathComponent("Tests")
    
    let parent = apolloCodegenTests.parentFolderURL()
    XCTAssertEqual(parent, expectedParent)
  }
  
  func testGettingChildFolderURL() {
    let testsFolderURL = TestFileHelper.sourceRootURL()
      .appendingPathComponent("Tests")
    
    let expectedChild = FileFinder.findParentFolder()
    
    let child = testsFolderURL.childFolderURL(folderName: "ApolloCodegenTests")
    XCTAssertEqual(child, expectedChild)
  }
  
  func testGettingChildFileURL() throws {
    let apolloCodegenTests = FileFinder.findParentFolder()

    let expectedFileURL = URL(fileURLWithPath: #filePath)

    let fileURL = try apolloCodegenTests.childFileURL(fileName: "URLExtensionsTests.swift")
    
    XCTAssertEqual(fileURL, expectedFileURL)
  }
  
  func testGettingChildFileURLWithEmptyFilenameThrows() {
    let starWars = TestFileHelper.starWarsFolderURL()

    do {
      _ = try starWars.childFileURL(fileName: "")
      XCTFail("That should have thrown")
    } catch {
      switch error {
      case ApolloURLError.fileNameIsEmpty:
        // This is what we want
        break
      default:
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testGettingHiddenChildFileURL() throws {
    let parentURL = FileFinder.findParentFolder()
    let filename = ".hiddenFile"

    let expectedURL = parentURL.appendingPathComponent(filename, isDirectory: false)
    let childURL = try parentURL.childFileURL(fileName: filename)

    XCTAssertEqual(childURL, expectedURL)
  }
  
  func testIsDirectoryForExistingDirectory() async {
    let parentDirectory = FileFinder.findParentFolder()
    await expect { await ApolloFileManager.default.doesDirectoryExist(atPath: parentDirectory.path) }.to(beTrue())
    XCTAssertTrue(parentDirectory.isDirectoryURL)
  }
  
  func testIsDirectoryForExistingFile() async {
    let currentFileURL = FileFinder.fileURL()
    await expect { await ApolloFileManager.default.doesFileExist(atPath: currentFileURL.path) }.to(beTrue())
    XCTAssertFalse(currentFileURL.isDirectoryURL)
  }
  
  func testIsSwiftFileForExistingFile() async {
    let currentFileURL = FileFinder.fileURL()
    await expect { await ApolloFileManager.default.doesFileExist(atPath: currentFileURL.path) }.to(beTrue())
    XCTAssertTrue(currentFileURL.isSwiftFileURL)
  }
  
  func testIsSwiftFileForNonExistentFileWithSingleExtension() async {
    let currentDirectory = FileFinder.findParentFolder()
    let doesntExist = currentDirectory.appendingPathComponent("test.swift")
    
    await expect { await ApolloFileManager.default.doesFileExist(atPath: doesntExist.path) }.to(beFalse())
    XCTAssertTrue(doesntExist.isSwiftFileURL)
  }
  
  func testIsSwiftFileForNonExistentFileWithMultipleExtensions() async {
    let currentDirectory = FileFinder.findParentFolder()
    let doesntExist = currentDirectory.appendingPathComponent("test.graphql.swift")
    
    await expect { await ApolloFileManager.default.doesFileExist(atPath: doesntExist.path) }.to(beFalse())
    XCTAssertTrue(doesntExist.isSwiftFileURL)
  }
  
}
