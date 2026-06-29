import ApolloAPI

/// A request to read one field's value(s) from one record in the
/// normalized cache, carrying enough type information for any
/// `NormalizedCache` implementation to fulfill the request without
/// re-deriving it from a `Selection.Field`.
///
/// `FieldProjection` is the value-type expression of ADR 0007's
/// selection-set-aware cache reads. The executor builds projections
/// upfront by traversing the selection set; the cache fulfills the
/// projections in one batched read. For the SQLite-backed cache
/// (per ADR 0006's row-per-element schema), `columnShape` tells the
/// read which of the six typed value columns to project and
/// `cardinality` tells it whether to expect one row at the default
/// `position` value (`-1`) or N rows at `position = 0..N-1`. For
/// the in-memory cache, the same information identifies the entry
/// to return.
///
/// This PR introduces the type only; no consumers exist yet. The
/// `NormalizedCache` protocol change to accept `[FieldProjection]`
/// is the next PR in sub-phase 1A.5 (PR-009c per ADR 0007).
///
/// # See Also
///
/// - [ADR 0007 — Selection-set-aware cache reads](../Design/adr/0007-selection-aware-cache-reads.md)
/// - [ADR 0006 — List storage strategy](../Design/adr/0006-list-storage-strategy.md)
@_spi(Execution)
public struct FieldProjection: Hashable, Sendable {

  /// The cache key of the record whose field is being read.
  public let cacheKey: CacheKey

  /// The name of the field on that record. Matches the storage-
  /// layer `field_name` column verbatim; aliasing is applied
  /// upstream of the projection by the executor (the projection
  /// carries the storage field name, not the response key).
  public let fieldName: String

  /// The SQLite typed-column slot the field's value(s) occupy on
  /// each stored row. See `ColumnShape` for the mapping rules.
  public let columnShape: ColumnShape

  /// `.scalar` if the field is stored as a single row at the default
  /// `position` value (`-1`); `.list` if the field is stored as N
  /// rows at `position = 0..N-1`. See `Cardinality` for details.
  public let cardinality: Cardinality

  /// Primary initializer used by the executor. Classifies a
  /// `Selection.Field.OutputType` into the projection's `columnShape`
  /// and `cardinality` at construction time. The OutputType itself
  /// is not retained — once classified, the projection's
  /// `(cacheKey, fieldName, columnShape, cardinality)` is everything
  /// any planned consumer needs (see ADR 0007 §implementation
  /// sequence). The executor keeps its own `Selection.Field` tree
  /// alongside the projections it issues for decoding return values
  /// into Swift types and for driving follow-up projections; the
  /// cache layer detects synthetic-vs-real `child_key_value` pointers
  /// at read time via the `.$[N]` suffix pattern established in
  /// PR #1007.
  public init(
    cacheKey: CacheKey,
    fieldName: String,
    outputType: Selection.Field.OutputType
  ) {
    self.init(
      cacheKey: cacheKey,
      fieldName: fieldName,
      columnShape: Self.columnShape(of: outputType),
      cardinality: Self.cardinality(of: outputType)
    )
  }

  /// Direct initializer for callers that build projections from
  /// non-`Selection.Field` sources — most importantly the
  /// dependency tracker (PR-009f), whose watcher dirty-set entries
  /// arrive as `(cacheKey, fieldName)` pairs without a wrapping
  /// `Selection.Field` in scope, and tests that exercise
  /// projection-driven behavior without a full selection set.
  ///
  /// Production code paths that have a `Selection.Field.OutputType`
  /// in hand should prefer the `outputType:` initializer so column-
  /// shape and cardinality classification stay in one place.
  public init(
    cacheKey: CacheKey,
    fieldName: String,
    columnShape: ColumnShape,
    cardinality: Cardinality
  ) {
    self.cacheKey = cacheKey
    self.fieldName = fieldName
    self.columnShape = columnShape
    self.cardinality = cardinality
  }

  // MARK: - Output-type classification

  /// The SQLite typed-column slot a field's value occupies. One of
  /// the six value columns introduced by the row-per-element schema
  /// (ADR 0006); the other five columns are `NULL` on every row.
  ///
  /// The mapping from a `Selection.Field.OutputType` is determined
  /// by the type's *named* type — its innermost form, after peeling
  /// off `.nonNull` and `.list` wrappers:
  ///
  /// | Named type            | ColumnShape     | Storage column        |
  /// |---|---|---|
  /// | `String`              | `.string`       | `string_value`        |
  /// | `Int`, `Int32`        | `.int`          | `int_value`           |
  /// | `Bool`                | `.bool`         | `bool_value`          |
  /// | `Float`, `Double`     | `.float`        | `float_value`         |
  /// | `.object(_)`          | `.childKey`     | `child_key_value`     |
  /// | `.customScalar(_)`    | `.customScalar` | `custom_scalar_value` |
  ///
  /// ## Custom scalars and the precise-column TODO
  ///
  /// All `.customScalar(T)` cases currently route to
  /// `.customScalar` regardless of `T`'s `_jsonValue` shape. The
  /// codegen-default custom scalar (`struct ScalarName:
  /// CustomScalarType { let value: String; var _jsonValue: ...
  /// { value } }`) unwraps to a `String` at write time via the
  /// normalizer's `accept(customScalar:)` path, and
  /// `SQLiteFieldEncoding` then writes that `String` into
  /// `string_value` — which means the read-side projection routing
  /// custom scalars to `.customScalar` will miss the value. This
  /// mismatch is harmless until PR-009g wires up SQL-level
  /// projection; it is the explicit subject of ADR 0007 Principle 7
  /// (custom scalars must declare their storage column) and is
  /// resolved by a follow-up PR that adds a static declaration on
  /// `CustomScalarType` (likely `_cacheStorageColumn`) and updates
  /// the codegen to emit it.
  ///
  /// This PR fixes the type system but defers the custom-scalar
  /// declaration mechanism to keep the scope narrow.
  public enum ColumnShape: Hashable, Sendable {
    case bool
    case int
    case float
    case string
    case childKey
    case customScalar
  }

