import Foundation
import ApolloInternalTestHelpers

// Inherits every test in `LoadFieldsTests` and runs them against the
// SQLite-backed cache. Together with the InMemory-targeted parent
// class this gives PR-009c coverage on both backends in one place.
class SQLiteLoadFieldsTests: LoadFieldsTests {
  override var cacheType: any TestCacheProvider.Type {
    SQLiteTestCacheProvider.self
  }
}
