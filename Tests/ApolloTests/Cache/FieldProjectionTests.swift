@testable @_spi(Execution) import Apollo
@_spi(Internal) @_spi(Execution) import ApolloAPI
import ApolloInternalTestHelpers
import Foundation
import Nimble
import XCTest

final class FieldProjectionTests: XCTestCase {

  // MARK: - Construction via outputType initializer

  func test__init_outputType__classifiesColumnShapeAndCardinality() {
    let projection = FieldProjection(
      cacheKey: "User:42",
      fieldName: "name",
      outputType: .nonNull(.scalar(String.self))
    )
    expect(projection.cacheKey) == "User:42"
    expect(projection.fieldName) == "name"
    expect(projection.columnShape) == .string
    expect(projection.cardinality) == .scalar
  }

  func test__init_outputType__nonNullWrappingDoesNotAffectClassification() {
    // `String?` and `String!` both project the same column with the
    // same cardinality; only the wrapper differs. After classification,
    // the projections must be indistinguishable.
    let optional = FieldProjection(
      cacheKey: "User:1",
      fieldName: "nickname",
      outputType: .scalar(String.self)
    )
    let nonNull = FieldProjection(
      cacheKey: "User:1",
      fieldName: "nickname",
      outputType: .nonNull(.scalar(String.self))
    )
    expect(optional) == nonNull
  }

  // MARK: - Construction via direct initializer

  func test__init_columnShapeAndCardinality__storesArgumentsVerbatim() {
    let projection = FieldProjection(
      cacheKey: "User:1",
      fieldName: "tags",
      columnShape: .string,
      cardinality: .list
    )
    expect(projection.cacheKey) == "User:1"
    expect(projection.fieldName) == "tags"
    expect(projection.columnShape) == .string
    expect(projection.cardinality) == .list
  }

  func test__init_columnShapeAndCardinality__matchesEquivalentOutputTypeInit() {
    // Building a projection via the direct initializer with the same
    // (columnShape, cardinality) as the outputType-derived classification
    // produces equal projections — the two paths are interchangeable.
    let direct = FieldProjection(
      cacheKey: "User:1",
      fieldName: "tags",
      columnShape: .string,
      cardinality: .list
    )
    let derived = FieldProjection(
      cacheKey: "User:1",
      fieldName: "tags",
      outputType: .nonNull(.list(.nonNull(.scalar(String.self))))
    )
    expect(direct) == derived
  }

  // MARK: - Equatable

