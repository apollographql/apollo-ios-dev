import Foundation
import os

/// Helper to get logs printing to stdout so they can be read from the command line.
enum PaginationLogger {
  @available(macOS 11.0, *)
  private static let logger = Logger()
  enum LogLevel: Hashable, CustomStringConvertible, Comparable {
    case error
    case warning
    case debug

    var description: String {
      switch self {
      case .error:
        return "ERROR"
      case .warning:
        return "WARNING"
      case .debug:
        return "DEBUG"
      }
    }
  }

  /// The `LogLevel` at which to print logs. Higher raw values than this will
  /// be ignored. Defaults to `debug`.
  static var level = LogLevel.debug

  /// Logs the given string if its `logLevel` is at or above `PaginationLogger.level`, otherwise ignores it.
  ///
  /// - Parameter logString: The string to log out, as an autoclosure
  /// - Parameter logLevel: The log level at which to print this specific log. Defaults to `debug`.
  /// - Parameter file: The file where this function was called. Defaults to the direct caller.
  /// - Parameter line: The line where this function was called. Defaults to the direct caller.
  static func log(
    _ logString: @autoclosure @escaping () -> String,
    logLevel: LogLevel = .debug,
    file: StaticString = #fileID,
    line: UInt = #line
  ) {
    guard logLevel <= PaginationLogger.level else { return }
    if #available(macOS 11.0, iOS 14.0, iOSApplicationExtension 14.0, tvOS 14.0, watchOS 7.0, *) {
      logger.debug("[\(logLevel) - ApolloPagination:\(file):\(line)] - \(logString())")
    } else {
      os_log(
        "[%@ - ApolloPagination:%@:%@] - %@)",
        log: .default,
        type: .debug,
        logLevel.description, file.description, line, logString()
      )
    }
  }
}
