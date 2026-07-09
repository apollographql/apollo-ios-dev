@_spi(Execution) import ApolloAPI

/// A `GraphQLExecutionSource` configured to execute upon the data stored in a ``NormalizedCache``.
///
/// Each object exposed by the cache is represented as a ``Record``.
struct CacheDataExecutionSource: GraphQLExecutionSource {
  typealias RawObjectData = Record
  typealias FieldCollector = CacheDataFieldSelectionCollector

  /// A `weak` reference to the transaction the cache data is being read from during execution.
  /// This transaction is used to resolve references to other objects in the cache during field
  /// value resolution.
  ///
  /// This property is `weak` to ensure there is not a retain cycle between the transaction and the
  /// execution pipeline. If the transaction has been deallocated, execution cannot continue
  /// against the cache data.
  weak var transaction: ApolloStore.ReadTransaction?

  /// Used to determine whether deferred selections within a selection set should be executed at the same
  /// time as the other selections.
  ///
  /// When executing on cache data all selections, including deferred, must be executed together because
  /// there is only a single response from the cache data. Any deferred selection that was cached will
  /// be returned in the response.
  var shouldAttemptDeferredFragmentExecution: Bool { true }

  init(transaction: ApolloStore.ReadTransaction) {
    self.transaction = transaction
  }

  func resolveField(
    with info: FieldExecutionInfo,
    on object: Record
  ) -> PossiblyDeferred<JSONValue?> {
    PossiblyDeferred {

      let value = try resolveCacheKey(with: info, on: object)

      switch value {
      case let reference as CacheReference:
        return deferredResolve(reference: reference, info: info).map { $0 as JSONValue }

      case let referenceList as [JSONValue]:
        return resolveReferences(in: referenceList, info: info).map { $0 as JSONValue? }

      default:
        return .immediate(.success(value))
      }
    }
  }
  
  private func resolveCacheKey(
    with info: FieldExecutionInfo,
    on object: Record
  ) throws -> JSONValue? {
    // `info.cacheReadStrategy()` centralizes the field-policy
    // resolution rules (programmatic `FieldPolicy.Provider` first,
    // `@fieldPolicy` directive second, plain field name last) and
    // memoizes the result on the `FieldExecutionInfo` so the
    // projection-time and resolve-time paths share a single
    // computation per `(field, info)`.
    let strategy = try info.cacheReadStrategy()

    switch strategy {
    case .parentRecordField(let name):
      // Standard non-policy read: the field's value lives on the
      // parent record under its normalized name (the same name the
      // writer used in `GraphQLResultNormalizer`). Subscript to get
      // it.
      return object[name]

    case .policyReference(let key):
      // `@fieldPolicy` redirect: the field's value is a direct cache
      // reference, computed from the field's arguments without
      // consulting the parent record. The writer never wrote an
      // entry under this name on the parent — the policy targets a
      // record that `@typePolicy` (or another write path) populated
      // under the canonical key. Return the reference; the executor's
      // existing `CacheReference` resolution will load it.
      return CacheReference(key) as JSONValue

    case .policyReferenceList(let keys):
      // Same as `policyReference`, lifted to a list-typed field:
      // each policy-derived key becomes one `CacheReference` in the
      // returned array.
      return keys.map { CacheReference($0) } as JSONValue
    }
  }

  private func resolveReferences(
    in list: [JSONValue],
    info: FieldExecutionInfo
  ) -> PossiblyDeferred<JSONValue> {
    return list
      .enumerated()
      .deferredFlatMap { index, element in
        if let cacheReference = element as? CacheReference {
          return self.deferredResolve(reference: cacheReference, info: info)
            .mapError { error in
              if !(error is GraphQLExecutionError) {
                return GraphQLExecutionError(
                  path: info.responsePath.appending(String(index)),
                  underlying: error
                )
              } else {
                return error
              }
            }.map { $0 as JSONValue }
        } else if let nestedList = element as? [JSONValue] {
          return self.resolveReferences(in: nestedList, info: info)
        } else {
          return .immediate(.success(element))
        }
      }.map { $0 as JSONValue }
  }

  private func deferredResolve(
    reference: CacheReference,
    info: FieldExecutionInfo
  ) -> PossiblyDeferred<Record> {
    guard let transaction else {
      return .immediate(.failure(ApolloStore.Error.notWithinReadTransaction))
    }

    // The child's selection set is the union of the selections of
    // every field merged into this `FieldExecutionInfo`, mirroring
    // `FieldExecutionInfo.computeChildExecutionData` — the executor
    // executes that union against the loaded record, so projecting
    // from `info.field` alone would under-collect whenever the same
    // field is selected more than once with divergent sub-selections
    // (e.g. directly and again inside a named or inline fragment),
    // turning fully-cached data into a spurious cache miss. Each
    // merged field's declared OutputType is peeled (`.nonNull` and
    // `.list` wrappers) down to its `.object` case; non-object
    // output types contribute nothing. Reaching this site with no
    // object-typed merged field at all is a contract violation —
    // only object-typed fields produce `CacheReference` values — and
    // is surfaced as an explicit decoding error.
    var childSelections: [Selection] = []
    var foundObjectOutputType = false
    for mergedField in info.mergedFields {
      guard let selections = Self.childSelections(of: mergedField.type) else { continue }
      foundObjectOutputType = true
      childSelections.append(contentsOf: selections)
    }
    guard foundObjectOutputType else {
      return .immediate(.failure(JSONDecodingError.wrongType))
    }

    return transaction.loadObject(
      forKey: reference.key,
      selections: childSelections,
      variables: info.parentInfo.variables,
      schema: info.parentInfo.schema,
      responsePath: info.responsePath
    )
  }

  /// Peels `.nonNull` and `.list` wrappers off `outputType` to find
  /// the inner `.object(RootSelectionSetType)` and returns that type's
  /// `__selections`. Returns `nil` if there is no object case
  /// (scalar or customScalar), in which case the caller is asking us
  /// to resolve a reference for a non-object-typed field — a contract
  /// violation we surface as an explicit decoding error rather than
  /// silently no-op.
  private static func childSelections(
    of outputType: Selection.Field.OutputType
  ) -> [Selection]? {
    switch outputType {
    case .nonNull(let inner), .list(let inner):
      return childSelections(of: inner)
    case .object(let selectionSetType):
      return selectionSetType.__selections
    case .scalar, .customScalar:
      return nil
    }
  }

  func computeCacheKey(
    for object: Record,
    in schema: any SchemaMetadata.Type,
    inferredToImplementInterface interface: Interface?
  ) -> CacheKey? {
    return object.key
  }

  /// A wrapper around the `DefaultFieldSelectionCollector` that supplies a
  /// lazy `runtimeObjectType` resolver derived from the `Record`'s
  /// `__typename` field. Resolution is deferred until an inline fragment
  /// actually requires the runtime type, avoiding any transformation of
  /// the record's field dictionary on selection sets that don't use type
  /// cases.
  struct CacheDataFieldSelectionCollector: FieldSelectionCollector {
    static func collectFields(
      from selections: [Selection],
      into groupedFields: inout FieldSelectionGrouping,
      for object: Record,
      info: ObjectExecutionInfo
    ) throws {
      return try DefaultFieldSelectionCollector.collectFields(
        from: selections,
        into: &groupedFields,
        resolveRuntimeType: { info.runtimeObjectType(forTypename: object["__typename"] as? String) },
        info: info
      )
    }
  }
}
