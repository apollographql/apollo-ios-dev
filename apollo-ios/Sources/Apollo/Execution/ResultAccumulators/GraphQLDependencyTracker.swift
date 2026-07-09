import ApolloAPI

final class GraphQLDependencyTracker: GraphQLResultAccumulator {

  let requiresCacheKeyComputation: Bool = true

  private var dependentKeys: Set<CacheDependentKey> = []

  func accept(scalar: JSONValue, info: FieldExecutionInfo) {
    insert(info)
  }

  func accept(customScalar: JSONValue, info: FieldExecutionInfo) {
    insert(info)
  }

  func acceptNullValue(info: FieldExecutionInfo) {
    insert(info)
  }

  func acceptMissingValue(info: FieldExecutionInfo) throws -> () {
    insert(info)
  }

  func accept(list: [Void], info: FieldExecutionInfo) {
    insert(info)
  }

  func accept(childObject: Void, info: FieldExecutionInfo) {
  }

  func accept(fieldEntry: Void, info: FieldExecutionInfo) -> Void? {
    insert(info)
    return ()
  }

  func accept(fieldEntries: [Void], info: ObjectExecutionInfo) {
  }

  func finish(rootValue: Void, info: ObjectExecutionInfo) -> Set<CacheDependentKey> {
    return dependentKeys
  }

  /// Records a dependency on the field described by `info`. The
  /// containing record's cache key is `info.parentInfo.cachePath` —
  /// the executor sets this to the writer's record key on entry to
  /// every record boundary (see `GraphQLExecutor.computeChildExecutionData`),
  /// so the resulting `(cacheKey, fieldName)` pair matches the
  /// changed-key set produced by `RecordSet.merge` by construction.
  /// `fieldName` is the field's normalized name on that record (the
  /// same name the writer wrote, including any argument-derived
  /// suffix), which is the last segment of `info.cachePath`.
  private func insert(_ info: FieldExecutionInfo) {
    let recordKey = info.parentInfo.cachePath.joined
    let fieldName: String
    if let normalizedName = try? info.normalizedFieldName() {
      fieldName = normalizedName
    } else {
      // Should not happen — `normalizedFieldName` only throws when the
      // field's cache key cannot be computed from its arguments, which
      // is the same precondition any caller of `info.cachePath` would
      // have already satisfied. Falling back to `responseKeyForField`
      // preserves intersection semantics for fields without arguments.
      fieldName = info.responseKeyForField
    }
    dependentKeys.insert(CacheDependentKey(cacheKey: recordKey, fieldName: fieldName))
  }
}
