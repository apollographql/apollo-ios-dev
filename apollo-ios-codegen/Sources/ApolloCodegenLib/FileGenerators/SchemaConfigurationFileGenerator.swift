import Foundation
import OrderedCollections

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
  
  let listValueRegex = #"""
  (?s)\b(?:public|internal|fileprivate|private)?\s*
  (?:static\s+)?func\s+cacheKeys\s*
  \(\s*for\s+field\s*:\s*Selection\.Field\s*,\s*
  variables\s*:\s*GraphQLOperation\.Variables\?\s*,\s*
  path\s*:\s*ResponsePath\s*\)\s*
  (?:async\s+throws|throws\s+async|async|throws)?\s*
  ->\s*\[\s*(?:\w+\.)?CacheKeyInfo\s*\]\?\s*\{  
  """#
  
  func appendFunctions(to filePath: String) throws {
    var src = try String(contentsOfFile: filePath, encoding: .utf8)
    if src.isEmpty { return }
    
    
  }
  
  private func insertFunction(in src: String, regex: String, funcDecl: String) {
    if !src.contains(Regex(regex)) {
      g
    }
  }
}
