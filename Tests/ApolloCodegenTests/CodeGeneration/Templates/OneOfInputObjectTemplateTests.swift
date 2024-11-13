import XCTest
import Nimble
@testable import ApolloCodegenLib
import Apollo
import GraphQLCompiler

class OneOfInputObjectTemplateTests: XCTestCase {
  var subject: OneOfInputObjectTemplate!

  override func tearDownWithError() throws {
    subject = nil
    try super.tearDownWithError()
  }
  
  private func buildSubject(
    name: String = "MockOneOfInput",
    customName: String? = nil,
    fields: [GraphQLInputField] = [],
    isOneOf: Bool = true,
    documentation: String? = nil,
    config: ApolloCodegenConfiguration = .mock(.swiftPackageManager)
  ) {
    let inputObject = GraphQLInputObjectType.mock(
      name,
      fields: fields,
      documentation: documentation,
      config: config,
      isOneOf: isOneOf
    )
    inputObject.name.customName = customName
    
    subject = OneOfInputObjectTemplate(
      graphqlInputObject: inputObject,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }
  
  func test_render_generateOneOfInputObject_withCaseAndInputDictVariable() throws {
    // given
    buildSubject(
      name: "mockOneOfInput",
      fields: [GraphQLInputField.mock("field", type: .scalar(.integer()), defaultValue: nil)]
    )
    
    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case field(Int)
    
      public var __data: InputDict {
        switch self {
        case .field(let value):
          return InputDict(["field": value])
        }
      }
    }
    """
    
    // when
    let actual = renderSubject()
    
    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: Access Level Tests
  
  func test_render_givenOneOfInputObjectWithValidAndDeprecatedFields_whenModuleType_swiftPackageManager_generatesAllWithPublicAccess() throws {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        )
      ],
      config: .mock(.swiftPackageManager)
    )
    
    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
      case fieldTwo(String)
    
      public var __data: InputDict {
        switch self {
        case .fieldOne(let value):
          return InputDict(["fieldOne": value])
        case .fieldTwo(let value):
          return InputDict(["fieldTwo": value])
        }
      }
    }
    """
    
    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test_render_givenOneOfInputObjectWithValidAndDeprecatedFields_whenModuleType_other_generatesAllWithPublicAccess() {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        )
      ],
      config: .mock(.other)
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
      case fieldTwo(String)
    
      public var __data: InputDict {
        switch self {
        case .fieldOne(let value):
          return InputDict(["fieldOne": value])
        case .fieldTwo(let value):
          return InputDict(["fieldTwo": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  func test_render_givenOneOInputObjectWithValidAndDeprecatedFields_whenModuleType_embeddedInTarget_withPublicAccessModifier_generatesAllWithPublicAccess() {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        )
      ],
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .public))
    )

    let expected = """
    enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
      case fieldTwo(String)
    
      public var __data: InputDict {
        switch self {
        case .fieldOne(let value):
          return InputDict(["fieldOne": value])
        case .fieldTwo(let value):
          return InputDict(["fieldTwo": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  func test_render_givenOneOfInputObjectWithValidAndDeprecatedFields_whenModuleType_embeddedInTarget_withInternalAccessModifier_generatesAllWithInternalAccess() {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        )
      ],
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    )

    let expected = """
    enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
      case fieldTwo(String)
    
