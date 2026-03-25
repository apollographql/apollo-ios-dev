import XCTest
import ApolloAPI

// MARK: - Switch-based lookup (old implementation)

/// Simulates the old generated code that used a switch statement for objectType lookup.
/// Used as a baseline to compare against the new dictionary-based implementation.
private enum SwitchBasedSchema {
  static let allObjects: [Object] = (0..<4000).map {
    Object(typename: "Type_\($0)", implementedInterfaces: [])
  }

  static func objectType(forTypename typename: String) -> Object? {
    // Simulate a large switch by doing a linear scan, which is what the compiler
    // generates for a switch with string cases.
    for obj in allObjects {
      if obj.typename == typename {
        return obj
      }
    }
    return nil
  }
}

// MARK: - Dictionary-based lookup (new implementation)

/// Simulates the new generated code that uses a static dictionary for objectType lookup.
private enum DictionaryBasedSchema {
  static let allObjects: [Object] = (0..<4000).map {
    Object(typename: "Type_\($0)", implementedInterfaces: [])
  }

  private static let objectTypeMap: [String: Object] = {
    var map = [String: Object](minimumCapacity: allObjects.count)
    for obj in allObjects {
      map[obj.typename] = obj
    }
    return map
  }()

  static func objectType(forTypename typename: String) -> Object? {
    objectTypeMap[typename]
  }
}

// MARK: - Performance Tests

class ObjectTypeLookupPerformanceTests: XCTestCase {

  /// Type names to look up during each measurement iteration.
  /// Includes early, middle, late, and non-existent entries to exercise
  /// different positions in the linear scan and dictionary hash paths.
  private static let lookupTypeNames: [String] = {
    var names = [String]()
    // First, middle, and last entries
    for i in stride(from: 0, to: 4000, by: 100) {
      names.append("Type_\(i)")
    }
    // Some entries that don't exist (exercises default/nil path)
    for i in 0..<10 {
      names.append("NonExistent_\(i)")
    }
    return names
  }()

  // MARK: - Switch-based (linear scan) performance

  func testPerformance_objectTypeLookup_switchBased() {
    // Warm up
    _ = SwitchBasedSchema.objectType(forTypename: "Type_0")

    measure {
      for _ in 0..<100 {
        for name in Self.lookupTypeNames {
          let result = SwitchBasedSchema.objectType(forTypename: name)
          if !name.hasPrefix("NonExistent") {
            XCTAssertNotNil(result)
          }
        }
      }
    }
  }

  // MARK: - Dictionary-based performance

  func testPerformance_objectTypeLookup_dictionaryBased() {
    // Warm up (also triggers lazy dictionary initialization)
    _ = DictionaryBasedSchema.objectType(forTypename: "Type_0")

    measure {
      for _ in 0..<100 {
        for name in Self.lookupTypeNames {
          let result = DictionaryBasedSchema.objectType(forTypename: name)
          if !name.hasPrefix("NonExistent") {
            XCTAssertNotNil(result)
          }
        }
      }
    }
  }
}
