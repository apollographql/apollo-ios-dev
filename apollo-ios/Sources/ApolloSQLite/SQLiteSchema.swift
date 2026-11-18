/// Compile-time constants for the SQLite cache database schema.
///
/// Grouped to make table boundaries explicit and to avoid free-floating
/// static properties on `SQLiteDatabase`. The two records-table layouts
/// share a physical table name (`recordsTableName`); only the column set
/// differs.
public enum SQLiteSchema {

  /// The records-table schema version that this build of Apollo iOS reads
  /// and writes. Stamped into `Metadata` on a fresh database; consulted by
  /// later openers to decide whether the on-disk layout needs to be
  /// migrated to the current shape.
  public static var currentVersion: SchemaVersion {
    SchemaVersion(major: 3, minor: 0)
  }

  /// Shared physical name of the records table across both layouts.
  public static let recordsTableName = "records"

  /// Columns for the row-per-element records-table layout.
  public enum Records {
    public static let cacheKey = "cache_key"
    public static let fieldName = "field_name"
    /// `-1` for non-list rows (a scalar field, a cache reference, or any
    /// other field that occupies a single row), `0..N-1` for the
    /// elements of a list-typed field. Part of the primary key, so
    /// `(cache_key, field_name)` is no longer unique on its own — see
    /// `defaultPositionValue`.
    public static let position = "position"
    public static let intValue = "int_value"
    public static let stringValue = "string_value"
    public static let floatValue = "float_value"
    public static let boolValue = "bool_value"
    public static let childKeyValue = "child_key_value"
    public static let customScalarValue = "custom_scalar_value"
    public static let writtenAt = "written_at"

    /// The `position` value for any row that does not represent a list
    /// element — scalars and cache references both occupy a single row
    /// at this position. Matches the column's DDL `DEFAULT -1` so
    /// writes that omit `position` still land in the right row.
    public static let defaultPositionValue: Int64 = -1
  }

  /// Columns for the legacy single-row JSON-blob records-table layout used
  /// by pre-3.0 Apollo iOS caches. Still referenced while migration support
  /// from older caches lives in the SQLite layer.
  public enum LegacyRecords {
    public static let id = "_id"
    public static let key = "key"
    public static let record = "record"
  }

  /// Names and columns for the `schema_metadata` key/value table.
  public enum Metadata {
    public static let tableName = "schema_metadata"
    public static let keyColumn = "key"
    public static let valueColumn = "value"
    public static let versionKey = "version"
  }
}
