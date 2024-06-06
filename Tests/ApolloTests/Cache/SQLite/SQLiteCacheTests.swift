import Foundation
import ApolloInternalTestHelpers

// These test cases inherit all tests from their superclasses.

class SQLiteFetchQueryTests: FetchQueryTests {
  override var cacheType: any TestCacheProvider.Type {
    SQLiteTestCacheProvider.self
  }
}

class SQLiteLoadQueryFromStoreTests: LoadQueryFromStoreTests {
  override var cacheType: any TestCacheProvider.Type {
    SQLiteTestCacheProvider.self
  }
}

class SQLiteReadWriteFromStoreTests: ReadWriteFromStoreTests {
  override var cacheType: any TestCacheProvider.Type {
    SQLiteTestCacheProvider.self
  }
}

class SQLiteWatchQueryTests: WatchQueryTests {
  override var cacheType: any TestCacheProvider.Type {
    SQLiteTestCacheProvider.self
  }
}

