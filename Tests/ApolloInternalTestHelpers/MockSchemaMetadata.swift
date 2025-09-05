import Apollo
import ApolloAPI

extension Object {
  public static let mock = Object(typename: "Mock", implementedInterfaces: [])
}

public class MockSchemaMetadata: SchemaMetadata {

  private nonisolated(unsafe) static var _configuration: SchemaConfiguration.Type = SchemaConfiguration.self
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  @MainActor
  private static let testObserver = TestObserver() { _ in
    stub_objectTypeForTypeName(nil)
    stub_cacheKeyInfoForType_Object(nil)
  }

  private nonisolated(unsafe) static var _objectTypeForTypeName: ((String) -> Object?)?
  public static var objectTypeForTypeName: ((String) -> Object?)? {
      _objectTypeForTypeName
  }

  @MainActor
  public static func stub_objectTypeForTypeName(_ stub: ((String) -> Object?)?) {
    _objectTypeForTypeName = stub
    if _objectTypeForTypeName != nil {
      testObserver.start()
    }
  }

  @MainActor
  public static func stub_cacheKeyInfoForType_Object(
    _ stub: ((Object, ObjectData) -> CacheKeyInfo?)?
  ){
    _configuration.stub_cacheKeyInfoForType_Object = stub
    if stub != nil {
      testObserver.start()
    }
  }
  
  @MainActor
  public static func stub_cacheKeyForField_SingleReturn(
    _ stub: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> CacheKeyInfo?)?
  ) {
    _configuration.stub_cacheKeyForField_SingleReturn = stub
    if stub != nil {
      testObserver.start()
    }
  }
  
  @MainActor
  public static func stub_cacheKeyForField_ListReturn(
    _ stub: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> [CacheKeyInfo]?)?
  ) {
    _configuration.stub_cacheKeyForField_ListReturn = stub
    if stub != nil {
      testObserver.start()
    }
  }

  public static func objectType(forTypename __typename: String) -> Object? {
    if let stub = objectTypeForTypeName {
      return stub(__typename)
    }

    return Object(typename: __typename, implementedInterfaces: [])
  }

  public class SchemaConfiguration: ApolloAPI.SchemaConfiguration/*, ApolloAPI.FieldPolicyProvider*/ {
    fileprivate static nonisolated(unsafe) var stub_cacheKeyInfoForType_Object: ((Object, ObjectData) -> CacheKeyInfo?)?
    
    fileprivate static nonisolated(unsafe) var stub_cacheKeyForField_SingleReturn: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> CacheKeyInfo?)?
    
    fileprivate static nonisolated(unsafe) var stub_cacheKeyForField_ListReturn: ((Selection.Field, GraphQLOperation.Variables?, ResponsePath) -> [CacheKeyInfo]?)?

    public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
      stub_cacheKeyInfoForType_Object?(type, object)
    }
    
//    public static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo? {
//      stub_cacheKeyForField_SingleReturn?(field, variables, path)
//    }
//    
//    public static func cacheKeyList(for listField: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]? {
//      stub_cacheKeyForField_ListReturn?(listField, variables, path)
//    }
  }
}


// MARK - Mock Cache Key Providers

public protocol MockStaticCacheKeyProvider {
  static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo?
}

extension MockStaticCacheKeyProvider {
  public static var resolver: (Object, ObjectData) -> CacheKeyInfo? {
    cacheKeyInfo(for:object:)
  }
}

public struct IDCacheKeyProvider: MockStaticCacheKeyProvider {
  public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    try? .init(jsonValue: object["id"])
  }
}

public struct MockCacheKeyProvider {
  let id: String

  public init(id: String) {
    self.id = id
  }

  public func cacheKeyInfo(for type: Object, object: JSONObject) -> CacheKeyInfo? {
    .init(id: id, uniqueKeyGroup: nil)
  }
}

// MARK: - Custom Mock Schemas

public enum MockSchema1: SchemaMetadata {
  public static let configuration: any SchemaConfiguration.Type = MockSchema1Configuration.self

  public static func objectType(forTypename __typename: String) -> Object? {
    Object(typename: __typename, implementedInterfaces: [])
  }
}

public enum MockSchema1Configuration: SchemaConfiguration {
  public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    CacheKeyInfo(id: "one")
  }
  
  public static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo? {
    return nil
  }
  
  public static func cacheKeys(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]? {
    return nil
  }
}

public enum MockSchema2: SchemaMetadata {
  public static let configuration: any SchemaConfiguration.Type = MockSchema2Configuration.self

  public static func objectType(forTypename __typename: String) -> Object? {
    Object(typename: __typename, implementedInterfaces: [])
  }
}

public enum MockSchema2Configuration: SchemaConfiguration {
  public static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    CacheKeyInfo(id: "two")
  }
  
  public static func cacheKey(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> CacheKeyInfo? {
    return nil
  }
  
  public static func cacheKeys(for field: Selection.Field, variables: GraphQLOperation.Variables?, path: ResponsePath) -> [CacheKeyInfo]? {
    return nil
  }
}
