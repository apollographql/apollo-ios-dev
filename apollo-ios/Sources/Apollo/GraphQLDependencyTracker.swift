#if !COCOAPODS
import ApolloAPI
#endif

@_spi(Execution)
public final class GraphQLDependencyTracker: GraphQLResultAccumulator {

  public let requiresCacheKeyComputation: Bool = true

  private var dependentKeys: Set<CacheKey> = Set()
  
  public init() {}

  public func accept(scalar: JSONValue, info: FieldExecutionInfo) {
    dependentKeys.insert(info.cachePath.joined)
  }

  public func accept(customScalar: JSONValue, info: FieldExecutionInfo) {
    dependentKeys.insert(info.cachePath.joined)
  }

  public func acceptNullValue(info: FieldExecutionInfo) {
    dependentKeys.insert(info.cachePath.joined)
  }

  public func acceptMissingValue(info: FieldExecutionInfo) throws -> () {
    dependentKeys.insert(info.cachePath.joined)
  }

  public func accept(list: [Void], info: FieldExecutionInfo) {
    dependentKeys.insert(info.cachePath.joined)
  }

  public func accept(childObject: Void, info: FieldExecutionInfo) {
  }

  public func accept(fieldEntry: Void, info: FieldExecutionInfo) -> Void? {
    dependentKeys.insert(info.cachePath.joined)
    return ()
  }

  public func accept(fieldEntries: [Void], info: ObjectExecutionInfo) {
  }

  public func finish(rootValue: Void, info: ObjectExecutionInfo) -> Set<CacheKey> {
    return dependentKeys
  }
}
