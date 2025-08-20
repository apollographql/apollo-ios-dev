import XCTest
import Nimble
@_spi(Execution) @testable import Apollo
@_spi(Unsafe) @_spi(Execution) import ApolloAPI
import ApolloInternalTestHelpers

@MainActor
class CacheKeyResolutionTests: XCTestCase {

  func test__schemaConfiguration__givenData_whenCacheKeyInfoIsNil_shouldReturnNil() {
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ _, _ in nil })

    let object: JSONObject = [
      "id": "α"
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }

  func test__schemaConfiguration__givenData_whenUnknownType_withCacheKeyInfoForUnknownType_shouldReturnInfoWithTypeName() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": "ω"
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("Omega:ω"))
  }

  func test__schemaConfiguration__givenData_whenUnknownType_nilCacheKeyInfo_shouldReturnNil() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in nil })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": "ω"
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }

  func test__schemaConfiguration__givenData_whenKnownType_givenNilCacheKeyInfo_shouldReturnNil() {
    let Alpha = Object(typename: "Alpha", implementedInterfaces: [])

    let object: JSONObject = [
      "__typename": "Alpha",
      "id": "α"
    ]

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Alpha })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in nil })

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }

  func test__schemaConfiguration__givenData_whenKnownType_givenCacheKeyInfo_shouldReturnCacheReference() {
    let object: JSONObject = [
      "__typename": "MockSchemaObject",
      "id": "β"
    ]

    MockSchemaMetadata.stub_cacheKeyInfoForType_Object(IDCacheKeyProvider.resolver)

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal(
      "MockSchemaObject:β"
    ))
  }

  func test__schemaConfiguration__givenData_asInt_equalToBoolFalse_shouldNotConvertToBool() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": 0
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("Omega:0"))
  }

  func test__schemaConfiguration__givenData_asInt_equalToBoolTrue_shouldNotConvertToBool() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": 1
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("Omega:1"))
  }

  func test__schemaConfiguration__givenData_asInt_outsideBoolRange_shouldReturnCacheReference() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": 2
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("Omega:2"))
  }

  func test__schemaConfiguration__givenData_asBool_true_shouldNotConvertToInt() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": true
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }

  func test__schemaConfiguration__givenData_asBool_false_shouldNotConvertToInt() {
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in nil })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
      return try? CacheKeyInfo(jsonValue: json["id"])
    })

    let object: JSONObject = [
      "__typename": "Omega",
      "id": false
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }

  func test__multipleSchemaConfigurations_withDifferentCacheKeyProvidersDefinedInExtensions_shouldReturnDifferentCacheKeys() {
    let object: JSONObject = [
      "__typename": "MockSchemaObject",
      "id": "β"
    ]
  
    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual1 = MockSchema1.cacheKey(for: objectDict)

    expect(actual1).to(equal(
      "MockSchemaObject:one"
    ))

    let actual2 = MockSchema2.cacheKey(for: objectDict)

    expect(actual2).to(equal(
      "MockSchemaObject:two"
    ))
  }

  func test__schemaConfiguration__givenData_whenKnownType_isCacheKeyProvider_withUniqueKeyGroupId_shouldReturnCacheReference() {
    let Delta = Object(typename: "Delta", implementedInterfaces: [])

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Delta })
    MockSchemaMetadata.stub_cacheKeyInfoForType_Object({ (_, json) in
        .init(id: "δ", uniqueKeyGroup: "GreekLetters")
    })

    let object: JSONObject = [
      "__typename": "Delta",
      "lowercase": "δ"
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("GreekLetters:δ"))
  }

  // MARK: - Key Fields
  
  func test__schemaConfiguration__givenSingleKeyField_shouldReturnKeyFieldValue() {
    let Delta = Object(typename: "Dog", implementedInterfaces: [], keyFields: ["id"])

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Delta })

    let object: JSONObject = [
      "__typename": "Dog",
      "id": "10",
      "name": "Beagle"
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal("Dog:10"))
  }
  
  func test__schemaConfiguration__givenMultipleKeyFields_shouldReturnKeyFieldValues() {
    let Delta = Object(typename: "Dog", implementedInterfaces: [], keyFields: ["id", "name"])

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Delta })

    let object: JSONObject = [
      "__typename": "Dog",
      "id": "10",
      "name": #"Be\ag+le"#,
      "height": 20,
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(equal(#"Dog:10+Be\\ag\+le"#))
  }
  
  func test__schemaConfiguration__givenMissingKeyFields_shouldReturnNil() {
    let Delta = Object(typename: "Dog", implementedInterfaces: [], keyFields: ["id", "name"])

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Delta })

    let object: JSONObject = [
      "__typename": "Dog",
      "id": "10",
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(for: objectDict)

    expect(actual).to(beNil())
  }
  
  func test__schemaConfiguration__givenInterfaceWithKeyField_shouldReturnKeyFieldValue() {
    let Interface = Interface(name: "Animal", keyFields: ["id"], implementingObjects: ["Cat"])

    let object: JSONObject = [
      "__typename": "Cat",
      "id": "10",
    ]

    let objectDict = NetworkResponseExecutionSource().opaqueObjectDataWrapper(for: object)
    let actual = MockSchemaMetadata.cacheKey(
      for: objectDict,
      inferredToImplementInterface: Interface
    )

    expect(actual).to(equal("Cat:10"))
  }
  
}
