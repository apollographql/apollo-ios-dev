import XCTest
import ApolloCodegenLib
import Nimble

final class ApolloCodegenConfiguration_SchemaCustomizationTests: XCTestCase {

  var testJSONEncoder: JSONEncoder!
  
  override func setUpWithError() throws {
    try super.setUpWithError()
    testJSONEncoder = JSONEncoder()
    testJSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  }

  override func tearDownWithError() throws {
    testJSONEncoder = nil
    try super.tearDownWithError()
  }

  // MARK: - Custom Type Names
  
  func test__encodeType_withCustomName() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyObject": .type(name: "CustomObject")
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyObject" : "CustomObject"
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeType_withCustomName() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyObject" : "CustomObject"
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyObject": .type(name: "CustomObject")
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeEmptyType_shouldThrowError() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyObject": .type(name: "")
      ]
    )
    
    //then
    expect {
      _ = try self.testJSONEncoder.encode(subject)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyObject"))
    })
  }
  
  func test__decodeEmptyType_shouldThrowError() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyObject" : ""
      }
    }
    """
    
    ///then
    expect {
      try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyObject"))
    })
  }
  
  // MARK: - Custom Enum Names
  
  func test__encodeEnum_withCustomNameAndCases() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: "CustomEnum",
          cases: [
            "CaseOne": "CustomCaseOne"
          ]
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "cases" : {
              "CaseOne" : "CustomCaseOne"
            },
            "name" : "CustomEnum"
          }
        }
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeEnum_withCustomNameAndCases() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "cases" : {
              "CaseOne" : "CustomCaseOne"
            },
            "name" : "CustomEnum"
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: "CustomEnum",
          cases: [
            "CaseOne": "CustomCaseOne"
          ]
        )
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeEnum_withCustomName_asType() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: "CustomEnum",
          cases: nil
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyEnum" : "CustomEnum"
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeEnum_withCustomName_asType() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "name" : "CustomEnum"
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .type(name: "CustomEnum")
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeEnum_withCustomCases() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: nil,
          cases: [
            "CaseOne": "CustomCaseOne"
          ]
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "cases" : {
              "CaseOne" : "CustomCaseOne"
            }
          }
        }
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeEnum_withCustomCases() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "cases" : {
              "CaseOne" : "CustomCaseOne"
            }
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: nil,
          cases: [
            "CaseOne": "CustomCaseOne"
          ]
        )
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeEmptyEnum_shouldThrowError() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyEnum": .enum(
          name: nil,
          cases: [:]
        )
      ]
    )
    
    //then
    expect {
      _ = try self.testJSONEncoder.encode(subject)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyEnum"))
    })
  }
  
  func test__decodeEmptyEnum_shouldThrowError() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyEnum" : {
          "enum" : {
            "cases" : {
            },
            "name" : ""
          }
        }
      }
    }
    """
    
    //then
    expect { 
      try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyEnum"))
    })
  }
  
  // MARK: - Custom InputObjects Names
  
  func test__encodeInputObject_withCustomNameAndFields() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: "CustomInputObject",
          fields: [
            "FieldOne": "CustomFieldOne"
          ]
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "fields" : {
              "FieldOne" : "CustomFieldOne"
            },
            "name" : "CustomInputObject"
          }
        }
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeInputObject_withCustomNameAndFields() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "fields" : {
              "FieldOne" : "CustomFieldOne"
            },
            "name" : "CustomInputObject"
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: "CustomInputObject",
          fields: [
            "FieldOne": "CustomFieldOne"
          ]
        )
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeInputObject_withCustomName_asType() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: "CustomInputObject",
          fields: nil
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyInputObject" : "CustomInputObject"
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeInputObject_withCustomName_asType() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "name" : "CustomInputObject"
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .type(name: "CustomInputObject")
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeInputObject_withCustomFields() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: nil,
          fields: [
            "FieldOne": "CustomFieldOne"
          ]
        )
      ]
    )
    
    let expected = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "fields" : {
              "FieldOne" : "CustomFieldOne"
            }
          }
        }
      }
    }
    """
    
    // when
    let encodedJSON = try testJSONEncoder.encode(subject)
    let actual = encodedJSON.asString
    
    //then
    expect(actual).to(equalLineByLine(expected))
  }
  
  func test__decodeInputObject_withCustomFields() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "fields" : {
              "FieldOne" : "CustomFieldOne"
            }
          }
        }
      }
    }
    """
    
    let expected = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: nil,
          fields: [
            "FieldOne": "CustomFieldOne"
          ]
        )
      ]
    )
    
    // when
    let actual = try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    
    //then
    expect(actual).to(equal(expected))
  }
  
  func test__encodeEmptyInputObject_shouldThrowError() throws {
    // given
    let subject = ApolloCodegenConfiguration.SchemaCustomization(
      customTypeNames: [
        "MyInputObject": .inputObject(
          name: nil,
          fields: [:]
        )
      ]
    )
    
    //then
    expect {
      _ = try self.testJSONEncoder.encode(subject)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyInputObject"))
    })
  }
  
  func test__decodeEmptyInputObject_shouldThrowError() throws {
    // given
    let subject = """
    {
      "customTypeNames" : {
        "MyInputObject" : {
          "inputObject" : {
            "fields" : {
            },
            "name" : ""
          }
        }
      }
    }
    """
    
    ///then
    expect {
      try JSONDecoder().decode(ApolloCodegenConfiguration.SchemaCustomization.self, from: subject.asData)
    }.to(throwError { error in
      guard case let ApolloCodegenConfiguration.SchemaCustomization.Error.emptyCustomization(type) = error else {
        fail("Expected .emptyCustomization, got .\(error)")
        return
      }
      expect(type).to(equal("MyInputObject"))
    })
  }
  
}