  /// Whether a field is stored as one row (scalar) or N rows (list).
  /// In the row-per-element schema this maps to the `position`
  /// predicate of the read:
  ///
  /// - `.scalar` — the field has one row at the default `position`
  ///   value (`-1`). Read with `WHERE position = -1`.
  /// - `.list` — the field has N rows at `position = 0..N-1`.
  ///   Read with `WHERE position >= 0 ORDER BY position`.
  ///
  /// Nested-list output types (`[[T]]`) report `.list` because
  /// only the outer list is read by the initial projection; the
  /// inner list is materialized by issuing a follow-up
  /// `FieldProjection` against the synthetic sub-record the outer
  /// row's `child_key_value` points at (per ADR 0006 §3.2).
  public enum Cardinality: Hashable, Sendable {
    case scalar
    case list
  }

  /// Classifies `outputType` into the SQLite column slot the field's
  /// value(s) are stored in. See `ColumnShape` for the mapping
  /// rules.
  ///
  /// Nested lists (`[[T]]`, two or more `.list` wrappers) report
  /// `.childKey` regardless of the innermost named type, because
  /// the outer-list rows hold `child_key_value` pointers to
  /// synthetic sub-records that carry the inner list's elements
  /// (per ADR 0006 §3.2). The inner list's column shape is
  /// determined by a *follow-up* projection issued by the consumer
  /// against the synthetic sub-record.
  public static func columnShape(
    of outputType: Selection.Field.OutputType
  ) -> ColumnShape {
    if listNestingDepth(of: outputType) >= 2 {
      return .childKey
    }
    return columnShape(ofNamedType: peelToNamedType(outputType))
  }

  /// Returns `.scalar` if `outputType` has no `.list` wrapper at any
  /// nesting level, `.list` otherwise. `.nonNull` wrappers are
  /// transparent.
  ///
  /// Nested-list output types (`[[T]]`) return `.list` because only
  /// the outer list drives the initial projection's row predicate —
  /// the inner list is materialized via follow-up projections per
  /// `Cardinality`'s doc comment.
  public static func cardinality(
    of outputType: Selection.Field.OutputType
  ) -> Cardinality {
    switch outputType {
    case .list:
      return .list
    case .nonNull(let inner):
      return cardinality(of: inner)
    case .scalar, .customScalar, .object:
      return .scalar
    }
  }

  // MARK: - Output-type classification internals

  /// Returns the inner classification of `outputType` after peeling
  /// off every `.nonNull` and `.list` wrapper. The result is one of
  /// `.scalar`, `.customScalar`, or `.object`. A `Selection.Field.
  /// OutputType` constructed by codegen always bottoms out in one
  /// of these three cases.
  private static func peelToNamedType(
    _ outputType: Selection.Field.OutputType
  ) -> Selection.Field.OutputType {
    switch outputType {
    case .nonNull(let inner), .list(let inner):
      return peelToNamedType(inner)
    case .scalar, .customScalar, .object:
      return outputType
    }
  }

  /// Counts the number of `.list` wrappers in `outputType`'s
  /// wrapper chain. `.nonNull` wrappers are transparent. Used to
  /// distinguish a flat list (`[T]`, one `.list` wrapper) from a
  /// nested list (`[[T]]`, two or more) for column-shape routing.
  private static func listNestingDepth(
    of outputType: Selection.Field.OutputType
  ) -> Int {
    switch outputType {
    case .list(let inner):
      return 1 + listNestingDepth(of: inner)
    case .nonNull(let inner):
      return listNestingDepth(of: inner)
    case .scalar, .customScalar, .object:
      return 0
    }
  }

  /// Maps an already-peeled named type (the `.scalar`,
  /// `.customScalar`, or `.object` case) to its column slot.
  private static func columnShape(
    ofNamedType namedType: Selection.Field.OutputType
  ) -> ColumnShape {
    switch namedType {
    case .scalar(let scalarType):
      return columnShape(forBuiltInScalarType: scalarType)
    case .customScalar:
      // All custom scalars route to `.customScalar` for now; the
      // precise-per-scalar mapping is deferred to a follow-up PR
      // that adds a static declaration on `CustomScalarType` per
      // ADR 0007 Principle 7. See `ColumnShape`'s doc comment.
      return .customScalar
    case .object:
      return .childKey
    case .nonNull, .list:
      // Unreachable: `peelToNamedType` is the only caller path
      // and it strips every wrapper. Guard defensively.
      return .customScalar
    }
  }

  /// Maps a built-in `ScalarType` metatype to its column slot. The
  /// five GraphQL primitive scalars route to their typed columns;
  /// any other type would fall through to `.customScalar`, but
  /// codegen never emits a non-built-in metatype here (it uses the
  /// `.customScalar` case for those), so the fallthrough is
  /// defensive only.
  private static func columnShape(
    forBuiltInScalarType scalarType: any ScalarType.Type
  ) -> ColumnShape {
    if scalarType == String.self { return .string }
    if scalarType == Int.self || scalarType == Int32.self { return .int }
    if scalarType == Bool.self { return .bool }
    if scalarType == Float.self || scalarType == Double.self { return .float }
    return .customScalar
  }
}
