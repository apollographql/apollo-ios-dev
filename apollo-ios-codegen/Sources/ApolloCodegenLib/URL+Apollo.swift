import Foundation

public enum ApolloURLError: Swift.Error, LocalizedError {
  case fileNameIsEmpty
  
  public var errorDescription: String? {
    switch self {
    case .fileNameIsEmpty:
      return "The file name for this file URL was empty. Please pass a non-empty string."
    }
  }
}

extension URL {

  /// The canonical form of a file path. Every path that is written, recorded as written, or
  /// compared against another path during code generation must go through this property so that
  /// differently spelled paths to the same file (symlinks, `.`/`..` components, relative paths)
  /// are equal.
  ///
  /// Symlinks are resolved in the directory containing the file, including when that directory
  /// does not exist yet. The file name is preserved exactly as given.
  var normalizedFilePath: String {
    let url = standardizedFileURL
    guard url.path != "/" else { return url.path }

    return url.deletingLastPathComponent()
      .resolvingSymlinksInExistingPath()
      .appendingPathComponent(url.lastPathComponent)
      .path
  }

  /// The path to a file that exists on disk with all symlinks resolved, including a symlink at the
  /// file itself. Used for files found by searching the file system.
  var symlinkResolvedFilePath: String {
    resolvingSymlinksInPath().path
  }

  private func resolvingSymlinksInExistingPath() -> URL {
    var existingURL = self
    var missingComponents: [String] = []

    while existingURL.path != "/" && !FileManager.default.fileExists(atPath: existingURL.path) {
      missingComponents.insert(existingURL.lastPathComponent, at: 0)
      existingURL.deleteLastPathComponent()
    }

    return missingComponents.reduce(existingURL.resolvingSymlinksInPath()) {
      $0.appendingPathComponent($1)
    }
  }

  /// Determines if the URL passed in is a directory URL.
  ///
  /// NOTE: Only works if something at the URL already exists.
  ///
  /// - Returns: True if the URL is a directory URL, false if it isn't.
  var isDirectoryURL: Bool {
    guard
      let resourceValues = try? resourceValues(forKeys: [.isDirectoryKey]),
      let isDirectory = resourceValues.isDirectory else {
        return false
    }
    
    return isDirectory
  }
  
  var isSwiftFileURL: Bool {
    pathExtension == "swift"
  }
  
  /// - Returns: the URL to the parent folder of the current URL.
  public func parentFolderURL() -> URL {
    deletingLastPathComponent()
  }
  
  /// - Parameter folderName: The name of the child folder to append to the current URL
  /// - Returns: The full URL including the appended child folder.
  public func childFolderURL(folderName: String) -> URL {
    appendingPathComponent(folderName, isDirectory: true)
  }

  /// Adds the filename to the caller to get the full URL of a file
  ///
  /// - Parameters:
  ///   - fileName: The name of the child file, with an extension, for example `"API.swift"`. Note: For hidden files just pass `".filename"`.
  /// - Returns: The full URL including the full file.
  public func childFileURL(fileName: String) throws -> URL {
    guard !fileName.isEmpty else {
      throw ApolloURLError.fileNameIsEmpty
    }
    
    return appendingPathComponent(fileName, isDirectory: false)
  }
}

extension String {

  /// The canonical form of this file path. See `URL.normalizedFilePath`.
  var normalizedFilePath: String {
    URL(fileURLWithPath: self).normalizedFilePath
  }

  /// The canonical form of this file path with a symlink at the file itself also resolved. See
  /// `URL.symlinkResolvedFilePath`.
  var symlinkResolvedFilePath: String {
    URL(fileURLWithPath: self).symlinkResolvedFilePath
  }
}
