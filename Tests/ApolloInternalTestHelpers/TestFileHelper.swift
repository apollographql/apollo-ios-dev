import Foundation
import Apollo

public struct TestFileHelper {
  
  public static func testParentFolder(for file: StaticString = #filePath) -> URL {
    let fileAsString = file.withUTF8Buffer {
        String(decoding: $0, as: UTF8.self)
    }
    let url = URL(fileURLWithPath: fileAsString)
    return url.deletingLastPathComponent()
  }
  
  public static func uploadServerFolder(from file: StaticString = #filePath) -> URL {
    self.testParentFolder(for: file)
      .deletingLastPathComponent() // test root
      .deletingLastPathComponent() // source root
      .appendingPathComponent("SimpleUploadServer")
  }
  
  public static func uploadsFolder(from file: StaticString = #filePath) -> URL {
    self.uploadServerFolder(from: file)
      .appendingPathComponent("uploads")
  }
  
  public static func fileURLForFile(named name: String, extension fileExtension: String) -> URL {
    return self.testParentFolder()
        .appendingPathComponent("Resources")
        .appendingPathComponent(name)
        .appendingPathExtension(fileExtension)
  }

  public static func sourceRootURL() -> URL {
    FileFinder.findParentFolder()
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // apollo-ios-dev
  }

  public static func starWarsFolderURL() -> URL {
    let source = self.sourceRootURL()
    return source
      .appendingPathComponent("Sources")
      .appendingPathComponent("StarWarsAPI")
  }

  public static func starWarsSchemaFileURL() -> URL {
    let starWars = self.starWarsFolderURL()
    return starWars
      .appendingPathComponent("graphql")
      .appendingPathComponent("schema.json")
  }
}
