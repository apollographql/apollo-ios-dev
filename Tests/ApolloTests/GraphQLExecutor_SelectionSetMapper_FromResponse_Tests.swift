import XCTest
import Nimble
@_spi(Execution) @testable import Apollo
@testable @_spi(Unsafe) @_spi(Internal) import ApolloAPI
import ApolloInternalTestHelpers

/// Tests reading fields from a JSON network response using a GraphQLExecutor and a SelectionSetMapper
class GraphQLExecutor_SelectionSetMapper_FromResponse_Tests: XCTestCase {

  // MARK: - Helpers

  private static let executor: GraphQLExecutor<NetworkResponseExecutionSource> = {
    let executor = GraphQLExecutor(executionSource: NetworkResponseExecutionSource())
    return executor
  }()

  private static func readValues<T: RootSelectionSet>(
    _ selectionSet: T.Type,
    from object: JSONObject,
    variables: GraphQLOperation.Variables? = nil
  ) async throws -> T {
    let dataDict = try await GraphQLExecutor_SelectionSetMapper_FromResponse_Tests.executor.execute(
      selectionSet: selectionSet,
      on: object,      
      variables: variables,
      accumulator: DataDictMapper()
    )
    return T(_dataDict: dataDict)
  }

  private static func readValues<T: SelectionSet, Operation: GraphQLOperation>(
    _ selectionSet: T.Type,
    in operation: Operation.Type,
    from object: JSONObject,
    variables: GraphQLOperation.Variables? = nil
  ) async throws -> T {
    let dataDict = try await GraphQLExecutor_SelectionSetMapper_FromResponse_Tests.executor.execute(
      selectionSet: selectionSet,
      in: operation,
      on: object,
      accumulator: DataDictMapper()
    )
    return T(_dataDict: dataDict)
  }

  // MARK: - Tests

  // MARK: Nonnull Scalar

