import Foundation
@testable import ApolloCodegenLib
import XCTest

/// Used to mock a `FileManager` instance that is compatible with the `.apollo` namespace extension.
public class MockApolloFileManager: ApolloFileManager {
  /// Translates to the `FileManager` functions that can be mocked.
  public enum Closure: CustomStringConvertible {
    case fileExists(_ handler: @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool)
    case removeItem(_ handler: @Sendable (String) throws -> Void)
    case createFile(_ handler: @Sendable (String, Data?, FileAttributes?) -> Bool)
    case createDirectory(_ handler: @Sendable (String, Bool, FileAttributes?) throws -> Void)

    // These are based on the return string from the #function macro. They are used in overriden
    // functions to lookup the provided closure. Be aware that if the function signature changes
    // these should be updated so the mocked closures can still be looked up.
    public var description: String {
      switch self {
      case .fileExists(_): return "fileExists(atPath:isDirectory:)"
      case .removeItem(_): return "removeItem(atPath:)"
      case .createFile(_): return "createFile(atPath:contents:attributes:)"
      case .createDirectory(_): return "createDirectory(atPath:withIntermediateDirectories:attributes:)"
      }
    }
  }

  /// If `true` then any function on the file manager called that is not mocked will
  ///  result in a test failure. If `false`, any called closure that is not mocked will fall
  ///  through to `super`. Defaults to `true`.
  var strict: Bool { _base.strict }

  /// If `true` all mocked closures must be called otherwise the test
  ///  will fail. Defaults to `true`.
  var requireAllClosuresCalled: Bool { _base.requireAllClosuresCalled }

  var _base: MockFileManager { unsafeDowncast(base, to: MockFileManager.self) }

  /// Designated initializer.
  ///
  /// - Parameters:
  ///  - strict: If `true` then any function on the file manager called that is not mocked will
  ///  result in a test failure. If `false`, any called closure that is not mocked will fall
  ///  through to `super`. Defaults to `true`.
  ///  - requireAllClosuresCalled: If `true` all mocked closures must be called otherwise the test
  ///  will fail. Defaults to `true`.
  public nonisolated init(
    strict: Bool = true,
    requireAllClosuresCalled: Bool = true
  ) {
    super.init(base: MockFileManager(
      strict: strict,
      requireAllClosuresCalled: requireAllClosuresCalled
    ))
  }

  /// Provide a mock closure for the `FileManager` function.
  ///
  /// - Parameter closure: The mocked function closure.
  public func mock(closure: Closure) {
    _base.mock(closure: closure)
  }

  private func didCall(closure: Closure) {
    _base.closuresToBeCalled.remove(closure.description)
  }

  /// Check whether all mocked closures were called during the lifetime of an instance.
  public var allClosuresCalled: Bool {
    return _base.closuresToBeCalled.isEmpty
  }

  class MockFileManager: FileManager, @unchecked Sendable {

    private let lock = NSLock()

    fileprivate var closures: [String: Closure] = [:]
    fileprivate var closuresToBeCalled: Set<String> = []

    let strict: Bool

    let requireAllClosuresCalled: Bool

    fileprivate init(
      strict: Bool = true,
      requireAllClosuresCalled: Bool = true
    ) {
      self.strict = strict
      self.requireAllClosuresCalled = requireAllClosuresCalled
    }

    deinit {
      if requireAllClosuresCalled && !allClosuresCalled {
        XCTFail("`requireAllClosuresCalled` is `true`, but not all mocked closures are called! Check \(closuresToBeCalled) in your MockFileManager instance.")
      }
    }

    /// Provide a mock closure for the `FileManager` function.
    ///
    /// - Parameter closure: The mocked function closure.
    fileprivate func mock(closure: Closure) {
      lock.withLock {
        closures[closure.description] = closure
        closuresToBeCalled.insert(closure.description)
      }
    }

    fileprivate func didCall(closure: Closure) {
      lock.withLock {
        _ = closuresToBeCalled.remove(closure.description)
      }
    }

    /// Check whether all mocked closures were called during the lifetime of an instance.
    fileprivate var allClosuresCalled: Bool {
      return lock.withLock {
        return closuresToBeCalled.isEmpty
      }
    }

    // MARK: FileManager overrides

    private func missingClosureMessage(_ function: String) -> String {
      return "\(function) closure must be mocked before calling it! Check your MockFileManager instance."
    }

    public override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
      let key = #function

      guard
        let closure = closures[key],
        case let .fileExists(handler) = closure else {
        if strict {
          XCTFail(missingClosureMessage(key))
          return false
        } else {
          return super.fileExists(atPath: path, isDirectory: isDirectory)
        }
      }

      defer {
        didCall(closure: closure)
      }

      return handler(path, isDirectory)
    }

    public override func removeItem(atPath path: String) throws {
      let key = #function

      guard
        let closure = closures[key],
        case let .removeItem(handler) = closure else {
        if strict {
          XCTFail(missingClosureMessage(key))
          return
        } else {
          return try super.removeItem(atPath: path)
        }
      }

      defer {
        didCall(closure: closure)
      }

      try handler(path)
    }

    public override func createFile(atPath path: String, contents data: Data?, attributes attr: FileAttributes?) -> Bool {
      let key = #function

      guard
        let closure = closures[key],
        case let .createFile(handler) = closure else {
        if strict {
          XCTFail(missingClosureMessage(key))
          return false
        } else {
          return super.createFile(atPath: path, contents: data, attributes: attr)
        }
      }

      defer {
        didCall(closure: closure)
      }

      return handler(path, data, attr)
    }

    public override func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: FileAttributes?) throws {
      let key = #function

      guard
        let closure = closures[key],
        case let .createDirectory(handler) = closure else {
        if strict {
          XCTFail(missingClosureMessage(key))
          return
        } else {
          return try super.createDirectory(
            atPath: path,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
          )
        }
      }

      defer {
        didCall(closure: closure)
      }

      try handler(path, createIntermediates, attributes)
    }
  }
}
