/// A dotted-decimal version tag for the SQLite records-table layout.
///
/// `major` typically aligns with the Apollo iOS major release that introduces
/// a schema change; `minor` allows for incremental schema iterations within
/// the same major release. Ordering is lexicographic over `(major, minor)`.
///
/// The on-disk representation is the `description` string (`"M.m"`),
/// stored as TEXT in the `schema_metadata` table.
public struct SchemaVersion: Sendable, Hashable, Comparable, CustomStringConvertible {

  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int = 0) {
    self.major = major
    self.minor = minor
  }

  /// Parses a string formatted as `"M.m"` or `"M"`. Returns `nil` for malformed
  /// input. A bare integer (`"3"`) is treated as `"3.0"` so older stamps that
  /// omitted the minor component still load.
  public init?(_ rawValue: String) {
    let majorPart: Substring
    let minorPart: Substring
    if let dot = rawValue.firstIndex(of: ".") {
      majorPart = rawValue[..<dot]
      minorPart = rawValue[rawValue.index(after: dot)...]
    } else {
      majorPart = Substring(rawValue)
      minorPart = "0"
    }

    guard let major = Int(majorPart), let minor = Int(minorPart) else {
      return nil
    }
    self.major = major
    self.minor = minor
  }

  public var description: String {
    "\(major).\(minor)"
  }

  public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    return lhs.minor < rhs.minor
  }
}
