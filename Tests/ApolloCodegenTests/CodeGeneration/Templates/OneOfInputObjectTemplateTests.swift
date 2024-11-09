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

}
