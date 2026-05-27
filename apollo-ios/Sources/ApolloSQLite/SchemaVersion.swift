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
    let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let parsedMajor = Int(parts[0]) else { return nil }

    if parts.count == 1 {
      self.major = parsedMajor
      self.minor = 0
    } else {
      guard let parsedMinor = Int(parts[1]) else { return nil }
      self.major = parsedMajor
      self.minor = parsedMinor
    }
  }

  public var description: String {
    "\(major).\(minor)"
  }

  public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    return lhs.minor < rhs.minor
  }
}
