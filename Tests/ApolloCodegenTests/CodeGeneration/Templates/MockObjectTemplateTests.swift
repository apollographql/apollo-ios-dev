import XCTest
import Nimble
import GraphQLCompiler
@testable import IR
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers

class MockObjectTemplateTests: XCTestCase {

  var ir: IRBuilder!
  var subject: MockObjectTemplate!

  override func tearDown() {
    subject = nil
    ir = nil

    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubject(
    name: String = "Dog",
    customName: String? = nil,
    interfaces: [GraphQLInterfaceType] = [],
    fields: [String : GraphQLField] = [:],
    schemaNamespace: String = "TestSchema",
    moduleType: ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType = .swiftPackage(),
    testMocks: ApolloCodegenConfiguration.TestMockFileOutput = .swiftPackage(),
    warningsOnDeprecatedUsage: ApolloCodegenConfiguration.Composition = .exclude
  ) {
    let config = ApolloCodegenConfiguration.mock(
      schemaNamespace: schemaNamespace,
      output: .mock(moduleType: moduleType, testMocks: testMocks),
      options: .init(warningsOnDeprecatedUsage: warningsOnDeprecatedUsage)
    )
    ir = IRBuilder.mock(compilationResult: .mock())

    let objectType = GraphQLObjectType.mock(
      name,
      interfaces: interfaces
    )
    objectType.name.customName = customName
    subject = MockObjectTemplate(
      graphqlObject: objectType,
      fields: fields
        .map { ($0.key, $0.value.type, $0.value.deprecationReason) },
      config: ApolloCodegen.ConfigurationContext(config: config),
      ir: ir
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: Boilerplate tests

  func test__target__isTestMockFile() {
    buildSubject()

    expect(self.subject.target).to(equal(.testMockFile))
  }

  func test__render__givenSchemaType_generatesExtension() {
    // given
    buildSubject(name: "Dog", moduleType: .swiftPackage())

    let expected = """
    public final class Dog: MockObject {
      public static let objectType: ApolloAPI.Object = TestSchema.Objects.Dog
      public static let _mockFields = MockFields()
      public typealias MockValueCollectionType = Array<Mock<Dog>>

      public struct MockFields: Sendable {
      }
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: Casing Tests

  func test__render__givenSchemaTypeWithLowercaseName_generatesCapitalizedClassName() {
    // given
    buildSubject(name: "dog")

    let expected = """
    public final class Dog: MockObject {
      public static let objectType: ApolloAPI.Object = TestSchema.Objects.Dog
      public static let _mockFields = MockFields()
      public typealias MockValueCollectionType = Array<Mock<Dog>>

      public struct MockFields: Sendable {
      }
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenLowercasedSchemaName_generatesFirstUppercasedSchemaNameReferences() {
    // given
    buildSubject(schemaNamespace: "lowercased")

    let expected = """
      public static let objectType: ApolloAPI.Object = Lowercased.Objects.Dog
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  func test__render__givenUppercasedSchemaName_generatesCapitalizedSchemaNameReferences() {
    // given
    buildSubject(schemaNamespace: "UPPER")

    let expected = """
      public static let objectType: ApolloAPI.Object = UPPER.Objects.Dog
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  func test__render__givenCapitalizedSchemaName_generatesCapitalizedSchemaNameReferences() {
    // given
    buildSubject(schemaNamespace: "MySchema")

    let expected = """
      public static let objectType: ApolloAPI.Object = MySchema.Objects.Dog
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 2, ignoringExtraLines: true))
  }

  // MARK: Mock Field Tests

  func test__render__givenSchemaType_generatesFieldAccessors() {
    // given
    let Cat: GraphQLType = .entity(.mock("Cat"))

    buildSubject(
      fields: [
        "string": .mock("string", type: .nonNull(.string())),
        "customScalar": .mock("customScalar", type: .nonNull(.scalar(.mock(name: "CustomScalar")))),
        "optionalString": .mock("optionalString", type: .string()),
        "object": .mock("object", type: Cat),
        "objectList": .mock("objectList", type: .list(.nonNull(Cat))),
        "objectNestedList": .mock("objectNestedList", type: .list(.nonNull(.list(.nonNull(Cat))))),
        "objectOptionalList": .mock("objectOptionalList", type: .list(Cat)),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<TestSchema.CustomScalar>("customScalar") public var customScalar
        @Field<Cat>("object") public var object
        @Field<[Cat]>("objectList") public var objectList
        @Field<[[Cat]]>("objectNestedList") public var objectNestedList
        @Field<[Cat?]>("objectOptionalList") public var objectOptionalList
        @Field<String>("optionalString") public var optionalString
        @Field<String>("string") public var string
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render__givenFieldsWithLowercaseTypeNames_generatesFieldAccessors() {
    // given
    let Cat: GraphQLType = .entity(.mock("cat"))

    buildSubject(
      fields: [
        "customScalar": .mock("customScalar", type: .nonNull(.scalar(.mock(name: "customScalar")))),
        "enumType": .mock("enumType", type: .enum(.mock(name: "enumType"))),
        "object": .mock("object", type: Cat),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<TestSchema.CustomScalar>("customScalar") public var customScalar
        @Field<GraphQLEnum<TestSchema.EnumType>>("enumType") public var enumType
        @Field<Cat>("object") public var object
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render__givenFieldsWithSwiftReservedKeyworkNames_generatesFieldsEscapedWithBackticks() {
    // given
    buildSubject(
      fields: [
        "associatedtype": .mock("associatedtype", type: .nonNull(.string())),
        "class": .mock("class", type: .nonNull(.string())),
        "deinit": .mock("deinit", type: .nonNull(.string())),
        "enum": .mock("enum", type: .nonNull(.string())),
        "extension": .mock("extension", type: .nonNull(.string())),
        "fileprivate": .mock("fileprivate", type: .nonNull(.string())),
        "func": .mock("func", type: .nonNull(.string())),
        "import": .mock("import", type: .nonNull(.string())),
        "init": .mock("init", type: .nonNull(.string())),
        "inout": .mock("inout", type: .nonNull(.string())),
        "internal": .mock("internal", type: .nonNull(.string())),
        "let": .mock("let", type: .nonNull(.string())),
        "operator": .mock("operator", type: .nonNull(.string())),
        "private": .mock("private", type: .nonNull(.string())),
        "precedencegroup": .mock("precedencegroup", type: .nonNull(.string())),
        "protocol": .mock("protocol", type: .nonNull(.string())),
        "Protocol": .mock("Protocol", type: .nonNull(.string())),
        "public": .mock("public", type: .nonNull(.string())),
        "rethrows": .mock("rethrows", type: .nonNull(.string())),
        "static": .mock("static", type: .nonNull(.string())),
        "struct": .mock("struct", type: .nonNull(.string())),
        "subscript": .mock("subscript", type: .nonNull(.string())),
        "typealias": .mock("typealias", type: .nonNull(.string())),
        "var": .mock("var", type: .nonNull(.string())),
        "break": .mock("break", type: .nonNull(.string())),
        "case": .mock("case", type: .nonNull(.string())),
        "catch": .mock("catch", type: .nonNull(.string())),
        "continue": .mock("continue", type: .nonNull(.string())),
        "default": .mock("default", type: .nonNull(.string())),
        "defer": .mock("defer", type: .nonNull(.string())),
        "do": .mock("do", type: .nonNull(.string())),
        "else": .mock("else", type: .nonNull(.string())),
        "fallthrough": .mock("fallthrough", type: .nonNull(.string())),
        "for": .mock("for", type: .nonNull(.string())),
        "guard": .mock("guard", type: .nonNull(.string())),
        "if": .mock("if", type: .nonNull(.string())),
        "in": .mock("in", type: .nonNull(.string())),
        "repeat": .mock("repeat", type: .nonNull(.string())),
        "return": .mock("return", type: .nonNull(.string())),
        "throw": .mock("throw", type: .nonNull(.string())),
        "switch": .mock("switch", type: .nonNull(.string())),
        "where": .mock("where", type: .nonNull(.string())),
        "while": .mock("while", type: .nonNull(.string())),
        "as": .mock("as", type: .nonNull(.string())),
        "false": .mock("false", type: .nonNull(.string())),
        "is": .mock("is", type: .nonNull(.string())),
        "nil": .mock("nil", type: .nonNull(.string())),
        "self": .mock("self", type: .nonNull(.string())),
        "Self": .mock("Self", type: .nonNull(.string())),
        "super": .mock("super", type: .nonNull(.string())),
        "throws": .mock("throws", type: .nonNull(.string())),
        "true": .mock("true", type: .nonNull(.string())),
        "try": .mock("try", type: .nonNull(.string())),
        "Type": .mock("Type", type: .nonNull(.string())),
        "Any": .mock("Any", type: .nonNull(.string())),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<String>("Any") public var `Any`
        @Field<String>("Protocol") public var `Protocol`
        @Field<String>("Self") public var `Self`
        @Field<String>("Type") public var `Type`
        @Field<String>("as") public var `as`
        @Field<String>("associatedtype") public var `associatedtype`
        @Field<String>("break") public var `break`
        @Field<String>("case") public var `case`
        @Field<String>("catch") public var `catch`
        @Field<String>("class") public var `class`
        @Field<String>("continue") public var `continue`
        @Field<String>("default") public var `default`
        @Field<String>("defer") public var `defer`
        @Field<String>("deinit") public var `deinit`
        @Field<String>("do") public var `do`
        @Field<String>("else") public var `else`
        @Field<String>("enum") public var `enum`
        @Field<String>("extension") public var `extension`
        @Field<String>("fallthrough") public var `fallthrough`
        @Field<String>("false") public var `false`
        @Field<String>("fileprivate") public var `fileprivate`
        @Field<String>("for") public var `for`
        @Field<String>("func") public var `func`
        @Field<String>("guard") public var `guard`
        @Field<String>("if") public var `if`
        @Field<String>("import") public var `import`
        @Field<String>("in") public var `in`
        @Field<String>("init") public var `init`
        @Field<String>("inout") public var `inout`
        @Field<String>("internal") public var `internal`
        @Field<String>("is") public var `is`
        @Field<String>("let") public var `let`
        @Field<String>("nil") public var `nil`
        @Field<String>("operator") public var `operator`
        @Field<String>("precedencegroup") public var `precedencegroup`
        @Field<String>("private") public var `private`
        @Field<String>("protocol") public var `protocol`
        @Field<String>("public") public var `public`
        @Field<String>("repeat") public var `repeat`
        @Field<String>("rethrows") public var `rethrows`
        @Field<String>("return") public var `return`
        @Field<String>("self") public var `self`
        @Field<String>("static") public var `static`
        @Field<String>("struct") public var `struct`
        @Field<String>("subscript") public var `subscript`
        @Field<String>("super") public var `super`
        @Field<String>("switch") public var `switch`
        @Field<String>("throw") public var `throw`
        @Field<String>("throws") public var `throws`
        @Field<String>("true") public var `true`
        @Field<String>("try") public var `try`
        @Field<String>("typealias") public var `typealias`
        @Field<String>("var") public var `var`
        @Field<String>("where") public var `where`
        @Field<String>("while") public var `while`
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render__givenFieldType_Interface_named_Actor_generatesFieldsWithNamespace() {
    // given
    let Actor_Interface = GraphQLInterfaceType.mock("Actor")

    buildSubject(
      fields: [
        "actor": .mock("actor", type: .entity(Actor_Interface)),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<MockObject.Actor>("actor") public var actor
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render__givenFieldType_Union_named_Actor_generatesFieldsWithNamespace() {
    // given
    let Actor_Union = GraphQLUnionType.mock("Actor")

    buildSubject(
      fields: [
        "actor": .mock("actor", type: .entity(Actor_Union)),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<MockObject.Actor>("actor") public var actor
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render__givenFieldType_Object_named_Actor_generatesFieldsWithoutNamespace() {
    // given
    let Actor_Object = GraphQLObjectType.mock("Actor")

    buildSubject(
      fields: [
        "actor": .mock("actor", type: .entity(Actor_Object)),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<Actor>("actor") public var actor
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  // MARK: Conflicting Field Name Tests

  func test_render_givenConflictingFieldName_generatesPropertyWithFieldName() {
    // given
    buildSubject(fields: [
      "hash": .mock("hash", type: .nonNull(.string()))
    ])

    let expected = """
      var hash: String? {
        get { _data["hash"] as? String }
        set { _setScalar(newValue, for: \\.hash) }
      }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 12, ignoringExtraLines: true))
  }

  // MARK: Convenience Initializer Tests

  func test__render__givenSchemaType_generatesConvenienceInitializer() {
    // given
    let Cat: GraphQLType = .entity(GraphQLObjectType.mock("Cat"))
    let Animal: GraphQLType = .entity(GraphQLInterfaceType.mock("Animal"))
    let Pet: GraphQLType = .entity(GraphQLUnionType.mock("Pet"))

    buildSubject(
      fields: [
        "string": .mock("string", type: .nonNull(.string())),
        "stringList": .mock("stringList", type: .list(.nonNull(.string()))),
        "stringNestedList": .mock("stringNestedList", type: .list(.list(.nonNull(.string())))),
        "stringOptionalList": .mock("stringOptionalList", type: .list(.string())),
        "customScalar": .mock("customScalar", type: .nonNull(.scalar(.mock(name: "CustomScalar")))),
        "customScalarList": .mock("customScalarList", type: .list(.nonNull(.scalar(.mock(name: "CustomScalar"))))),
        "customScalarOptionalList": .mock("customScalarOptionalList", type: .list(.scalar(.mock(name: "CustomScalar")))),
        "optionalString": .mock("optionalString", type: .string()),
        "object": .mock("object", type: Cat),
        "objectList": .mock("objectList", type: .list(.nonNull(Cat))),
        "objectNestedList": .mock("objectNestedList", type: .list(.nonNull(.list(.nonNull(Cat))))),
        "objectOptionalList": .mock("objectOptionalList", type: .list(Cat)),
        "interface": .mock("interface", type: Animal),
        "interfaceList": .mock("interfaceList", type: .list(.nonNull(Animal))),
        "interfaceNestedList": .mock("interfaceNestedList", type: .list(.nonNull(.list(.nonNull(Animal))))),
        "interfaceOptionalList": .mock("interfaceOptionalList", type: .list(Animal)),
        "union": .mock("union", type: Pet),
        "unionList": .mock("unionList", type: .list(.nonNull(Pet))),
        "unionNestedList": .mock("unionNestedList", type: .list(.nonNull(.list(.nonNull(Pet))))),
        "unionOptionalList": .mock("unionOptionalList", type: .list(Pet)),
        "enumType": .mock("enumType", type: .enum(.mock(name: "enumType"))),
        "enumList": .mock("enumList", type: .list(.nonNull(.enum(.mock(name: "enumType"))))),
        "enumOptionalList": .mock("enumOptionalList", type: .list(.enum(.mock(name: "enumType"))))
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
    }

    public extension Mock where O == Dog {
      convenience init(
        customScalar: TestSchema.CustomScalar = .defaultMockValue,
        customScalarList: [TestSchema.CustomScalar]? = nil,
        customScalarOptionalList: [TestSchema.CustomScalar?]? = nil,
        enumList: [GraphQLEnum<TestSchema.EnumType>]? = nil,
        enumOptionalList: [GraphQLEnum<TestSchema.EnumType>?]? = nil,
        enumType: GraphQLEnum<TestSchema.EnumType>? = nil,
        interface: (any AnyMock)? = nil,
        interfaceList: [(any AnyMock)]? = nil,
        interfaceNestedList: [[(any AnyMock)]]? = nil,
        interfaceOptionalList: [(any AnyMock)?]? = nil,
        object: Mock<Cat>? = nil,
        objectList: [Mock<Cat>]? = nil,
        objectNestedList: [[Mock<Cat>]]? = nil,
        objectOptionalList: [Mock<Cat>?]? = nil,
        optionalString: String? = nil,
        string: String = "",
        stringList: [String]? = nil,
        stringNestedList: [[String]?]? = nil,
        stringOptionalList: [String?]? = nil,
        union: (any AnyMock)? = nil,
        unionList: [(any AnyMock)]? = nil,
        unionNestedList: [[(any AnyMock)]]? = nil,
        unionOptionalList: [(any AnyMock)?]? = nil
      ) {
        self.init()
        _setScalar(customScalar, for: \\.customScalar)
        _setScalarList(customScalarList, for: \\.customScalarList)
        _setScalarList(customScalarOptionalList, for: \\.customScalarOptionalList)
        _setScalarList(enumList, for: \\.enumList)
        _setScalarList(enumOptionalList, for: \\.enumOptionalList)
        _setScalar(enumType, for: \\.enumType)
        _setEntity(interface, for: \\.interface)
        _setList(interfaceList, for: \\.interfaceList)
        _setList(interfaceNestedList, for: \\.interfaceNestedList)
        _setList(interfaceOptionalList, for: \\.interfaceOptionalList)
        _setEntity(object, for: \\.object)
        _setList(objectList, for: \\.objectList)
        _setList(objectNestedList, for: \\.objectNestedList)
        _setList(objectOptionalList, for: \\.objectOptionalList)
        _setScalar(optionalString, for: \\.optionalString)
        _setScalar(string, for: \\.string)
        _setScalarList(stringList, for: \\.stringList)
        _setScalarList(stringNestedList, for: \\.stringNestedList)
        _setScalarList(stringOptionalList, for: \\.stringOptionalList)
        _setEntity(union, for: \\.union)
        _setList(unionList, for: \\.unionList)
        _setList(unionNestedList, for: \\.unionNestedList)
        _setList(unionOptionalList, for: \\.unionOptionalList)
      }
    }

    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 8 + self.subject.fields.count,
      ignoringExtraLines: false)
    )
  }

  func test__render__givenSchemaTypeAndDefaultParameterFlagOn_generatesDefaultValueForRequiredFields() {
    // given
    let aardvark: GraphQLType = .entity(GraphQLObjectType.mock("aardvark"))
    let Cat: GraphQLType = .entity(GraphQLObjectType.mock("Cat"))
    let Animal: GraphQLType = .entity(GraphQLInterfaceType.mock("Animal", implementingObjects: [GraphQLObjectType.mock("Duck")]))
    let Pet: GraphQLType = .entity(GraphQLUnionType.mock("Pet", types: [GraphQLObjectType.mock("Goldfish"), GraphQLObjectType.mock("Hamster")]))

    buildSubject(
      fields: [
        "string": .mock("string", type: .nonNull(.string())),
        "stringList": .mock("stringList", type: .nonNull(.list(.nonNull(.string())))),
        "stringNestedList": .mock("stringNestedList", type: .nonNull(.list(.nonNull(.list(.nonNull(.string())))))),
        "customScalar": .mock("customScalar", type: .nonNull(.scalar(.mock(name: "CustomScalar")))),
        "customScalarList": .mock("customScalarList", type: .nonNull(.list(.nonNull(.scalar(.mock(name: "CustomScalar")))))),
        "lowercaseObject": .mock("object", type: .nonNull(aardvark)),
        "object": .mock("object", type: .nonNull(Cat)),
        "objectList": .mock("objectList", type: .nonNull(.list(.nonNull(Cat)))),
        "objectNestedList": .mock("objectNestedList", type: .nonNull(.list(.nonNull(.list(.nonNull(Cat)))))),
        "interface": .mock("interface", type: .nonNull(Animal)),
        "interfaceList": .mock("interfaceList", type: .nonNull(.list(.nonNull(Animal)))),
        "interfaceNestedList": .mock("interfaceNestedList", type: .nonNull(.list(.nonNull(.list(.nonNull(Animal)))))),
        "union": .mock("union", type: .nonNull(Pet)),
        "unionList": .mock("unionList", type: .nonNull(.list(.nonNull(Pet)))),
        "unionNestedList": .mock("unionNestedList", type: .nonNull(.list(.nonNull(.list(.nonNull(Pet)))))),
        "enumType": .mock("enumType", type: .nonNull(.enum(.mock(name: "enumType", values: ["foo", "bar"])))),
        "enumList": .mock("enumList", type: .nonNull(.list(.nonNull(.enum(.mock(name: "enumType", values: ["foo", "bar"])))))),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
    }

    public extension Mock where O == Dog {
      convenience init(
        customScalar: TestSchema.CustomScalar = .defaultMockValue,
        customScalarList: [TestSchema.CustomScalar] = [],
        enumList: [GraphQLEnum<TestSchema.EnumType>] = [],
        enumType: GraphQLEnum<TestSchema.EnumType> = .case(.foo),
        interface: (any AnyMock) = Mock<Duck>(),
        interfaceList: [(any AnyMock)] = [],
        interfaceNestedList: [[(any AnyMock)]] = [],
        lowercaseObject: Mock<Aardvark> = Mock<Aardvark>(),
        object: Mock<Cat> = Mock<Cat>(),
        objectList: [Mock<Cat>] = [],
        objectNestedList: [[Mock<Cat>]] = [],
        string: String = "",
        stringList: [String] = [],
        stringNestedList: [[String]] = [],
        union: (any AnyMock) = Mock<Goldfish>(),
        unionList: [(any AnyMock)] = [],
        unionNestedList: [[(any AnyMock)]] = []
      ) {
        self.init()
        _setScalar(customScalar, for: \\.customScalar)
        _setScalarList(customScalarList, for: \\.customScalarList)
        _setScalarList(enumList, for: \\.enumList)
        _setScalar(enumType, for: \\.enumType)
        _setEntity(interface, for: \\.interface)
        _setList(interfaceList, for: \\.interfaceList)
        _setList(interfaceNestedList, for: \\.interfaceNestedList)
        _setEntity(lowercaseObject, for: \\.lowercaseObject)
        _setEntity(object, for: \\.object)
        _setList(objectList, for: \\.objectList)
        _setList(objectNestedList, for: \\.objectNestedList)
        _setScalar(string, for: \\.string)
        _setScalarList(stringList, for: \\.stringList)
        _setScalarList(stringNestedList, for: \\.stringNestedList)
        _setEntity(union, for: \\.union)
        _setList(unionList, for: \\.unionList)
        _setList(unionNestedList, for: \\.unionNestedList)
      }
    }

    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 8 + self.subject.fields.count,
      ignoringExtraLines: false)
    )
  }


  func test__render__givenSchemaTypeWithoutFields_doesNotgenerateConvenienceInitializer() {
    // given
    buildSubject(moduleType: .swiftPackage())

    let expected = """
    }
    
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 8 + self.subject.graphqlObject.fields.count,
      ignoringExtraLines: false)
    )
  }

  func test__render__givenFieldsWithSwiftReservedKeyworkNames_generatesConvenienceInitializerParamatersEscapedWithBackticksAndInternalNames() {
    // given
    buildSubject(
      fields: [
        "associatedtype": .mock("associatedtype", type: .nonNull(.string())),
        "class": .mock("class", type: .nonNull(.string())),
        "deinit": .mock("deinit", type: .nonNull(.string())),
        "enum": .mock("enum", type: .nonNull(.string())),
        "extension": .mock("extension", type: .nonNull(.string())),
        "fileprivate": .mock("fileprivate", type: .nonNull(.string())),
        "func": .mock("func", type: .nonNull(.string())),
        "import": .mock("import", type: .nonNull(.string())),
        "init": .mock("init", type: .nonNull(.string())),
        "inout": .mock("inout", type: .nonNull(.string())),
        "internal": .mock("internal", type: .nonNull(.string())),
        "let": .mock("let", type: .nonNull(.string())),
        "operator": .mock("operator", type: .nonNull(.string())),
        "private": .mock("private", type: .nonNull(.string())),
        "precedencegroup": .mock("precedencegroup", type: .nonNull(.string())),
        "protocol": .mock("protocol", type: .nonNull(.string())),
        "Protocol": .mock("Protocol", type: .nonNull(.string())),
        "public": .mock("public", type: .nonNull(.string())),
        "rethrows": .mock("rethrows", type: .nonNull(.string())),
        "static": .mock("static", type: .nonNull(.string())),
        "struct": .mock("struct", type: .nonNull(.string())),
        "subscript": .mock("subscript", type: .nonNull(.string())),
        "typealias": .mock("typealias", type: .nonNull(.string())),
        "var": .mock("var", type: .nonNull(.string())),
        "break": .mock("break", type: .nonNull(.string())),
        "case": .mock("case", type: .nonNull(.string())),
        "catch": .mock("catch", type: .nonNull(.string())),
        "continue": .mock("continue", type: .nonNull(.string())),
        "default": .mock("default", type: .nonNull(.string())),
        "defer": .mock("defer", type: .nonNull(.string())),
        "do": .mock("do", type: .nonNull(.string())),
        "else": .mock("else", type: .nonNull(.string())),
        "fallthrough": .mock("fallthrough", type: .nonNull(.string())),
        "for": .mock("for", type: .nonNull(.string())),
        "guard": .mock("guard", type: .nonNull(.string())),
        "if": .mock("if", type: .nonNull(.string())),
        "in": .mock("in", type: .nonNull(.string())),
        "repeat": .mock("repeat", type: .nonNull(.string())),
        "return": .mock("return", type: .nonNull(.string())),
        "throw": .mock("throw", type: .nonNull(.string())),
        "switch": .mock("switch", type: .nonNull(.string())),
        "where": .mock("where", type: .nonNull(.string())),
        "while": .mock("while", type: .nonNull(.string())),
        "as": .mock("as", type: .nonNull(.string())),
        "false": .mock("false", type: .nonNull(.string())),
        "is": .mock("is", type: .nonNull(.string())),
        "nil": .mock("nil", type: .nonNull(.string())),
        "self": .mock("self", type: .nonNull(.string())),
        "Self": .mock("Self", type: .nonNull(.string())),
        "super": .mock("super", type: .nonNull(.string())),
        "throws": .mock("throws", type: .nonNull(.string())),
        "true": .mock("true", type: .nonNull(.string())),
        "try": .mock("try", type: .nonNull(.string())),
        "Type": .mock("Type", type: .nonNull(.string())),
        "Any": .mock("Any", type: .nonNull(.string())),
      ],
      moduleType: .swiftPackage()
    )

    let expected = """
    }

    public extension Mock where O == Dog {
      convenience init(
        `Any`: String = "",
        `Protocol`: String = "",
        `Self`: String = "",
        `Type`: String = "",
        `as`: String = "",
        `associatedtype`: String = "",
        `break`: String = "",
        `case`: String = "",
        `catch`: String = "",
        `class`: String = "",
        `continue`: String = "",
        `default`: String = "",
        `defer`: String = "",
        `deinit`: String = "",
        `do`: String = "",
        `else`: String = "",
        `enum`: String = "",
        `extension`: String = "",
        `fallthrough`: String = "",
        `false`: String = "",
        `fileprivate`: String = "",
        `for`: String = "",
        `func`: String = "",
        `guard`: String = "",
        `if`: String = "",
        `import`: String = "",
        `in`: String = "",
        `init`: String = "",
        `inout`: String = "",
        `internal`: String = "",
        `is`: String = "",
        `let`: String = "",
        `nil`: String = "",
        `operator`: String = "",
        `precedencegroup`: String = "",
        `private`: String = "",
        `protocol`: String = "",
        `public`: String = "",
        `repeat`: String = "",
        `rethrows`: String = "",
        `return`: String = "",
        `self` self_value: String = "",
        `static`: String = "",
        `struct`: String = "",
        `subscript`: String = "",
        `super`: String = "",
        `switch`: String = "",
        `throw`: String = "",
        `throws`: String = "",
        `true`: String = "",
        `try`: String = "",
        `typealias`: String = "",
        `var`: String = "",
        `where`: String = "",
        `while`: String = ""
      ) {
        self.init()
        _setScalar(`Any`, for: \\.`Any`)
        _setScalar(`Protocol`, for: \\.`Protocol`)
        _setScalar(`Self`, for: \\.`Self`)
        _setScalar(`Type`, for: \\.`Type`)
        _setScalar(`as`, for: \\.`as`)
        _setScalar(`associatedtype`, for: \\.`associatedtype`)
        _setScalar(`break`, for: \\.`break`)
        _setScalar(`case`, for: \\.`case`)
        _setScalar(`catch`, for: \\.`catch`)
        _setScalar(`class`, for: \\.`class`)
        _setScalar(`continue`, for: \\.`continue`)
        _setScalar(`default`, for: \\.`default`)
        _setScalar(`defer`, for: \\.`defer`)
        _setScalar(`deinit`, for: \\.`deinit`)
        _setScalar(`do`, for: \\.`do`)
        _setScalar(`else`, for: \\.`else`)
        _setScalar(`enum`, for: \\.`enum`)
        _setScalar(`extension`, for: \\.`extension`)
        _setScalar(`fallthrough`, for: \\.`fallthrough`)
        _setScalar(`false`, for: \\.`false`)
        _setScalar(`fileprivate`, for: \\.`fileprivate`)
        _setScalar(`for`, for: \\.`for`)
        _setScalar(`func`, for: \\.`func`)
        _setScalar(`guard`, for: \\.`guard`)
        _setScalar(`if`, for: \\.`if`)
        _setScalar(`import`, for: \\.`import`)
        _setScalar(`in`, for: \\.`in`)
        _setScalar(`init`, for: \\.`init`)
        _setScalar(`inout`, for: \\.`inout`)
        _setScalar(`internal`, for: \\.`internal`)
        _setScalar(`is`, for: \\.`is`)
        _setScalar(`let`, for: \\.`let`)
        _setScalar(`nil`, for: \\.`nil`)
        _setScalar(`operator`, for: \\.`operator`)
        _setScalar(`precedencegroup`, for: \\.`precedencegroup`)
        _setScalar(`private`, for: \\.`private`)
        _setScalar(`protocol`, for: \\.`protocol`)
        _setScalar(`public`, for: \\.`public`)
        _setScalar(`repeat`, for: \\.`repeat`)
        _setScalar(`rethrows`, for: \\.`rethrows`)
        _setScalar(`return`, for: \\.`return`)
        _setScalar(self_value, for: \\.`self`)
        _setScalar(`static`, for: \\.`static`)
        _setScalar(`struct`, for: \\.`struct`)
        _setScalar(`subscript`, for: \\.`subscript`)
        _setScalar(`super`, for: \\.`super`)
        _setScalar(`switch`, for: \\.`switch`)
        _setScalar(`throw`, for: \\.`throw`)
        _setScalar(`throws`, for: \\.`throws`)
        _setScalar(`true`, for: \\.`true`)
        _setScalar(`try`, for: \\.`try`)
        _setScalar(`typealias`, for: \\.`typealias`)
        _setScalar(`var`, for: \\.`var`)
        _setScalar(`where`, for: \\.`where`)
        _setScalar(`while`, for: \\.`while`)
      }
    }

    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(
      expected,
      atLine: 8 + self.subject.fields.count,
      ignoringExtraLines: false)
    )
  }

