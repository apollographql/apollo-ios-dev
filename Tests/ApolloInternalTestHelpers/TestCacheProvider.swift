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
  var store: ApolloStore! { get }
}

extension CacheDependentTesting where Self: XCTestCase {
  public func makeTestStore() async throws -> ApolloStore {
    let (cache, tearDownHandler) = await cacheType.makeNormalizedCache()
    nonisolated(unsafe) let `self` = self

    if let tearDownHandler = tearDownHandler {
      self.addTeardownBlock {
        do {
          try tearDownHandler()
        } catch {
          self.record(error)
        }
      }
    }

    return ApolloStore(cache: cache)
  }

}
