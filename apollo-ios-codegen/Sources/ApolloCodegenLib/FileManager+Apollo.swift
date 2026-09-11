import Foundation

public typealias FileAttributes = [FileAttributeKey : Any]

@globalActor public actor FileManagerActor: GlobalActor {
  public static let shared = FileManagerActor()
}

@FileManagerActor
public class ApolloFileManager {

  public nonisolated static let `default` = ApolloFileManager(base: FileManager.default)

  public let base: FileManager

  /// The paths for the files written to by the ``ApolloFileManager``.
  public var writtenFiles: Set<String> = []

  nonisolated init(base: FileManager) {
    self.base = base
  }

  // MARK: Presence

  /// Checks if the path exists and is a file, not a directory.
  ///
  /// - Parameter path: The path to check.
  /// - Returns: `true` if there is something at the path and it is a file, not a directory.
  public func doesFileExist(atPath path: String) -> Bool {
    var isDirectory = ObjCBool(false)
    let exists = base.fileExists(atPath: path, isDirectory: &isDirectory)

    return exists && !isDirectory.boolValue
  }

  /// Checks if the path exists and is a directory, not a file.
  ///
  /// - Parameter path: The path to check.
  /// - Returns: `true` if there is something at the path and it is a directory, not a file.
  public func doesDirectoryExist(atPath path: String) -> Bool {
    var isDirectory = ObjCBool(false)
    let exists = base.fileExists(atPath: path, isDirectory: &isDirectory)

    return exists && isDirectory.boolValue
  }
  
  // MARK: Manipulation

  /// Verifies that a file exists at the path and then attempts to delete it. An error is thrown if the path is for a directory.
  ///
  /// - Parameter path: The path of the file to delete.
  public func deleteFile(atPath path: String) throws {
    var isDirectory = ObjCBool(false)
    let exists = base.fileExists(atPath: path, isDirectory: &isDirectory)

    if exists && isDirectory.boolValue {
      throw FileManagerPathError.notAFile(path: path)
    }

    guard exists else { return }
    try base.removeItem(atPath: path)
  }

  /// Verifies that a directory exists at the path and then attempts to delete it. An error is thrown if the path is for a file.
  ///
  /// - Parameter path: The path of the directory to delete.
  public func deleteDirectory(atPath path: String) throws {
    var isDirectory = ObjCBool(false)
    let exists = base.fileExists(atPath: path, isDirectory: &isDirectory)

    if exists && !isDirectory.boolValue {
      throw FileManagerPathError.notADirectory(path: path)
    }

    guard exists else { return }
    try base.removeItem(atPath: path)
  }

  /// Creates a file at the specified path and writes any given data to it. If a file already exists at `path` this
  /// method can be configured to overwrite the contents of that file, if the current process has the appropriate
  /// privileges to do so.
  ///
  /// - Parameters:
  ///   - path: Path to the file.
  ///   - data: [optional] Data to write to the file path.
  ///   - overwrite: Indicates if the contents of an existing file should be overwritten.
  ///       If `false` the function will exit without writing the file if it already exists.
  ///       This will not throw an error.
  ///       Defaults to `false.
  ///
  /// On a case-insensitive volume, overwriting an existing file whose on-disk name differs from
  /// `path` only by case first renames the file so its directory entry adopts the casing of
  /// `path`.
  public func createFile(atPath path: String, data: Data? = nil, overwrite: Bool = true) throws {
    try createContainingDirectoryIfNeeded(forPath: path)

    if !overwrite && doesFileExist(atPath: path) { return }

    adoptFileNameCasingIfNeeded(atPath: path)

    guard base.createFile(atPath: path, contents: data, attributes: nil) else {
      throw FileManagerPathError.cannotCreateFile(at: path)
    }
    writtenFiles.insert(path)
  }

  public func renameFile(atPath oldPath: String, toPath newPath: String) throws {
    guard doesFileExist(atPath: oldPath) else { return }

    try base.moveItem(atPath: oldPath, toPath: newPath)

    writtenFiles.insert(newPath)
  }

  // MARK: Case Sensitivity

  private var volumeCaseSensitivityCache: [String: Bool] = [:]