  // MARK: Access Level Tests

  func test__render__givenSchemaTypeAndFields_whenTestMocksIsSwiftPackage_shouldRenderWithPublicAccess() {
    // given
    buildSubject(
      name: "Dog",
      fields: [
        "string": .mock("string", type: .nonNull(.string()))
      ],
      testMocks: .swiftPackage()
    )

    let expectedClassDefinition = """
    public final class Dog: MockObject {
      public static let objectType: ApolloAPI.Object = TestSchema.Objects.Dog
      public static let _mockFields = MockFields()
      public typealias MockValueCollectionType = Array<Mock<Dog>>

      public struct MockFields: Sendable {
    """

    let expectedExtensionDefinition = """
    public extension Mock where O == Dog {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expectedClassDefinition, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedExtensionDefinition, atLine: 11, ignoringExtraLines: true))
  }

  func test__render__givenSchemaType_whenTestMocksAbsolute_withPublicAccessModifier_shouldRenderWithPublicAccess() {
    // given
    buildSubject(
      name: "Dog",
      fields: [
        "string": .mock("string", type: .nonNull(.string()))
      ],
      testMocks: .absolute(path: "", accessModifier: .public)
    )

    let expectedClassDefinition = """
    public final class Dog: MockObject {
      public static let objectType: ApolloAPI.Object = TestSchema.Objects.Dog
      public static let _mockFields = MockFields()
      public typealias MockValueCollectionType = Array<Mock<Dog>>

      public struct MockFields: Sendable {
    """

    let expectedExtensionDefinition = """
    public extension Mock where O == Dog {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expectedClassDefinition, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedExtensionDefinition, atLine: 11, ignoringExtraLines: true))
  }

  func test__render__givenSchemaType_whenTestMocksAbsolute_withInternalAccessModifier_shouldRenderWithInternalAccess() {
    // given
    buildSubject(
      name: "Dog",
      fields: [
        "string": .mock("string", type: .nonNull(.string()))
      ],
      testMocks: .absolute(path: "", accessModifier: .internal)
    )

    let expectedClassDefinition = """
    final class Dog: MockObject {
      static let objectType: ApolloAPI.Object = TestSchema.Objects.Dog
      static let _mockFields = MockFields()
      typealias MockValueCollectionType = Array<Mock<Dog>>

      struct MockFields: Sendable {
    """

    let expectedExtensionDefinition = """
    extension Mock where O == Dog {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expectedClassDefinition, ignoringExtraLines: true))
    expect(actual).to(equalLineByLine(expectedExtensionDefinition, atLine: 11, ignoringExtraLines: true))
  }

  // MARK: - Deprecation Warnings

  func test__render_fieldAccessors__givenWarningsOnDeprecatedUsage_include_hasDeprecatedField_shouldGenerateWarning() throws {
    // given
    buildSubject(
      fields: [
        "string": .mock("string", type: .nonNull(.string()), deprecationReason: "Cause I said so!"),
      ],
      moduleType: .swiftPackage(),
      warningsOnDeprecatedUsage: .include
    )

    let expected = """
      public struct MockFields: Sendable {
        @available(*, deprecated, message: "Cause I said so!")
        @Field<String>("string") public var string
      }
    """
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  func test__render_fieldAccessors__givenWarningsOnDeprecatedUsage_exclude_hasDeprecatedField_shouldNotGenerateWarning() throws {
    // given
    buildSubject(
      fields: [
        "string": .mock("string", type: .nonNull(.string()), deprecationReason: "Cause I said so!"),
      ],
      moduleType: .swiftPackage(),
      warningsOnDeprecatedUsage: .exclude
    )

    let expected = """
      public struct MockFields: Sendable {
        @Field<String>("string") public var string
      }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }
  
  // MARK: - Reserved Keyword Tests
  
  func test__render__givenObjectUsingReservedKeyword_generatesTypeWithSuffix() {
    let keywords = ["Type", "type"]
    
    keywords.forEach { keyword in
      // given
      buildSubject(
        name: keyword,
        fields: [
          "string": .mock("string", type: .nonNull(.string())),
        ],
        moduleType: .swiftPackage()
      )

      let expected = """
      public final class \(keyword.firstUppercased)_Object: MockObject {
        public static let objectType: ApolloAPI.Object = TestSchema.Objects.\(keyword.firstUppercased)_Object
        public static let _mockFields = MockFields()
        public typealias MockValueCollectionType = Array<Mock<\(keyword.firstUppercased)_Object>>

        public struct MockFields: Sendable {
          @Field<String>("string") public var string
        }
      }

      public extension Mock where O == \(keyword.firstUppercased)_Object {
        convenience init(
          string: String = ""
        ) {
          self.init()
          _setScalar(string, for: \\.string)
        }
      }
      """
      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
  // MARK: - Schema Customization Tests
  
  func test__render__givenMockObject_withCustomName_shouldRenderWithCustomName() throws {
    // given
    buildSubject(
      name: "MyObject",
      customName: "MyCustomObject"
    )
    
    let expected = """
    public final class MyCustomObject: MockObject {
      public static let objectType: ApolloAPI.Object = TestSchema.Objects.MyCustomObject
      public static let _mockFields = MockFields()
      public typealias MockValueCollectionType = Array<Mock<MyCustomObject>>
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

}
