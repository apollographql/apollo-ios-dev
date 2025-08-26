import Foundation
import OrderedCollections
import TemplateString

/// Generates a file containing schema metadata used by the GraphQL executor at runtime.
struct SchemaConfigurationFileGenerator: FileGenerator {
  /// Shared codegen configuration
  let config: ApolloCodegen.ConfigurationContext

  var template: any TemplateRenderer { SchemaConfigurationTemplate(config: config) }
  var overwrite: Bool { false }
  var target: FileTarget { .schema }
  var fileName: String { "SchemaConfiguration" }
  
  // Field Policy Handling
  let singleValueRegex = #"""
  (?s)\b(?:public|internal|fileprivate|private)?\s*
  (?:static\s+)?func\s+cacheKey\s*
  \(\s*for\s+field\s*:\s*Selection\.Field\s*,\s*
  variables\s*:\s*GraphQLOperation\.Variables\?\s*,\s*
  path\s*:\s*ResponsePath\s*\)\s*
  (?:async\s+throws|throws\s+async|async|throws)?\s*
  ->\s*(?:\w+\.)?CacheKeyInfo\?\s*\{  
  """#
  
  var singleValueFunc: TemplateString {
  """
    static func cacheKey(for field: \(config.ApolloAPITargetName).Selection.Field, variables: \(config.ApolloAPITargetName).GraphQLOperation.Variables?, path: \(config.ApolloAPITargetName).ResponsePath) -> \(config.ApolloAPITargetName).CacheKeyInfo? {
      // Implement this function to configure cache key resolution for fields that return a single object/value
      return nil
    }
  """
  }
  
  let listValueRegex = #"""
  (?s)\b(?:public|internal|fileprivate|private)?\s*
  (?:static\s+)?func\s+cacheKeys\s*
  \(\s*for\s+field\s*:\s*Selection\.Field\s*,\s*
  variables\s*:\s*GraphQLOperation\.Variables\?\s*,\s*
  path\s*:\s*ResponsePath\s*\)\s*
  (?:async\s+throws|throws\s+async|async|throws)?\s*
  ->\s*\[\s*(?:\w+\.)?CacheKeyInfo\s*\]\?\s*\{  
  """#
  
  var listValueFunc: TemplateString {
  """
    static func cacheKeys(for field: \(config.ApolloAPITargetName).Selection.Field, variables: \(config.ApolloAPITargetName).GraphQLOperation.Variables?, path: \(config.ApolloAPITargetName).ResponsePath) -> [\(config.ApolloAPITargetName).CacheKeyInfo]? {
      // Implement this function to configure cache key resolution for fields that return a list of objects/values
      return nil
    }  
  """
  }
  
  func appendFunctions(to filePath: String) async throws {
    var src = try String(contentsOfFile: filePath, encoding: .utf8)
    if src.isEmpty { return }
    
    insertFunction(in: &src, regex: singleValueRegex, funcDecl: singleValueFunc)
    insertFunction(in: &src, regex: listValueRegex, funcDecl: listValueFunc)
    
    try src.write(toFile: filePath, atomically: true, encoding: .utf8)
  }
  
  private func insertFunction(in src: inout String, regex: String, funcDecl: TemplateString) {
    if !src.containsRegex(regex),
       let enumDefRange = src.range(of: "enum SchemaConfiguration"),
       let closeBraceIndex = src[enumDefRange.lowerBound...].lastIndex(of: "}") {
      src.insert(contentsOf: "\n\n\(funcDecl)\n", at: closeBraceIndex)
    }
  }
  
}

extension String {
  fileprivate func containsRegex(_ regex: String) -> Bool {
    do {
      let reg = try NSRegularExpression(
        pattern: regex,
        options: []
      )
      let range = NSRange(self.startIndex..<self.endIndex, in: self)
      return reg.firstMatch(in: self, options: [], range: range) != nil
    } catch {
      return false
    }
  }
}