      var __data: InputDict {
        switch self {
        case .fieldOne(let value):
          return InputDict(["fieldOne": value])
        case .fieldTwo(let value):
          return InputDict(["fieldTwo": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: Casing Tests

  func test__render__givenLowercasedOneOfInputObjectField__generatesCorrectlyCasedSwiftDefinition() throws {
    // given
    buildSubject(
      name: "mockInput",
      fields: [GraphQLInputField.mock("field", type: .scalar(.integer()), defaultValue: nil)]
    )

    let expected = "public enum MockInput: OneOfInputObject {"

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenUppercasedOneOfInputObjectField__generatesCorrectlyCasedSwiftDefinition() throws {
    // given
    buildSubject(
      name: "MOCKInput",
      fields: [GraphQLInputField.mock("field", type: .scalar(.integer()), defaultValue: nil)]
    )

    let expected = "public enum MOCKInput: OneOfInputObject {"

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenMixedCaseOneOfInputObjectField__generatesCorrectlyCasedSwiftDefinition() throws {
    // given
    buildSubject(
      name: "mOcK_Input",
      fields: [GraphQLInputField.mock("field", type: .scalar(.integer()), defaultValue: nil)]
    )

    let expected = "public enum MOcK_Input: OneOfInputObject {"

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  func test__casing__givenSchemaName_generatesWithNoCaseConversion() throws {
    // given
    let fields: [GraphQLInputField] = [
      GraphQLInputField.mock(
        "InputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("InnerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      )
    ]

    buildSubject(
      fields: fields,
      config: .mock(schemaNamespace: "testschema",
                    output: .mock(
                      moduleType: .swiftPackageManager,
                      operations: .relative(subpath: nil)
                    ),
                    options: .init(
                      conversionStrategies: .init(inputObjects: .none)
                    )
                   )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case InputField(Testschema.InnerInputObject)
      case inputField(Testschema.InnerInputObject)
    
      public var __data: InputDict {
        switch self {
        case .InputField(let value):
          return InputDict(["InputField": value])
        case .inputField(let value):
          return InputDict(["inputField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  func test__casing__givenSchemaNameLowercased_nonListField_generatesWithFirstUppercasedNamespace() throws {
    // given
    let fields: [GraphQLInputField] = [
      GraphQLInputField.mock(
        "enumField",
        type: .enum(.mock(name: "EnumValue")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      )
    ]

    buildSubject(
      fields: fields,
      config: .mock(schemaNamespace: "testschema", output: .mock(
        moduleType: .swiftPackageManager,
        operations: .relative(subpath: nil)))
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case enumField(GraphQLEnum<Testschema.EnumValue>)
      case inputField(Testschema.InnerInputObject)
    
      public var __data: InputDict {
        switch self {
        case .enumField(let value):
          return InputDict(["enumField": value])
        case .inputField(let value):
          return InputDict(["inputField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenUppercasedSchemaName_nonListField_generatesWithUppercasedNamespace() throws {
    // given
    let fields: [GraphQLInputField] = [
      GraphQLInputField.mock(
        "enumField",
        type: .enum(.mock(name: "EnumValue")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      )
    ]

    buildSubject(
      fields: fields,
      config: .mock(schemaNamespace: "TESTSCHEMA", output: .mock(
        moduleType: .swiftPackageManager,
        operations: .relative(subpath: nil)))
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case enumField(GraphQLEnum<TESTSCHEMA.EnumValue>)
      case inputField(TESTSCHEMA.InnerInputObject)
    
      public var __data: InputDict {
        switch self {
        case .enumField(let value):
          return InputDict(["enumField": value])
        case .inputField(let value):
          return InputDict(["inputField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenCapitalizedSchemaName_nonListField_generatesWithCapitalizedNamespace() throws {
    // given
    let fields: [GraphQLInputField] = [
      GraphQLInputField.mock(
        "enumField",
        type: .enum(.mock(name: "EnumValue")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      )
    ]

    buildSubject(
      fields: fields,
      config: .mock(schemaNamespace: "TestSchema", output: .mock(
        moduleType: .swiftPackageManager,
        operations: .relative(subpath: nil)))
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case enumField(GraphQLEnum<TestSchema.EnumValue>)
      case inputField(TestSchema.InnerInputObject)
    
      public var __data: InputDict {
        switch self {
        case .enumField(let value):
          return InputDict(["enumField": value])
        case .inputField(let value):
          return InputDict(["inputField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenLowercasedSchemaName_listField_generatesWithFirstUppercasedNamespace() throws {
    // given
    buildSubject(
      fields: [GraphQLInputField.mock(
        "listNullableItem",
        type: .list(.enum(.mock(name: "EnumValue"))),
        defaultValue: nil)],
      config: .mock(
        schemaNamespace: "testschema",
        output: .mock(moduleType: .swiftPackageManager, operations: .relative(subpath: nil))
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case listNullableItem([GraphQLEnum<Testschema.EnumValue>?])
    
      public var __data: InputDict {
        switch self {
        case .listNullableItem(let value):
          return InputDict(["listNullableItem": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenUppercasedSchemaName_listField_generatesWithUppercasedNamespace() throws {
    // given
    buildSubject(
      fields: [GraphQLInputField.mock(
        "listNullableItem",
        type: .list(.enum(.mock(name: "EnumValue"))),
        defaultValue: nil)],
      config: .mock(
        schemaNamespace: "TESTSCHEMA",
        output: .mock(moduleType: .swiftPackageManager, operations: .relative(subpath: nil))
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case listNullableItem([GraphQLEnum<TESTSCHEMA.EnumValue>?])
    
      public var __data: InputDict {
        switch self {
        case .listNullableItem(let value):
          return InputDict(["listNullableItem": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenCapitalizedSchemaName_listField_generatesWithCapitalizedNamespace() throws {
    // given
    buildSubject(
      fields: [GraphQLInputField.mock(
        "listNullableItem",
        type: .list(.enum(.mock(name: "EnumValue"))),
        defaultValue: nil)],
      config: .mock(
        schemaNamespace: "TestSchema",
        output: .mock(moduleType:.swiftPackageManager ,operations: .relative(subpath: nil))
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case listNullableItem([GraphQLEnum<TestSchema.EnumValue>?])
    
      public var __data: InputDict {
        switch self {
        case .listNullableItem(let value):
          return InputDict(["listNullableItem": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: Field Type Tests

  func test__render__givenSingleFieldType__generatesCaseAndDataDict() throws {
    // given
    buildSubject(fields: [
      GraphQLInputField.mock("field", type: .scalar(.string()), defaultValue: nil)
    ])

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case field(String)
    
      public var __data: InputDict {
        switch self {
        case .field(let value):
          return InputDict(["field": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: false))
  }
  
  func test__render__givenSingleFieldTypeInMixedCase__generatesCaseAndDataDictWithCorrectCasing() throws {
    // given
    buildSubject(fields: [
      GraphQLInputField.mock("Field", type: .scalar(.string()), defaultValue: nil)
    ])

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case field(String)
    
      public var __data: InputDict {
        switch self {
        case .field(let value):
          return InputDict(["Field": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: false))
  }
  
  func test__render__givenSingleFieldTypeInAllUppercase__generatesCaseAndDataDictWithCorrectCasing() throws {
    // given
    buildSubject(fields: [
      GraphQLInputField.mock("FIELDNAME", type: .scalar(.string()), defaultValue: nil)
    ])

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case fieldname(String)
    
      public var __data: InputDict {
        switch self {
        case .fieldname(let value):
          return InputDict(["FIELDNAME": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: false))
  }

  func test__render__givenAllPossibleSchemaInputFieldTypes__generatesCasesAndDataDict() throws {
    // given
    buildSubject(fields: [
      GraphQLInputField.mock(
        "stringField",
        type: .scalar(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "intField",
        type: .scalar(.integer()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "boolField",
        type: .scalar(.boolean()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "floatField",
        type: .scalar(.float()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "customScalarField",
        type: .scalar(.mock(name: "CustomScalar")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "lowercaseCustomScalarField",
        type: .scalar(.mock(name: "lowercaseCustomScalar")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "enumField",
        type: .enum(.mock(name: "EnumType")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "lowercaseEnumField",
        type: .enum(.mock(name: "lowercaseEnumType")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "lowercaseInputField",
        type: .inputObject(.mock(
          "lowercaseInnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "listField",
        type: .list(.scalar(.string())),
        defaultValue: nil
      )
    ], config: .mock(.swiftPackageManager, schemaNamespace: "TestSchema"))

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case stringField(String)
      case intField(Int)
      case boolField(Bool)
      case floatField(Double)
      case customScalarField(CustomScalar)
      case lowercaseCustomScalarField(LowercaseCustomScalar)
      case enumField(GraphQLEnum<EnumType>)
      case lowercaseEnumField(GraphQLEnum<LowercaseEnumType>)
      case inputField(InnerInputObject)
      case lowercaseInputField(LowercaseInnerInputObject)
      case listField([String?])
    
      public var __data: InputDict {
        switch self {
        case .stringField(let value):
          return InputDict(["stringField": value])
        case .intField(let value):
          return InputDict(["intField": value])
        case .boolField(let value):
          return InputDict(["boolField": value])
        case .floatField(let value):
          return InputDict(["floatField": value])
        case .customScalarField(let value):
          return InputDict(["customScalarField": value])
        case .lowercaseCustomScalarField(let value):
          return InputDict(["lowercaseCustomScalarField": value])
        case .enumField(let value):
          return InputDict(["enumField": value])
        case .lowercaseEnumField(let value):
          return InputDict(["lowercaseEnumField": value])
        case .inputField(let value):
          return InputDict(["inputField": value])
        case .lowercaseInputField(let value):
          return InputDict(["lowercaseInputField": value])
        case .listField(let value):
          return InputDict(["listField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenSchemaModuleInputFieldTypes__generatesCasesAndDataDict_withNamespaceWhenRequired() throws {
    // given
    let fields: [GraphQLInputField] = [
      GraphQLInputField.mock(
        "enumField",
        type: .enum(.mock(name: "EnumValue")),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inputField",
        type: .inputObject(.mock(
          "InnerInputObject",
          fields: [
            GraphQLInputField.mock("innerStringField", type: .scalar(.string()), defaultValue: nil)
          ]
        )),
        defaultValue: nil
      )
    ]

    let expectedNoNamespace = """
      case enumField(GraphQLEnum<EnumValue>)
      case inputField(InnerInputObject)
    """

    let expectedWithNamespace = """
      case enumField(GraphQLEnum<TestSchema.EnumValue>)
      case inputField(TestSchema.InnerInputObject)
    """

    let tests: [(config: ApolloCodegenConfiguration.FileOutput, expected: String)] = [
      (.mock(moduleType: .swiftPackageManager, operations: .relative(subpath: nil)), expectedWithNamespace),
      (.mock(moduleType: .swiftPackageManager, operations: .absolute(path: "custom")), expectedWithNamespace),
      (.mock(moduleType: .swiftPackageManager, operations: .inSchemaModule), expectedNoNamespace),
      (.mock(moduleType: .other, operations: .relative(subpath: nil)), expectedWithNamespace),
      (.mock(moduleType: .other, operations: .absolute(path: "custom")), expectedWithNamespace),
      (.mock(moduleType: .other, operations: .inSchemaModule), expectedNoNamespace),
      (.mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .relative(subpath: nil)), expectedWithNamespace),
      (.mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .absolute(path: "custom")), expectedWithNamespace),
      (.mock(moduleType: .embeddedInTarget(name: "CustomTarget", accessModifier: .public), operations: .inSchemaModule), expectedNoNamespace)
    ]

    for test in tests {
      // given
      buildSubject(fields: fields, config: .mock(output: test.config))

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(test.expected, atLine: 2, ignoringExtraLines: true))
    }
  }
  
  // MARK: Documentation Tests

  func test__render__givenSchemaDocumentation_include_hasDocumentation_shouldGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      fields: [
        GraphQLInputField.mock("fieldOne",
                               type: .nonNull(.string()),
                               defaultValue: nil,
                               documentation: "Field Documentation!")
      ],
      documentation: documentation,
      config: .mock(.swiftPackageManager, options: .init(schemaDocumentation: .include))
    )

    let expected = """
    /// \(documentation)
    public enum MockOneOfInput: OneOfInputObject {
      /// Field Documentation!
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenSchemaDocumentation_exclude_hasDocumentation_shouldNotGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      fields: [
        GraphQLInputField.mock("fieldOne",
                               type: .nonNull(.string()),
                               defaultValue: nil,
                               documentation: "Field Documentation!")
      ],
      documentation: documentation,
      config: .mock(.swiftPackageManager, options: .init(schemaDocumentation: .exclude))
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: Deprecation Tests

  func test__render__givenDeprecatedField_includeDeprecationWarnings_shouldGenerateWarning() throws {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        )
      ],
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include, warningsOnDeprecatedUsage: .include)
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenDeprecatedField_excludeDeprecationWarnings_shouldNotGenerateWarning() throws {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        )
      ],
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include,warningsOnDeprecatedUsage: .exclude)
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenDeprecatedField_andDocumentation_includeDeprecationWarnings_shouldGenerateWarning_afterDocumentation() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          documentation: "Field Documentation!",
          deprecationReason: "Not used anymore!"
        )
      ],
      documentation: documentation,
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include,warningsOnDeprecatedUsage: .include)
      )
    )

    let expected = """
    /// This is some great documentation!
    public enum MockOneOfInput: OneOfInputObject {
      /// Field Documentation!
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenDeprecatedField_andDocumentation_excludeDeprecationWarnings_shouldNotGenerateWarning_afterDocumentation() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          documentation: "Field Documentation!")
      ],
      documentation: documentation,
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include,warningsOnDeprecatedUsage: .exclude)
      )
    )

    let expected = """
    /// This is some great documentation!
    public enum MockOneOfInput: OneOfInputObject {
      /// Field Documentation!
      case fieldOne(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenDeprecatedAndValidFields_includeDeprecationWarnings_shouldGenerateWarnings() throws {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        ),
        GraphQLInputField.mock(
          "fieldThree",
          type: .nonNull(.string()),
          defaultValue: nil
        ),
        GraphQLInputField.mock(
          "fieldFour",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Stop using this field!"
        )
      ],
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include,warningsOnDeprecatedUsage: .include)
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      @available(*, deprecated, message: "Not used anymore!")
      case fieldOne(String)
      case fieldTwo(String)
      case fieldThree(String)
      @available(*, deprecated, message: "Stop using this field!")
      case fieldFour(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenDeprecatedAndValidFields_excludeDeprecationWarnings_shouldNotGenerateWarning_afterDocumentation() throws {
    // given
    buildSubject(
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Not used anymore!"
        ),
        GraphQLInputField.mock(
          "fieldTwo",
          type: .nonNull(.string()),
          defaultValue: nil
        ),
        GraphQLInputField.mock(
          "fieldThree",
          type: .nonNull(.string()),
          defaultValue: nil,
          deprecationReason: "Stop using this field!"
        )
      ],
      config: .mock(
        .swiftPackageManager,
        options: .init(schemaDocumentation: .include,warningsOnDeprecatedUsage: .exclude)
      )
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case fieldOne(String)
      case fieldTwo(String)
      case fieldThree(String)
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: Reserved Keywords + Special Names

  func test__render__givenFieldsUsingReservedNames__generateCasesAndDataDictWithEscaping() throws {
    // given
    let fields = [
      GraphQLInputField.mock(
        "associatedtype",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "class",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "deinit",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "enum",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "extension",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "fileprivate",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "func",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "import",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "init",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "inout",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "internal",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "let",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "operator",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "private",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "precedencegroup",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "protocol",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "public",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "rethrows",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "static",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "struct",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "subscript",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "typealias",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "var",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "break",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "case",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "catch",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "continue",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "default",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "defer",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "do",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "else",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "fallthrough",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "for",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "guard",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "if",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "in",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "repeat",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "return",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "throw",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "switch",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "where",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "while",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "as",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "false",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "is",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "nil",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "self",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "super",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "throws",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "true",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "try",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
      GraphQLInputField.mock(
        "_",
        type: .nonNull(.string()),
        defaultValue: nil
      ),
    ]

    buildSubject(
      fields: fields,
      config: .mock(.swiftPackageManager,
                    options: .init(
                      conversionStrategies: .init(inputObjects: .none)
                    ),
                    schemaNamespace: "TestSchema")
    )

    let expected = """
    public enum MockOneOfInput: OneOfInputObject {
      case `associatedtype`(String)
      case `class`(String)
      case `deinit`(String)
      case `enum`(String)
      case `extension`(String)
      case `fileprivate`(String)
      case `func`(String)
      case `import`(String)
      case `init`(String)
      case `inout`(String)
      case `internal`(String)
      case `let`(String)
      case `operator`(String)
      case `private`(String)
      case `precedencegroup`(String)
      case `protocol`(String)
      case `public`(String)
      case `rethrows`(String)
      case `static`(String)
      case `struct`(String)
      case `subscript`(String)
      case `typealias`(String)
      case `var`(String)
      case `break`(String)
      case `case`(String)
      case `catch`(String)
      case `continue`(String)
      case `default`(String)
      case `defer`(String)
      case `do`(String)
      case `else`(String)
      case `fallthrough`(String)
      case `for`(String)
      case `guard`(String)
      case `if`(String)
      case `in`(String)
      case `repeat`(String)
      case `return`(String)
      case `throw`(String)
      case `switch`(String)
      case `where`(String)
      case `while`(String)
      case `as`(String)
      case `false`(String)
      case `is`(String)
      case `nil`(String)
      case `self`(String)
      case `super`(String)
      case `throws`(String)
      case `true`(String)
      case `try`(String)
      case `_`(String)
    
      public var __data: InputDict {
        switch self {
        case .`associatedtype`(let value):
          return InputDict(["associatedtype": value])
        case .`class`(let value):
          return InputDict(["class": value])
        case .`deinit`(let value):
          return InputDict(["deinit": value])
        case .`enum`(let value):
          return InputDict(["enum": value])
        case .`extension`(let value):
          return InputDict(["extension": value])
        case .`fileprivate`(let value):
          return InputDict(["fileprivate": value])
        case .`func`(let value):
          return InputDict(["func": value])
        case .`import`(let value):
          return InputDict(["import": value])
        case .`init`(let value):
          return InputDict(["init": value])
        case .`inout`(let value):
          return InputDict(["inout": value])
        case .`internal`(let value):
          return InputDict(["internal": value])
        case .`let`(let value):
          return InputDict(["let": value])
        case .`operator`(let value):
          return InputDict(["operator": value])
        case .`private`(let value):
          return InputDict(["private": value])
        case .`precedencegroup`(let value):
          return InputDict(["precedencegroup": value])
        case .`protocol`(let value):
          return InputDict(["protocol": value])
        case .`public`(let value):
          return InputDict(["public": value])
        case .`rethrows`(let value):
          return InputDict(["rethrows": value])
        case .`static`(let value):
          return InputDict(["static": value])
        case .`struct`(let value):
          return InputDict(["struct": value])
        case .`subscript`(let value):
          return InputDict(["subscript": value])
        case .`typealias`(let value):
          return InputDict(["typealias": value])
        case .`var`(let value):
          return InputDict(["var": value])
        case .`break`(let value):
          return InputDict(["break": value])
        case .`case`(let value):
          return InputDict(["case": value])
        case .`catch`(let value):
          return InputDict(["catch": value])
        case .`continue`(let value):
          return InputDict(["continue": value])
        case .`default`(let value):
          return InputDict(["default": value])
        case .`defer`(let value):
          return InputDict(["defer": value])
        case .`do`(let value):
          return InputDict(["do": value])
        case .`else`(let value):
          return InputDict(["else": value])
        case .`fallthrough`(let value):
          return InputDict(["fallthrough": value])
        case .`for`(let value):
          return InputDict(["for": value])
        case .`guard`(let value):
          return InputDict(["guard": value])
        case .`if`(let value):
          return InputDict(["if": value])
        case .`in`(let value):
          return InputDict(["in": value])
        case .`repeat`(let value):
          return InputDict(["repeat": value])
        case .`return`(let value):
          return InputDict(["return": value])
        case .`throw`(let value):
          return InputDict(["throw": value])
        case .`switch`(let value):
          return InputDict(["switch": value])
        case .`where`(let value):
          return InputDict(["where": value])
        case .`while`(let value):
          return InputDict(["while": value])
        case .`as`(let value):
          return InputDict(["as": value])
        case .`false`(let value):
          return InputDict(["false": value])
        case .`is`(let value):
          return InputDict(["is": value])
        case .`nil`(let value):
          return InputDict(["nil": value])
        case .`self`(let value):
          return InputDict(["self": value])
        case .`super`(let value):
          return InputDict(["super": value])
        case .`throws`(let value):
          return InputDict(["throws": value])
        case .`true`(let value):
          return InputDict(["true": value])
        case .`try`(let value):
          return InputDict(["try": value])
        case .`_`(let value):
          return InputDict(["_": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__generatesOneOfInputObject_usingReservedKeyword_asEscapedType() throws {
    let keywords = ["Type", "type"]
    
    keywords.forEach { keyword in
      // given
      buildSubject(
        name: keyword,
        fields: [GraphQLInputField.mock("field", type: .scalar(.integer()), defaultValue: nil)]
      )

      let expected = """
      public enum \(keyword.firstUppercased)_InputObject: OneOfInputObject {
      """

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
  // MARK: - Schema Customization Tests
  
  func test__render__givenOneOfInputObjectAndField_withCustomNames_shouldRenderWithCustomNames() throws {
    // given
    let customInputField = GraphQLInputField.mock(
      "myField",
      type: .nonNull(.string()),
      defaultValue: nil
    )
    customInputField.name.customName = "myCustomField"
    buildSubject(
      name: "MyInputObject",
      customName: "MyCustomInputObject",
      fields: [
        GraphQLInputField.mock(
          "fieldOne",
          type: .nonNull(.string()),
          defaultValue: nil
        ),
        customInputField
      ]
    )

    let expected = """
    // Renamed from GraphQL schema value: 'MyInputObject'
    public enum MyCustomInputObject: OneOfInputObject {
      case fieldOne(String)
      // Renamed from GraphQL schema value: 'myField'
      case myCustomField(String)
    
      public var __data: InputDict {
        switch self {
        case .fieldOne(let value):
          return InputDict(["fieldOne": value])
        case .myCustomField(let value):
          return InputDict(["myField": value])
        }
      }
    }
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
}
