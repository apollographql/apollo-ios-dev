import Foundation
import XCTest
import ApolloCodegenInternalTestHelpers
import ApolloInternalTestHelpers
@testable import ApolloCodegenLib
import Nimble

class FileManagerExtensionTests: XCTestCase {
  var uniquePath: String { testFilePathBuilder.testIsolatedOutputFolder.path }

  lazy var uniqueError: (any Error)! = {
    NSError(domain: "FileManagerExtensionTest", code: Int.random(in: 1...100))
  }()

  lazy var uniqueData: Data! = {
    let length = Int(128)
    let bytes = [UInt32](repeating: 0, count: length).map { _ in arc4random() }
    return Data(bytes: bytes, count: length)
  }()

  var testFilePathBuilder: TestFilePathBuilder!

  override func setUp() {
    super.setUp()
    testFilePathBuilder = TestFilePathBuilder(test: self)
  }

  override func tearDown() {
    testFilePathBuilder = nil
    uniqueError = nil
    uniqueData = nil
    super.tearDown()
  }

  // MARK: Presence

  func test_doesFileExist_givenFileExistsAndIsDirectory_shouldReturnFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true
    }))

    // then
    await expect { await mocked.doesFileExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesFileExist_givenFileExistsAndIsNotDirectory_shouldReturnTrue() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true
    }))

    // then
    await expect { await mocked.doesFileExist(atPath: self.uniquePath) }.to(beTrue())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesFileExist_givenFileDoesNotExistAndIsDirectory_shouldReturnFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false
    }))

    // then
    await expect { await mocked.doesFileExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesFileExist_givenFileDoesNotExistAndIsNotDirectory_shouldReturnFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false
    }))

    // then
    await expect { await mocked.doesFileExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesDirectoryExist_givenFilesExistsAndIsDirectory_shouldReturnTrue() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true
    }))

    // then
    await expect { await mocked.doesDirectoryExist(atPath: self.uniquePath) }.to(beTrue())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesDirectoryExist_givenFileExistsAndIsNotDirectory_shouldReturnFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true
    }))

    // then
    await expect { await mocked.doesDirectoryExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesDirectoryExist_givenFileDoesNotExistAndIsDirectory_shouldReturnFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false
    }))

    // then
    await expect { await mocked.doesDirectoryExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_doesDirectoryExist_givenFileDoesNotExistAndIsNotDirectory_shouldFalse() async {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false
    }))

    // then
    await expect { await mocked.doesDirectoryExist(atPath: self.uniquePath) }.to(beFalse())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  // MARK: Deletion

  func test_deleteFile_givenFileExistsAndIsDirectory_shouldThrow() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true
    }))

    // then
    await expect { try await mocked.deleteFile(atPath: self.uniquePath) }
      .to(throwError(FileManagerPathError.notAFile(path: self.uniquePath)))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteFile_givenFileExistsAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true

    }))
    await mocked.mock(closure: .removeItem({ [uniquePath] path in
      expect(path).to(equal(uniquePath))
    }))

    // then
    await expect { try await mocked.deleteFile(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteFile_givenFileExistsAndIsNotDirectoryAndError_shouldThrow() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true

    }))
    await mocked.mock(closure: .removeItem({ [uniquePath, uniqueError] path in
      expect(path).to(equal(uniquePath))

      throw uniqueError!
    }))

    // then
    await expect { try await mocked.deleteFile(atPath: self.uniquePath) }.to(throwError(self.uniqueError))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteFile_givenFileDoesNotExistAndIsDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false
    }))

    // then
    await expect { try await mocked.deleteFile(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteFile_givenFileDoesNotExistAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false
    }))

    // then
    await expect { try await mocked.deleteFile(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteDirectory_givenFileExistsAndIsDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))
    await mocked.mock(closure: .removeItem({ [uniquePath] path in
      expect(path).to(equal(uniquePath))
    }))

    // then
    await expect { try await mocked.deleteDirectory(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteDirectory_givenFileExistsAndIsDirectoryAndError_shouldThrow() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))
    await mocked.mock(closure: .removeItem({ [uniquePath, uniqueError] path in
      expect(path).to(equal(uniquePath))

      throw uniqueError!
    }))

    // then
    await expect { try await mocked.deleteDirectory(atPath: self.uniquePath) }.to(throwError(self.uniqueError))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteDirectory_givenFileExistsAndIsNotDirectory_shouldThrow() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true

    }))

    // then
    await expect { try await mocked.deleteDirectory(atPath: self.uniquePath) }
      .to(throwError(FileManagerPathError.notADirectory(path: self.uniquePath)))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteDirectory_givenFileDoesNotExistAndIsDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false
    }))

    // then
    await expect { try await mocked.deleteDirectory(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_deleteDirectory_givenFileDoesNotExistAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false
    }))

    // then
    await expect { try await mocked.deleteDirectory(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  // MARK: Creation

  func test_createFile_givenContainingDirectoryDoesExistAndFileCreated_shouldNotThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))
    let expectedPath = self.uniquePath
    let expectedData = self.uniqueData
    await mocked.mock(closure: .createFile({ path, data, attr in
      expect(path).to(equal(expectedPath))
      expect(data).to(equal(expectedData))
      expect(attr).to(beNil())

      return true

    }))

    // then
    await expect {
      try await mocked.createFile(atPath: self.uniquePath, data:self.uniqueData)
    }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createFile_givenContainingDirectoryDoesExistAndFileNotCreated_shouldThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))
    let expectedPath = self.uniquePath
    let expectedData = self.uniqueData
    await mocked.mock(closure: .createFile({ path, data, attr in
      expect(path).to(equal(expectedPath))
      expect(data).to(equal(expectedData))
      expect(attr).to(beNil())

      return false

    }))

    // then
    await expect {
      try await mocked.createFile(atPath: self.uniquePath, data:self.uniqueData)
    }.to(throwError(FileManagerPathError.cannotCreateFile(at: self.uniquePath)))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createFile_givenContainingDirectoryDoesNotExistAndFileCreated_shouldNotThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false

    }))
    let expectedPath = self.uniquePath
    let expectedData = self.uniqueData
    await mocked.mock(closure: .createFile({ path, data, attr in
      expect(path).to(equal(expectedPath))
      expect(data).to(equal(expectedData))
      expect(attr).to(beNil())

      return true

    }))
    await mocked.mock(closure: .createDirectory({ path, createIntermediates, attr in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attr).to(beNil())
    }))

    // then
    await expect {
      try await mocked.createFile(atPath: self.uniquePath, data:self.uniqueData)
    }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createFile_givenContainingDirectoryDoesNotExistAndFileNotCreated_shouldThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false

    }))
    let expectedPath = self.uniquePath
    let expectedData = self.uniqueData
    await mocked.mock(closure: .createFile({ path, data, attr in
      expect(path).to(equal(expectedPath))
      expect(data).to(equal(expectedData))
      expect(attr).to(beNil())

      return false

    }))
    await mocked.mock(closure: .createDirectory({ path, createIntermediates, attr in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attr).to(beNil())
    }))

    // then
    await expect {
      try await mocked.createFile(atPath: self.uniquePath, data:self.uniqueData)
    }.to(throwError(FileManagerPathError.cannotCreateFile(at: self.uniquePath)))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createFile_givenContainingDirectoryDoesNotExistAndError_shouldThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false

    }))
    await mocked.mock(closure: .createDirectory({ [uniqueError] path, createIntermediates, attr in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attr).to(beNil())

      throw uniqueError!
    }))

    // then
    await expect{
      try await mocked.createFile(atPath: self.uniquePath, data:self.uniqueData)
    }.to(throwError(self.uniqueError))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createFile_givenOverwriteFalse_whenFileExists_shouldNotThrow_shouldNotOverwrite() async throws {
    // given
    let filePath = URL(fileURLWithPath: self.uniquePath).path
    let directoryPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager(strict: true, requireAllClosuresCalled: false)

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      switch path {
      case directoryPath: isDirectory?.pointee = true
      case filePath: isDirectory?.pointee = false
      default: fail("Unknown path - \(path)")
      }

      return true

    }))
    await mocked.mock(closure: .createFile({ path, data, attr in
      fail("Tried to create file when overwrite was false")

      return false
    }))

    // then
    await expect {
      try await mocked.createFile(
        atPath: self.uniquePath,
        data:self.uniqueData,
        overwrite: false
      )
    }.notTo(throwError())
  }

  func test_createContainingDirectory_givenFileExistsAndIsDirectory_shouldReturnEarly() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))

    // then
    await expect { try await mocked.createContainingDirectoryIfNeeded(forPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createContainingDirectory_givenFileExistsAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true

    }))
    await mocked.mock(closure: .createDirectory({ path, createIntermediates, attributes in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createContainingDirectoryIfNeeded(forPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createContainingDirectory_givenFileDoesNotExistAndIsDirectory_shouldSucceed() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false

    }))
    await mocked.mock(closure: .createDirectory({ path, createIntermediates, attributes in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createContainingDirectoryIfNeeded(forPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createContainingDirectory_givenFileDoesNotExistAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false

    }))
    await mocked.mock(closure: .createDirectory({ path, createIntermediates, attributes in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createContainingDirectoryIfNeeded(forPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createContainingDirectory_givenError_shouldThrow() async throws {
    // given
    let parentPath = URL(fileURLWithPath: self.uniquePath).deletingLastPathComponent().path
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ path, isDirectory in
      expect(path).to(equal(parentPath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false

    }))
    await mocked.mock(closure: .createDirectory({ [uniqueError] path, createIntermediates, attributes in
      expect(path).to(equal(parentPath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())

      throw uniqueError!
    }))

    // then
    await expect { try await mocked.createContainingDirectoryIfNeeded(forPath: self.uniquePath) }
      .to(throwError(self.uniqueError))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createDirectory_givenFileExistsAndIsDirectory_shouldReturnEarly() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return true

    }))

    // then
    await expect { try await mocked.createDirectoryIfNeeded(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createDirectory_givenFileExistsAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return true

    }))
    await mocked.mock(closure: .createDirectory({ [uniquePath] path, createIntermediates, attributes in
      expect(path).to(equal(uniquePath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createDirectoryIfNeeded(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createDirectory_givenFileDoesNotExistAndIsDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = true
      return false

    }))
    await mocked.mock(closure: .createDirectory({ [uniquePath] path, createIntermediates, attributes in
      expect(path).to(equal(uniquePath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createDirectoryIfNeeded(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createDirectory_givenFileDoesNotExistAndIsNotDirectory_shouldSucceed() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false

    }))
    await mocked.mock(closure: .createDirectory({ [uniquePath] path, createIntermediates, attributes in
      expect(path).to(equal(uniquePath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())
    }))

    // then
    await expect { try await mocked.createDirectoryIfNeeded(atPath: self.uniquePath) }.notTo(throwError())
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }

  func test_createDirectory_givenError_shouldThrow() async throws {
    // given
    let mocked = MockApolloFileManager()

    await mocked.mock(closure: .fileExists({ [uniquePath] path, isDirectory in
      expect(path).to(equal(uniquePath))
      expect(isDirectory).notTo(beNil())

      isDirectory?.pointee = false
      return false

    }))
    await mocked.mock(closure: .createDirectory({ [uniquePath, uniqueError] path, createIntermediates, attributes in
      expect(path).to(equal(uniquePath))
      expect(createIntermediates).to(beTrue())
      expect(attributes).to(beNil())

      throw uniqueError!
    }))

    // then
    await expect { try await mocked.createDirectoryIfNeeded(atPath: self.uniquePath) }
      .to(throwError(self.uniqueError))
    await expect { await mocked.allClosuresCalled }.to(beTrue())
  }
}
