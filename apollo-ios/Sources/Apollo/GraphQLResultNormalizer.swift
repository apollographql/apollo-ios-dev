import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

@_spi(Execution)
public enum ResultNormalizerFactory {

  public static func selectionSetDataNormalizer() -> SelectionSetDataResultNormalizer {
    SelectionSetDataResultNormalizer()
  }

  public static func networkResponseDataNormalizer() -> RawJSONResultNormalizer {
    RawJSONResultNormalizer()
  }
}

@_spi(Execution)
public class BaseGraphQLResultNormalizer: GraphQLResultAccumulator {
  
  public let requiresCacheKeyComputation: Bool = true

  private var records: RecordSet = [:]

  fileprivate init() {}

  public final func accept(scalar: JSONValue, info: FieldExecutionInfo) -> JSONValue? {
    return scalar
  }

  public func accept(customScalar: JSONValue, info: FieldExecutionInfo) -> JSONValue? {
    return customScalar
  }

  public final func acceptNullValue(info: FieldExecutionInfo) -> JSONValue? {
    return NSNull()
  }

  public final func acceptMissingValue(info: FieldExecutionInfo) -> JSONValue? {
    return nil
  }

  public final func accept(list: [JSONValue?], info: FieldExecutionInfo) -> JSONValue? {
    return list
  }

  public final func accept(childObject: CacheReference, info: FieldExecutionInfo) -> JSONValue? {
    return childObject
  }

  public final func accept(fieldEntry: JSONValue?, info: FieldExecutionInfo) throws -> (key: String, value: JSONValue)? {
    guard let fieldEntry else { return nil }
    return (try info.cacheKeyForField(), fieldEntry)
  }

  public final func accept(
    fieldEntries: [(key: String, value: JSONValue)],
    info: ObjectExecutionInfo
  ) throws -> CacheReference {
    let cachePath = info.cachePath.joined

    let object = JSONObject(fieldEntries, uniquingKeysWith: { (_, last) in last })
    records.merge(record: Record(key: cachePath, object))

    return CacheReference(cachePath)
  }

  public final func finish(rootValue: CacheReference, info: ObjectExecutionInfo) throws -> RecordSet {
    return records
  }
}

@_spi(Execution)
public final class RawJSONResultNormalizer: BaseGraphQLResultNormalizer {}

@_spi(Execution)
public final class SelectionSetDataResultNormalizer: BaseGraphQLResultNormalizer {
  override public final func accept(customScalar: JSONValue, info: FieldExecutionInfo) -> JSONValue? {
    if let customScalar = customScalar as? (any JSONEncodable) {
      return customScalar._jsonValue
    }
    return customScalar
  }
}