  /// Queries whether the volume containing the given directory treats file names that differ
  /// only by case as distinct files, or `nil` when this cannot be determined.
  /// Replaceable in tests to simulate volume behavior deterministically.
  var volumeCaseSensitivityProvider: @Sendable (_ directoryPath: String) -> Bool? = {
    directoryPath in
    let resourceValues = try? URL(fileURLWithPath: directoryPath, isDirectory: true)
      .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
    return resourceValues?.volumeSupportsCaseSensitiveNames
  }

  /// Queries the canonical path for an existing file, with the on-disk casing of its name, or
  /// `nil` when this cannot be determined.
  /// Replaceable in tests to simulate volume behavior deterministically.
  var onDiskCasedPathProvider: @Sendable (_ path: String) -> String? = { path in
    let resourceValues = try? URL(fileURLWithPath: path)
      .resourceValues(forKeys: [.canonicalPathKey])
    return resourceValues?.canonicalPath
  }

  /// Whether the volume containing `path` treats file names that differ only by case as
  /// distinct files.
  ///
  /// Returns `nil` when the volume's capability cannot be determined; callers must choose the
  /// failure mode that is safe for their operation.
  func volumeSupportsCaseSensitiveNames(forPath path: String) -> Bool? {
    let directoryPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
    if let cached = volumeCaseSensitivityCache[directoryPath] { return cached }

    guard let isCaseSensitive = volumeCaseSensitivityProvider(directoryPath) else { return nil }

    volumeCaseSensitivityCache[directoryPath] = isCaseSensitive
    return isCaseSensitive
  }

  /// The canonical path for an existing file, with the on-disk casing of its name, or `nil` if
  /// it cannot be determined.
  func onDiskCasedPath(forPath path: String) -> String? {
    onDiskCasedPathProvider(path)
  }

  /// On a case-insensitive volume, writing to a path whose on-disk file name differs only by
  /// case would update the file's contents while keeping the old directory entry name. This
  /// renames the file first so the directory entry adopts the casing of `path`.
  ///
  /// Skipped when the volume's case sensitivity cannot be determined — a stale directory entry
  /// name is preferable to renaming on an unknown file system.
  func adoptFileNameCasingIfNeeded(atPath path: String) {
    guard
      volumeSupportsCaseSensitiveNames(forPath: path) == false,
      let onDiskPath = onDiskCasedPath(forPath: path)
    else { return }

    let onDiskName = URL(fileURLWithPath: onDiskPath).lastPathComponent
    let targetName = URL(fileURLWithPath: path).lastPathComponent
    guard
      onDiskName != targetName,
      onDiskName.caseInsensitiveCompare(targetName) == .orderedSame
    else { return }

    do {
      try base.moveItem(atPath: onDiskPath, toPath: path)
    } catch {
      CodegenLogger.log(
        "Unable to rename \(onDiskPath) to adopt the casing of \(targetName): \(error)",
        logLevel: .warning
      )
    }
  }

  /// Creates the containing directory (including all intermediate directories) for the given file URL if necessary.
  /// This method will not overwrite any existing directory.
  ///
  /// - Parameter fileURL: The URL of the file to create a containing directory for if necessary.
  public func createContainingDirectoryIfNeeded(forPath path: String) throws {
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
    try createDirectoryIfNeeded(atPath: parent.path)
  }

  /// Creates the directory (including all intermediate directories) for the given URL if necessary. This method will
  /// not overwrite any existing directory.
  ///
  /// - Parameter path: The path of the directory to create if necessary.
  public func createDirectoryIfNeeded(atPath path: String) throws {
    if doesDirectoryExist(atPath: path) { return }
    try base.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
  }
}

// MARK: - FileManagerPathError

public enum FileManagerPathError: Swift.Error, LocalizedError, Equatable {
  case notAFile(path: String)
  case notADirectory(path: String)
  case cannotCreateFile(at: String)

  public var errorDescription: String {
    switch self {
    case .notAFile(let path):
      return "\(path) is not a file!"
    case .notADirectory(let path):
      return "\(path) is not a directory!"
    case .cannotCreateFile(let path):
      return "Cannot create file at \(path)"
    }
  }
}

extension FileManager: @retroactive @unchecked Sendable {}