  func test__equality__givenSameStorageShape__returnsTrue() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .nonNull(.scalar(Int.self)))
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .nonNull(.scalar(Int.self)))
    expect(a) == b
  }

  func test__equality__givenDifferentCacheKey__returnsFalse() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    let b = FieldProjection(cacheKey: "User:2", fieldName: "age", outputType: .scalar(Int.self))
    expect(a) != b
  }

  func test__equality__givenDifferentFieldName__returnsFalse() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    let b = FieldProjection(cacheKey: "User:1", fieldName: "height", outputType: .scalar(Int.self))
    expect(a) != b
  }

  func test__equality__givenDifferentColumnShape__returnsFalse() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "value", outputType: .scalar(String.self))
    let b = FieldProjection(cacheKey: "User:1", fieldName: "value", outputType: .scalar(Int.self))
    expect(a) != b
  }

  func test__equality__givenDifferentCardinality__returnsFalse() {
    // Same (cacheKey, fieldName, columnShape) but scalar vs list.
    let scalar = FieldProjection(
      cacheKey: "User:1", fieldName: "value",
      columnShape: .string, cardinality: .scalar
    )
    let list = FieldProjection(
      cacheKey: "User:1", fieldName: "value",
      columnShape: .string, cardinality: .list
    )
    expect(scalar) != list
  }

  // MARK: - Hashable

  func test__hashable__equalProjectionsProduceEqualHashes() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    expect(a.hashValue) == b.hashValue
  }

  func test__hashable__usableInSet__deduplicatesEqualValues() {
    let a = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    let b = FieldProjection(cacheKey: "User:1", fieldName: "age", outputType: .scalar(Int.self))
    let set: Set<FieldProjection> = [a, b]
    expect(set.count) == 1
  }

  // MARK: - ColumnShape — built-in primitive scalars

  func test__columnShape__givenStringScalar__returnsString() {
    expect(FieldProjection.columnShape(of: .scalar(String.self))) == .string
  }

  func test__columnShape__givenIntScalar__returnsInt() {
    expect(FieldProjection.columnShape(of: .scalar(Int.self))) == .int
  }

  func test__columnShape__givenInt32Scalar__returnsInt() {
    expect(FieldProjection.columnShape(of: .scalar(Int32.self))) == .int
  }

  func test__columnShape__givenBoolScalar__returnsBool() {
    expect(FieldProjection.columnShape(of: .scalar(Bool.self))) == .bool
  }

  func test__columnShape__givenFloatScalar__returnsFloat() {
    expect(FieldProjection.columnShape(of: .scalar(Float.self))) == .float
  }

  func test__columnShape__givenDoubleScalar__returnsFloat() {
    expect(FieldProjection.columnShape(of: .scalar(Double.self))) == .float
  }

  // MARK: - ColumnShape — wrapper transparency

  func test__columnShape__givenNonNullWrappedScalar__peelsToInnerType() {
    expect(FieldProjection.columnShape(of: .nonNull(.scalar(Int.self)))) == .int
  }

  func test__columnShape__givenListWrappedScalar__peelsToInnerType() {
    expect(FieldProjection.columnShape(of: .list(.scalar(String.self)))) == .string
  }

  func test__columnShape__givenDeeplyWrappedScalar__peelsThroughEveryLayer() {
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.scalar(Bool.self))))
    expect(FieldProjection.columnShape(of: outputType)) == .bool
  }

  func test__columnShape__givenNestedListOfInts__returnsChildKeyForOuterField() {
    // `[[Int]]` — the outer list's rows hold `child_key_value`
    // pointers at synthetic sub-records (per ADR 0006 §3.2). The
    // inner-list element column (`.int`) is read via a follow-up
    // projection against the synthetic sub-record, not by the
    // outer field's projection.
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.list(.nonNull(.scalar(Int.self))))))
    expect(FieldProjection.columnShape(of: outputType)) == .childKey
  }

  func test__columnShape__givenTripleNestedList__returnsChildKey() {
    // `[[[String]]]` — same rule, regardless of nesting depth and
    // inner type.
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.list(.nonNull(.list(.nonNull(.scalar(String.self))))))))
    expect(FieldProjection.columnShape(of: outputType)) == .childKey
  }

  func test__columnShape__givenSingleListOfScalars__doesNotApplyNestingRule() {
    // `[Int]` — one `.list` wrapper. Inner-typed column applies.
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.scalar(Int.self))))
    expect(FieldProjection.columnShape(of: outputType)) == .int
  }

  // MARK: - ColumnShape — object types map to childKey

  func test__columnShape__givenObject__returnsChildKey() {
    let outputType: Selection.Field.OutputType = .object(MockSelectionSet.self)
    expect(FieldProjection.columnShape(of: outputType)) == .childKey
  }

  func test__columnShape__givenListOfObjects__returnsChildKey() {
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.object(MockSelectionSet.self))))
    expect(FieldProjection.columnShape(of: outputType)) == .childKey
  }

  // MARK: - ColumnShape — custom scalars

  func test__columnShape__givenCustomScalar__routesToCustomScalar() {
    // Per the doc on `ColumnShape`, all `.customScalar(_)` cases
    // route to `.customScalar` in this PR; precise-per-scalar
    // mapping (for the codegen-default wrapper whose `_jsonValue`
    // is a primitive like `String`) is deferred to a follow-up PR
    // per ADR 0007 Principle 7.
    expect(
      FieldProjection.columnShape(of: .customScalar(StructCustomScalar.self))
    ) == .customScalar
  }

  func test__columnShape__givenListOfCustomScalars__routesToCustomScalar() {
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.customScalar(StructCustomScalar.self))))
    expect(FieldProjection.columnShape(of: outputType)) == .customScalar
  }

  // MARK: - Cardinality

  func test__cardinality__givenScalar__returnsScalar() {
    expect(FieldProjection.cardinality(of: .scalar(Int.self))) == .scalar
  }

  func test__cardinality__givenObject__returnsScalar() {
    expect(FieldProjection.cardinality(of: .object(MockSelectionSet.self))) == .scalar
  }

  func test__cardinality__givenCustomScalar__returnsScalar() {
    expect(FieldProjection.cardinality(of: .customScalar(StructCustomScalar.self))) == .scalar
  }

  func test__cardinality__givenNonNullScalar__returnsScalar() {
    expect(FieldProjection.cardinality(of: .nonNull(.scalar(String.self)))) == .scalar
  }

  func test__cardinality__givenList__returnsList() {
    expect(FieldProjection.cardinality(of: .list(.scalar(String.self)))) == .list
  }

  func test__cardinality__givenNonNullList__returnsList() {
    expect(
      FieldProjection.cardinality(of: .nonNull(.list(.scalar(Int.self))))
    ) == .list
  }

  func test__cardinality__givenListOfNonNullScalars__returnsList() {
    expect(
      FieldProjection.cardinality(of: .list(.nonNull(.scalar(Int.self))))
    ) == .list
  }

  func test__cardinality__givenNestedList__returnsList() {
    // `[[Int]]` — outer list is what the initial projection reads.
    // Inner-list materialization is the caller's responsibility per
    // ADR 0006 §3.2.
    let outputType: Selection.Field.OutputType =
      .nonNull(.list(.nonNull(.list(.nonNull(.scalar(Int.self))))))
    expect(FieldProjection.cardinality(of: outputType)) == .list
  }

  // MARK: - End-to-end shape inferences for common GraphQL field types

  func test__shape__givenNonNullString__producesScalarStringColumn() {
    let projection = FieldProjection(
      cacheKey: "User:1",
      fieldName: "name",
      outputType: .nonNull(.scalar(String.self))
    )
    expect(projection.columnShape) == .string
    expect(projection.cardinality) == .scalar
  }

  func test__shape__givenListOfNonNullStrings__producesListStringColumn() {
    let projection = FieldProjection(
      cacheKey: "User:1",
      fieldName: "tags",
      outputType: .nonNull(.list(.nonNull(.scalar(String.self))))
    )
    expect(projection.columnShape) == .string
    expect(projection.cardinality) == .list
  }

  func test__shape__givenNonNullObject__producesScalarChildKeyColumn() {
    let projection = FieldProjection(
      cacheKey: "Query.viewer",
      fieldName: "user",
      outputType: .nonNull(.object(MockSelectionSet.self))
    )
    expect(projection.columnShape) == .childKey
    expect(projection.cardinality) == .scalar
  }

  func test__shape__givenListOfObjects__producesListChildKeyColumn() {
    let projection = FieldProjection(
      cacheKey: "User:1",
      fieldName: "friends",
      outputType: .nonNull(.list(.nonNull(.object(MockSelectionSet.self))))
    )
    expect(projection.columnShape) == .childKey
    expect(projection.cardinality) == .list
  }

  func test__shape__givenNestedListOfInts__producesListChildKeyColumn() {
    // The outer list's rows hold `child_key_value` pointers at
    // synthetic sub-records per ADR 0006 §3.2; the inner list
    // lives under the sentinel field name on those sub-records
    // and gets its own follow-up projection. The OUTER
    // projection's column is `.childKey`, not the inner element's
    // column — which is why this field is shape-equivalent to a
    // list of objects at the projection layer.
    let projection = FieldProjection(
      cacheKey: "Matrix:1",
      fieldName: "rows",
      outputType: .nonNull(.list(.nonNull(.list(.nonNull(.scalar(Int.self))))))
    )
    expect(projection.columnShape) == .childKey
    expect(projection.cardinality) == .list
  }
}

// MARK: - Custom-scalar test fixture

/// A user-defined custom scalar matching the shape codegen emits
/// for custom scalars in a generated schema. The exact
/// `_jsonValue` shape doesn't affect the projection — the
/// projection only inspects the type identity passed via
/// `.customScalar(_)`.
private struct StructCustomScalar: CustomScalarType, Sendable, Hashable {
  let payload: [String: String]

  init(_jsonValue value: JSONValue) throws {
    guard let dict = value as? [String: String] else {
      throw JSONDecodingError.couldNotConvert(value: value, to: Self.self)
    }
    self.payload = dict
  }

  var _jsonValue: JSONValue { payload }
}
