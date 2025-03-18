import XCTest
import Apollo

public typealias TearDownHandler = @Sendable () throws -> ()
public typealias TestDependency<Resource> = (Resource, TearDownHandler?)

public protocol TestCacheProvider: AnyObject {
  static func makeNormalizedCache() async -> TestDependency<any NormalizedCache>
}

public class InMemoryTestCacheProvider: TestCacheProvider {
  public static func makeNormalizedCache() async -> TestDependency<any NormalizedCache> {
    let cache = InMemoryNormalizedCache()
    return (cache, nil)
  }
}

public protocol CacheDependentTesting {
  var cacheType: any TestCacheProvider.Type { get }
  var cache: (any NormalizedCache)! { get }  
}

extension CacheDependentTesting where Self: XCTestCase {
  public func makeNormalizedCache() async throws -> any NormalizedCache {
    let (cache, tearDownHandler) = await cacheType.makeNormalizedCache()

    if let tearDownHandler = tearDownHandler {
      self.addTeardownBlock {
        do {
          try tearDownHandler()
        } catch {
          self.record(error)
        }
      }
    }

    return cache
  }
  
  public func mergeRecordsIntoCache(_ records: RecordSet) async {
    _ = try! await cache.merge(records: records)
  }
}
