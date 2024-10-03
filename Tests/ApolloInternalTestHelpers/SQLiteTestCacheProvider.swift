import Foundation
import Apollo
import ApolloSQLite

public class SQLiteTestCacheProvider: TestCacheProvider {  
  public static func makeNormalizedCache() async -> TestDependency<any NormalizedCache> {
    await makeNormalizedCache(fileURL: temporarySQLiteFileURL())
  }

  public static func makeNormalizedCache(fileURL: URL) async -> TestDependency<any NormalizedCache> {
    let cache = try! SQLiteNormalizedCache(fileURL: fileURL)
    let tearDownHandler = { @Sendable in
      try Self.deleteCache(at: fileURL)
    }
    return (cache, tearDownHandler)
  }

  public static func temporarySQLiteFileURL() -> URL {
    let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
    
    // Create a folder with a random UUID to hold the SQLite file, since creating them in the
    // same folder this close together will cause DB locks when you try to delete between tests.
    let folder = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    
    return folder.appendingPathComponent("db.sqlite3")
  }

  static func deleteCache(at url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }
}
