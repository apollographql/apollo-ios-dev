import Foundation

/// Helper to get logs printing to stdout so they can be read from the command line.
enum PaginationLogger {
  enum LogLevel: Int {
    case error
    case warning
    case debug

    var name: String {
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
    _ logString: @autoclosure () -> String,
    logLevel: LogLevel = .debug,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard logLevel.rawValue <= PaginationLogger.level.rawValue else { return }

    let standardOutput = FileHandle.standardOutput
    let string = "[\(logLevel.name) - ApolloPagination:\(file.lastPathComponent):\(line)] - \(logString())"
    guard let data = string.data(using: .utf8) else { return }
    standardOutput.write(data)
  }
}

private extension StaticString {
  var lastPathComponent: String {
    return (description as NSString).lastPathComponent
  }
}