  func test__nonnull_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String.self)] }
    }
    let object: JSONObject = ["name": "Luke Skywalker"]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }
  
  func test__nonnull_scalar__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String.self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["name"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }
  
  func test__nonnull_scalar__givenDataHasNullValueForField_throwsNullValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String.self)] }
    }
    let object: JSONObject = ["name": NSNull()]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["name"]))
      expect(error.underlying).to(matchError(JSONDecodingError.nullValue))
    })
  }
  
  func test__nonnull_scalar__givenDataWithTypeConvertibleToFieldType_getsConvertedValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String.self)] }
    }
    let object: JSONObject = ["name": 10]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.name).to(equal("10"))
  }

  func test__nonnull_scalar__givenDataWithTypeNotConvertibleToFieldType_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String.self)] }
    }
    let object: JSONObject = ["name": false]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["name"]))
        expect(value as? Bool).to(beFalse())
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: Custom Scalar

  func test__nonnull_customScalar_asString__givenDataAsInt_getsValue() async throws {
    // given
    typealias GivenCustomScalar = String

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("customScalar", GivenCustomScalar.self)] }
    }
    let object: JSONObject = ["customScalar": Int(12345678)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.customScalar).to(equal("12345678"))
  }

  func test__nonnull_customScalar_asString__givenDataAsInt64_getsValue() async throws {
    // given
    typealias GivenCustomScalar = String

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("customScalar", GivenCustomScalar.self)] }
    }
    let object: JSONObject = ["customScalar": Int64(989561700)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.customScalar).to(equal("989561700"))
  }

  func test__nonnull_customScalar_asString__givenDataAsDouble_getsValue() async throws {
    // given
    typealias GivenCustomScalar = String

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("customScalar", GivenCustomScalar.self)] }
    }
    let object: JSONObject = ["customScalar": Double(1234.5678)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.customScalar).to(equal("1234.5678"))
  }

  func test__nonnull_customScalar_asCustomStruct__givenDataAsInt64_getsValue() async throws {
    // given
    struct GivenCustomScalar: CustomScalarType, Hashable {
      let value: Int64
      init(value: Int64) {
        self.value = value
      }
      init(_jsonValue value: JSONValue) throws {
        self.value = value as! Int64
      }
      var _jsonValue: JSONValue { value }
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("customScalar", GivenCustomScalar.self)] }
    }
    let object: JSONObject = ["customScalar": Int64(989561700)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.customScalar).to(equal(GivenCustomScalar(value: 989561700)))
  }

  // MARK: Optional Scalar
  
  func test__optional_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String?.self)] }
    }
    let object: JSONObject = ["name": "Luke Skywalker"]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__optional_scalar__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String?.self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["name"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__optional_scalar__givenDataHasNullValueForField_returnsNilValueForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String?.self)] }
    }
    let object: JSONObject = ["name": NSNull()]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.name).to(beNil())
  }

  func test__optional_scalar__givenDataWithTypeConvertibleToFieldType_getsConvertedValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String?.self)] }
    }
    let object: JSONObject = ["name": 10]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.name).to(equal("10"))
  }

  func test__optional_scalar__givenDataWithTypeNotConvertibleToFieldType_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("name", String?.self)] }
    }
    let object: JSONObject = ["name": false]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["name"]))
        expect(value as? Bool).to(beFalse())
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: Nonnull Enum Value

  private enum MockEnum: String, EnumType {
    case SMALL
    case MEDIUM
    case LARGE
  }

  func test__nonnull_enum__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("size", GraphQLEnum<MockEnum>.self)] }
    }
    let object: JSONObject = ["size": "SMALL"]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.size).to(equal(GraphQLEnum(MockEnum.SMALL)))
  }

  func test__nonnull_enum__givenDataIsNotAnEnumCase_getsValueAsUnknownCase() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("size", GraphQLEnum<MockEnum>.self)] }
    }
    let object: JSONObject = ["size": "GIGANTIC"]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.size).to(equal(GraphQLEnum<MockEnum>.unknown("GIGANTIC")))
  }

  func test__nonnull_enum__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("size", GraphQLEnum<MockEnum>.self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["size"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__nonnull_enum__givenDataHasNullValueForField_throwsNullValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("size", GraphQLEnum<MockEnum>.self)
      ]}
    }
    let object: JSONObject = ["size": NSNull()]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["size"]))
      expect(error.underlying).to(matchError(JSONDecodingError.nullValue))
    })
  }

  func test__nonnull_enum__givenDataWithType_Int_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("size", GraphQLEnum<MockEnum>.self)] }
    }
    let object: JSONObject = ["size": 10]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["size"]))
        expect(value as? Int).to(equal(10))
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  func test__nonnull_enum__givenDataWithType_Double_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("size", GraphQLEnum<MockEnum>.self)] }
    }
    let object: JSONObject = ["size": 10.0]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["size"]))
        expect(value as? Double).to(equal(10.0))
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: NonNull List Of NonNull Scalar

  func test__nonnull_list_nonnull_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = ["favorites": ["Purple", "Potatoes", "iPhone"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["Purple", "Potatoes", "iPhone"]))
  }
  
  func test__nonnull_list_nonnull_scalar__givenEmptyDataArray_getsValueAsEmptyArray() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = ["favorites": [] as JSONValue]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(Array<String>()))
  }

  func test__nonnull_list_nonnull_scalar__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }.to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["favorites"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__nonnull_list_nonnull_scalar__givenDataIsNullForField_throwsNullValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = ["favorites": NSNull()]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }.to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["favorites"]))
      expect(error.underlying).to(matchError(JSONDecodingError.nullValue))
    })
  }

  func test__nonnull_list_nonnull_scalar__givenDataWithElementTypeConvertibleToFieldType_getsConvertedValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = ["favorites": [10, 20, 30]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["10", "20", "30"]))
  }

  func test__nonnull_list_nonnull_enum__givenDataWithStringsNotEnumValue_getsValueAsUnknownCase() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("favorites", [GraphQLEnum<MockEnum>].self)
      ] }
    }
    let object: JSONObject = ["favorites": ["10", "20", "30"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal([
      GraphQLEnum<MockEnum>.unknown("10"),
      GraphQLEnum<MockEnum>.unknown("20"),
      GraphQLEnum<MockEnum>.unknown("30")
    ]))
  }

  func test__nonnull_list_nonnull_scalar__givenDataWithElementTypeNotConvertibleToFieldType_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String].self)] }
    }
    let object: JSONObject = ["favorites": [true, false, true]]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["favorites", "0"]))
        expect(value as? Bool).to(beTrue())
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: Optional List Of NonNull Scalar

  func test__optional_list_nonnull_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = ["favorites": ["Purple", "Potatoes", "iPhone"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["Purple", "Potatoes", "iPhone"]))
  }
  
  func test__optional_list_nonnull_scalar__givenEmptyDataArray_getsValueAsEmptyArray() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = ["favorites": [] as JSONValue]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(Array<String>()))
  }

  func test__optional_list_nonnull_scalar__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["favorites"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__optional_list_nonnull_scalar__givenDataIsNullForField_valueIsNil() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = ["favorites": NSNull()]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(beNil())
  }

  func test__optional_list_nonnull_scalar__givenDataWithElementTypeConvertibleToFieldType_getsConvertedValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = ["favorites": [10, 20, 30]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["10", "20", "30"]))
  }

  func test__optional_list_nonnull_scalar__givenDataWithElementTypeNotConvertibleToFieldType_throwsCouldNotConvertError() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String]?.self)] }
    }
    let object: JSONObject = ["favorites": [true, false, false]]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["favorites", "0"]))
        expect(value as? Bool).to(beTrue())
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: NonNull List Of Optional Scalar

  func test__nonnull_list_optional_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?].self)] }
    }
    let object: JSONObject = ["favorites": ["Purple", "Potatoes", "iPhone"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["Purple", "Potatoes", "iPhone"]))
  }

  func test__nonnull_list_optional_scalar__givenEmptyDataArray_getsValueAsEmptyArray() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?].self)] }
    }
    let object: JSONObject = ["favorites": [] as JSONValue]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(Array<String>()))
  }

  func test__nonnull_list_optional_scalar__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?].self)] }
    }
    let object: JSONObject = [:]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["favorites"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__nonnull_list_nonnull_optional__givenDataIsNullForField_throwsNullValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?].self)] }
    }
    let object: JSONObject = ["favorites": NSNull()]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["favorites"]))
      expect(error.underlying).to(matchError(JSONDecodingError.nullValue))
    })
  }

  func test__nonnull_list_nonnull_optional__givenDataIsArrayWithNullElement_valueIsArrayWithValuesIncludingNilElement() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?].self)] }
    }
    let object: JSONObject = ["favorites": ["Red", NSNull(), "Bird"] as JSONValue]

    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites! as [String?]).to(equal(["Red", nil, "Bird"]))
  }

  // MARK: Optional List Of Optional Scalar

  func test__optional_list_optional_scalar__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [.field("favorites", [String?]?.self)] }
    }
    let object: JSONObject = ["favorites": ["Purple", "Potatoes", "iPhone"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal(["Purple", "Potatoes", "iPhone"]))
  }

  func test__optional_list_optional_enum__givenDataWithUnknownEnumCaseElement_getsValueWithUnknownEnumCaseElement() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("favorites", [GraphQLEnum<MockEnum>?]?.self)
      ] }
    }
    let object: JSONObject = ["favorites": ["Purple"]]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.favorites).to(equal([GraphQLEnum<MockEnum>.unknown("Purple")]))
  }

  func test__optional_list_optional_enum__givenDataWithNonConvertibleTypeElement_getsValueWithUnknownEnumCaseElement() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] { [
        .field("favorites", [GraphQLEnum<MockEnum>?]?.self)
      ] }
    }
    let object: JSONObject = ["favorites": [10]]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      if case JSONDecodingError.couldNotConvert(let value, let expectedType) = error.underlying {
        expect(error.path).to(equal(["favorites", "0"]))
        expect(value as? Int).to(equal(10))
        expect(expectedType == String.self).to(beTrue())
      }
    })
  }

  // MARK: Nonnull Nested Selection Set

  func test__nonnull_nestedObject__givenData_getsValue() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("child", Child.self)
      ]}

      class Child: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }
    let object: JSONObject = [
      "child": [
        "__typename": "Child",
        "name": "Luke Skywalker"
      ]
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.child?.name).to(equal("Luke Skywalker"))
  }

  func test__nonnull_nestedObject__givenDataMissingKeyForField_throwsMissingValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("child", Child.self)
      ]}

      class Child: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }
    let object: JSONObject = ["child": ["__typename": "Child"]]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["child", "name"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__nonnull_nestedObject__givenDataHasNullValueForField_throwsNullValueError() async {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("child", Child.self)
      ]}

      class Child: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }
    let object: JSONObject = [
      "child": [
        "__typename": "Child",
        "name": NSNull()
      ] as JSONValue
    ]

    // when
    await expect { try await Self.readValues(GivenSelectionSet.self, from: object) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["child", "name"]))
      expect(error.underlying).to(matchError(JSONDecodingError.nullValue))
    })
  }

  // MARK: - Inline Fragments

  @MainActor func test__inlineFragment__withoutTypenameMatchingCondition_selectsTypeCaseField() async throws {
    // given
    struct Types {
      static let Human = Object(typename: "Human", implementedInterfaces: [])
      static let MockChildObject = Object(typename: "MockChildObject", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata
      override class var __parentType: any ParentType { Object.mock }
      override class var __selections: [Selection] {[
        .field("child", Child.self),
      ]}

      class Child: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.MockChildObject }
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .inlineFragment(AsHuman.self)
        ]}

        class AsHuman: MockTypeCase, @unchecked Sendable {
          override class var __parentType: any ParentType { Types.Human }
          override class var __selections: [Selection] {[
            .field("name", String.self),
          ]}
        }
      }
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ typeName in
      switch typeName {
      case "Human":
        return Types.Human
      default:
        fail()
        return nil
      }
    })

    let object: JSONObject = [
      "child": [
        "__typename": "Human",
        "name": "Han Solo"
      ]
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.child?.__typename).to(equal("Human"))
    expect(data.child?.name).to(equal("Han Solo"))
  }

  func test__inlineFragment__givenDataForDeferredSelection_doesNotSelectDeferredFields() async throws {
    // given
    class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(DeferredSpecies.self, label: "deferreSpecies"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredSpecies = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredSpecies: DeferredSpecies?
        }

        class DeferredSpecies: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("species", String.self),
          ]}
        }
      }
    }

    let object: JSONObject = [
      "animal": [
        "__typename": "Animal",
        "name": "Dog",
        "species": "Canis familiaris",
      ]
    ]

    // when
    let data = try await Self.readValues(AnAnimal.self, from: object)

    // then
    expect(data.animal.__typename).to(equal("Animal"))
    expect(data.animal.name).to(equal("Dog"))

    expect(data.animal.fragments.$deferredSpecies).to(equal(.pending))
    expect(data.animal.fragments.deferredSpecies?.species).to(beNil())
  }

  // MARK: Deferred Inline Fragments

  func test__deferredInlineFragment__givenPartialDataForSelection_withConditionEvaluatingTrue_collectsDeferredFragment() async throws {
    // given
    class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(if: "varA", DeferredSpecies.self, label: "deferredSpecies"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredSpecies = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredSpecies: DeferredSpecies?
        }

        class DeferredSpecies: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("species", String.self),
          ]}
        }
      }
    }

    let object: JSONObject = [
      "animal": [
        "__typename": "Animal",
        "name": "Lassie"
      ]
    ]

    // when
    let data = try await Self.readValues(AnAnimal.self, from: object, variables: ["varA": true])

    // then
    expect(data.animal.__typename).to(equal("Animal"))
    expect(data.animal.name).to(equal("Lassie"))

    expect(data.animal.__data._deferredFragments).to(equal([ObjectIdentifier(AnAnimal.Animal.DeferredSpecies.self)]))
    expect(data.animal.__data._fulfilledFragments).to(equal([ObjectIdentifier(AnAnimal.Animal.self)]))
  }

  func test__deferredInlineFragment__givenPartialDataForSelection_withConditionEvaluatingFalse_doesCollectFulfilledFragmentAndFields() async throws {
    // given
    class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(if: "varA", DeferredSpecies.self, label: "deferredSpecies"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredSpecies = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredSpecies: DeferredSpecies?
        }

        class DeferredSpecies: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("species", String.self),
          ]}
        }
      }
    }

    let object: JSONObject = [
      "animal": [
        "__typename": "Animal",
        "name": "Lassie",
        "species": "Canis familiaris",
      ]
    ]

    // when
    let data = try await Self.readValues(AnAnimal.self, from: object, variables: ["varA": false])

    // then
    expect(data.animal.__typename).to(equal("Animal"))
    expect(data.animal.name).to(equal("Lassie"))
    expect(data.animal.fragments.deferredSpecies?.species).to(equal("Canis familiaris"))

    expect(data.animal.__data._deferredFragments.isEmpty).to(beTrue())
    expect(data.animal.__data._fulfilledFragments).to(equal([
      ObjectIdentifier(AnAnimal.Animal.self),
      ObjectIdentifier(AnAnimal.Animal.DeferredSpecies.self)
    ]))
  }

  func test__deferredInlineFragment__givenPartialDataForSelection_withConditionEvaluatingFalse_whenMissingDeferredIncrementalData_shouldThrow() async throws {
    // given
    class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(if: "varA", DeferredSpecies.self, label: "deferredSpecies"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredSpecies = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredSpecies: DeferredSpecies?
        }

        class DeferredSpecies: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("species", String.self),
          ]}
        }
      }
    }

    let object: JSONObject = [
      "animal": [
        "__typename": "Animal",
        "name": "Lassie"
      ]
    ]

    // when + then
    await expect { try await Self.readValues(AnAnimal.self, from: object, variables: ["varA": false]) }
      .to(throwError { (error: GraphQLExecutionError) in
      // then
      expect(error.path).to(equal(["animal.species"]))
      expect(error.underlying).to(matchError(JSONDecodingError.missingValue))
    })
  }

  func test__deferredInlineFragment__givenIncrementalDataForDeferredSelection_selectsFieldsAndFulfillsFragment() async throws {
    // given
    class AnAnimal: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __selections: [Selection] {[
        .field("animal", Animal.self),
      ]}

      var animal: Animal { __data["animal"] }

      class Animal: AbstractMockSelectionSet<Animal.Fragments, MockSchemaMetadata>, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .deferred(DeferredSpecies.self, label: "deferredSpecies"),
        ]}

        struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) {
            __data = _dataDict
            _deferredSpecies = Deferred(_dataDict: _dataDict)
          }

          @Deferred var deferredSpecies: DeferredSpecies?
        }

        class DeferredSpecies: MockTypeCase, @unchecked Sendable {
          override class var __selections: [Selection] {[
            .field("species", String.self),
          ]}
        }
      }
    }

    let object: JSONObject = [
      "species": "Canis familiaris",
    ]

    // when
    let data = try await Self.readValues(AnAnimal.Animal.DeferredSpecies.self, in: MockQuery<AnAnimal>.self, from: object)

    // then
    expect(data.species).to(equal("Canis familiaris"))

    expect(data.__data._fulfilledFragments).to(equal([ObjectIdentifier(AnAnimal.Animal.DeferredSpecies.self)]))
    expect(data.__data._deferredFragments).to(beEmpty())
  }

  // MARK: - Fragments

  @MainActor func test__fragment__asObjectType_matchingParentType_selectsFragmentFields() async throws {
    // given
    struct Types {
      static let MockChildObject = Object(typename: "MockChildObject", implementedInterfaces: [])
    }

    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __parentType: any ParentType { Types.MockChildObject }
      override class var __selections: [Selection] {[
        .field("child", Child.self)
      ]}

      class Child: MockSelectionSet, @unchecked Sendable {
        override class var __selections: [Selection] {[
          .field("name", String.self)
        ]}
      }
    }

    class GivenSelectionSet: AbstractMockSelectionSet<GivenSelectionSet.Fragments, MockSchemaMetadata>, @unchecked Sendable {
      override class var __parentType: any ParentType { Types.MockChildObject }
      override class var __selections: [Selection] {[
        .fragment(GivenFragment.self)
      ]}

      struct Fragments: FragmentContainer {
        let __data: DataDict
        var childFragment: GivenFragment { _toFragment() }

        init(_dataDict: DataDict) { __data = _dataDict }
      }
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in return Types.MockChildObject })

    let object: JSONObject = [
      "__typename": "MockChildObject",
      "child": [
        "__typename": "Human",
        "name": "Han Solo"
      ]
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object)

    // then
    expect(data.child?.name).to(equal("Han Solo"))
    expect(data.fragments.childFragment.child?.name).to(equal("Han Solo"))
  }

  // MARK: - Boolean Conditions

  // MARK: Include

  func test__booleanCondition_include_singleField__givenVariableIsTrue_getsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_include_singleField__givenVariableIsFalse_doesNotGetsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_include_singleField__givenGraphQLNullableVariableIsTrue_getsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": GraphQLNullable<Bool>(true)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_include_singleField__givenGraphQLNullableVariableIsFalse_doesNotGetsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": GraphQLNullable<Bool>(false)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_multipleIncludes_singleField__givenAllVariablesAreTrue_getsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "one" || "two", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["one": true, "two": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_include_singleField__givenVariableIsFalse_givenOtherSelection_doesNotGetsValueForConditionalField_doesGetOtherSelection() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("id", String.self),
        .include(if: "variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(equal("1234"))
  }

  func test__booleanCondition_include_multipleFields__givenVariableIsTrue_getsValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
    expect(data.id).to(equal("1234"))
  }

  func test__booleanCondition_include_multipleFields__givenVariableIsFalse_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "variable", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(beNil())
  }

  func test__booleanCondition_include_fragment__givenVariableIsTrue_getsValuesForFragmentFields() async throws {
    // given
    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("name", String.self),
      ]}
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("id", String.self),
        .include(if: "variable", .fragment(GivenFragment.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_include_fragment__givenVariableIsFalse_doesNotGetValuesForFragmentFields() async throws {
    // given
    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("name", String.self),
      ]}
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("id", String.self),
        .include(if: "variable", .fragment(GivenFragment.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(beNil())
  }

  @MainActor func test__booleanCondition_include_typeCase__givenVariableIsTrue_typeCaseMatchesParentType_getsValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .include(if: "variable", .inlineFragment(AsPerson.self))
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .field("name", String.self),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Types.Person })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(equal("Luke Skywalker"))
  }

  @MainActor func test__booleanCondition_include_typeCase__givenVariableIsFalse_typeCaseMatchesParentType_doesNotGetValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .include(if: "variable", .inlineFragment(AsPerson.self))
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .field("name", String.self),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Types.Person })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(beNil())
  }

  @MainActor func test__booleanCondition_include_typeCase__givenVariableIsTrue_typeCaseDoesNotMatchParentType_doesNotGetValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .include(if: "variable", .inlineFragment(AsPerson.self))
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .field("name", String.self),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Object.mock })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(beNil())
  }

  @MainActor func test__booleanCondition_include_singleFieldOnNestedTypeCase__givenVariableIsTrue_typeCaseMatchesParentType_getsValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .inlineFragment(AsPerson.self)
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .include(if: "variable", .field("name", String.self)),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Types.Person })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(equal("Luke Skywalker"))
  }

  @MainActor func test__booleanCondition_include_singleFieldOnNestedTypeCase__givenVariableIsFalse_typeCaseMatchesParentType_getsValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .inlineFragment(AsPerson.self)
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .include(if: "variable", .field("name", String.self)),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Types.Person })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(beNil())
  }

  @MainActor func test__booleanCondition_include_typeCaseOnNamedFragment__givenVariableIsTrue_typeCaseMatchesParentType_getsValuesForTypeCaseFields() async throws {
    // given
    struct Types {
      static let Person = Object(typename: "Person", implementedInterfaces: [])
    }

    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("name", String.self),
      ]}
    }
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("id", String.self),
        .include(if: "variable", .inlineFragment(AsPerson.self))
      ]}

      class AsPerson: MockTypeCase, @unchecked Sendable {
        override class var __parentType: any ParentType { Types.Person }
        override class var __selections: [Selection] {[
          .fragment(GivenFragment.self),
        ]}
      }
    }
    MockSchemaMetadata.stub_objectTypeForTypeName({ _ in Types.Person })
    let object: JSONObject = [
      "__typename": "Person",
      "name": "Luke Skywalker",
      "id": "1234"
    ]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.id).to(equal("1234"))
    expect(data.name).to(equal("Luke Skywalker"))
  }

  // MARK: Skip

  func test__booleanCondition_skip_singleField__givenVariableIsFalse_getsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_skip_singleField__givenVariableIsTrue_doesNotGetsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_skip_singleField__givenGraphQLNullableVariableIsFalse_getsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": GraphQLNullable<Bool>(false)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_skip_singleField__givenGraphQLNullableVariableIsTrue_doesNotGetsValueForConditionalField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": GraphQLNullable<Bool>(true)]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_skip_multipleFields__givenVariableIsFalse_getsValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": false]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
    expect(data.id).to(equal("1234"))
  }

  func test__booleanCondition_skip_multipleFields__givenVariableIsTrue_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(beNil())
  }

  func test__booleanCondition_skip_singleField__givenVariableIsTrue_givenFieldIdSelectedByAnotherSelection_getsValueForField() async throws {
    // given
    class GivenFragment: MockFragment, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .field("name", String.self),
      ]}
    }

    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"variable", .field("name", String.self)),
        .fragment(GivenFragment.self)
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker"]
    let variables = ["variable": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  // MARK: Skip & Include
  /// Compliance with spec: https://spec.graphql.org/draft/#note-f3059

  func test__booleanCondition_bothSkipAndInclude_multipleFields__givenSkipIsTrue_includeIsTrue_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip" && "include", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = ["skip": true,
                     "include": true]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(beNil())
  }

  func test__booleanCondition_bothSkipAndInclude_multipleFields__givenSkipIsTrue_includeIsFalse_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip" && "include", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": true,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(beNil())
  }

  func test__booleanCondition_bothSkipAndInclude_multipleFields__givenSkipIsFalse_includeIsFalse_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip" && "include", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
    expect(data.id).to(beNil())
  }

  func test__booleanCondition_bothSkipAndInclude_multipleFields__givenSkipIsFalse_includeIsTrue_getValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip" && "include", [
          .field("name", String.self),
          .field("id", String.self),
        ])
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": true
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
    expect(data.id).to(equal("1234"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelection__givenSkipIsTrue_includeIsTrue_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip", .field("name", String.self)),
        .include(if: "include", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": true,
      "include": true
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelectionMergedAsOrCondition__givenSkipIsTrue_includeIsTrue_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "include" || !"skip", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": true,
      "include": true
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelection__givenSkipIsFalse_includeIsFalse_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip", .field("name", String.self)),
        .include(if: "include", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelectionMergedAsOrCondition__givenSkipIsFalse_includeIsFalse_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "include" || !"skip", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelection__givenSkipIsFalse_includeIsTrue_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip", .field("name", String.self)),
        .include(if: "include", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": true
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelectionMergedAsOrCondition__givenSkipIsFalse_includeIsTrue_getsValuesForField() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "include" || !"skip", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": false,
      "include": true
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(equal("Luke Skywalker"))
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelection__givenSkipIsTrue_includeIsFalse_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: !"skip", .field("name", String.self)),
        .include(if: "include", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": true,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_bothSkipAndInclude_onSeperateFieldsForSameSelectionMergedAsOrCondition__givenSkipIsTrue_includeIsFalse_doesNotGetValuesForConditionalFields() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: "include" || !"skip", .field("name", String.self))
      ]}
    }
    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]
    let variables = [
      "skip": true,
      "include": false
    ]

    // when
    let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: variables)

    // then
    expect(data.name).to(beNil())
  }

  func test__booleanCondition_bothSkipAndInclude_mergedAsComplexLogicalCondition_correctlyEvaluatesConditionalSelections() async throws {
    // given
    class GivenSelectionSet: MockSelectionSet, @unchecked Sendable {
      override class var __selections: [Selection] {[
        .include(if: ("a" && !"b" && "c") || "d" || !"e", .field("name", String?.self))
      ]}

      var name: String? { __data["name"] }
    }

    let tests: [(variables: [String: Bool], expectedResult: Bool)] = [
      (["a": true,  "b": false, "c": true,  "d": true,  "e": true],  true),  // a && b && c -> true
      (["a": false, "b": false, "c": true,  "d": false, "e": true],  false), // a is false
      (["a": true,  "b": true,  "c": true,  "d": false, "e": true],  false), // b is true
      (["a": true,  "b": false, "c": false, "d": false, "e": true],  false), // c is false
      (["a": false, "b": false, "c": false, "d": true,  "e": true],  true),  // d is true
      (["a": false, "b": false, "c": false, "d": false, "e": false], true),  // e is false
      (["a": false, "b": false, "c": false, "d": true,  "e": true],  true),  // d is true
      (["a": false, "b": false, "c": false, "d": false, "e": true],  false), // e is true
    ]

    let object: JSONObject = ["name": "Luke Skywalker", "id": "1234"]

    for test in tests {
      // when
      let data = try await Self.readValues(GivenSelectionSet.self, from: object, variables: test.variables)

      // then
      if test.expectedResult {
        expect(data.name).to(equal("Luke Skywalker"))
      } else {
        expect(data.name).to(beNil())
      }
    }
  }

  // MARK: Fulfilled Fragment Tests

  @MainActor func test__nestedEntity_andTypeCaseWithAdditionalMergedNestedEntityFields_givenChildEntityCanConvertToTypeCase_fulfilledFragmentsContainsTypeCase() async throws {
    struct Types {
      static let Character = Interface(name: "Character", implementingObjects: ["Human"])
      static let Hero = Interface(name: "Hero", implementingObjects: ["Human"])
      static let Human = Object(typename: "Human", implementedInterfaces: [Character.self, Hero.self])
    }

    MockSchemaMetadata.stub_objectTypeForTypeName({
      switch $0 {
      case "Human": return Types.Human
      default: fail(); return nil
      }
    })

    class Character: MockSelectionSet, @unchecked Sendable {
      typealias Schema = MockSchemaMetadata

      override class var __parentType: any ParentType { Types.Character }
      override class var __selections: [Selection] {[
        .field("__typename", String.self),
        .field("friend", Friend.self),
        .inlineFragment(AsHero.self)
      ]}

      var friend: Friend { __data["friend"] }

      class Friend: MockSelectionSet, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Character }
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
        ]}
      }

      class AsHero: ConcreteMockTypeCase<Character>, @unchecked Sendable {
        typealias Schema = MockSchemaMetadata

        override class var __parentType: any ParentType { Types.Hero }
        override class var __selections: [Selection] {[
          .field("friend", Friend.self),
        ]}

        var friend: Friend { __data["friend"] }

        class Friend: MockSelectionSet, @unchecked Sendable {
          typealias Schema = MockSchemaMetadata

          override class var __parentType: any ParentType { Types.Character }
          override class var __selections: [Selection] {[
            .field("heroName", String.self),
          ]}

          var heroName: String? { __data["heroName"] }
        }
      }

    }

    let jsonObject: JSONObject = [
      "__typename": "Human", "friend": [
        "__typename": "Human",
        "name": "Han",
        "heroName": "Han Solo"
      ]
    ]

    let data = try await Character(data: jsonObject)
    expect(data.friend.__data.fragmentIsFulfilled(Character.Friend.self)).to(beTrue())
    expect(data.friend.__data.fragmentIsFulfilled(Character.AsHero.Friend.self)).to(beTrue())
  }
}
