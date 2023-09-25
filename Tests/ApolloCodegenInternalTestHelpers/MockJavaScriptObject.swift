@testable import ApolloCodegenLib
@testable import JavaScriptCore
@testable import GraphQLCompiler

private var mockJavaScriptBridge = try! JavaScriptBridge()

extension JavaScriptObject {

  @objc public class func emptyMockObject() -> Self {
    let object = JSValue(newObjectIn: mockJavaScriptBridge.context)!
    return Self.fromJSValue(object, bridge: mockJavaScriptBridge)
  }
  
}

extension JavaScriptWrapper {
  public class func emptyMockObject() -> Self {
    return self.init(.emptyMockObject())
  }
}
