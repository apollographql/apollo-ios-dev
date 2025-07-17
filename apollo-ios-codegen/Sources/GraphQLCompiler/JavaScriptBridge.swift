@preconcurrency import JavaScriptCore
import OrderedCollections

// MARK: - JavaScriptError

// JavaScriptCore APIs haven't been annotated for nullability, but most of its methods will never return `null`
// and can be safely force unwrapped. (Even when an exception is thrown they would still return
// a `JSValue` representing a JavaScript `undefined` value.)

/// An error thrown during JavaScript execution.
/// See https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error
public class JavaScriptError: JavaScriptObjectDecodable, Error, @unchecked Sendable {
  public let name: String?
  public let message: String?
  public let stack: String?

  @MainActor
  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    self.name = jsValue["name"]
    self.message = jsValue["message"]
    self.stack = jsValue["stack"]
  }

  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    self.init(jsValue, bridge: bridge)
  }
}

extension JavaScriptError: CustomStringConvertible {
  public var description: String {
    let components = [name, message, stack].compactMap { $0 }
    return "JavaScriptError: \(components.joined(separator: "-"))"
  }
}

// MARK: - JavaScriptReferencedObject

/// A type that references an underlying JavaScript object.
///
/// A `JavaScriptReferencedObject` is weakly referenced by the `JavaScriptBridge` that it was
/// created with. This allows references to the same `JSValue` within the same `bridge` to reference
/// the same object by calling `fromJSValue(_:bridge)`.
protocol JavaScriptReferencedObject: AnyObject, JavaScriptObjectDecodable {
  /// Initializes an instance of the referenced object from a `JSValue` to be stored in the
  /// given `JavaScriptBridge`.
  ///
  /// - Warning: This function should not be called directly to initialize an instance. Instead use
  /// `fromJSValue(_:bridge)`, which will return the existing object if it has already been
  /// initialized or call this and then `finalize(_: bridge:)` to initialize and store the object in the `bridge`.
  @MainActor
  init(_ jsValue: JSValue, bridge: JavaScriptBridge)

  /// This function will be after being initialized by a `JavaScriptBridge` to allow the object to
  /// complete setup of its values.
  ///
  /// Some properties of the object may be self-referential. In order to avoid infinite recursion,
  /// while initializing these objects, these properties must be set up after the object has been
  /// initialized and stored by the `JavaScriptBridge`.
  @MainActor
  func finalize(_ jsValue: JSValue, bridge: JavaScriptBridge)
}

extension JavaScriptReferencedObject {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    bridge.getReferenceOrInitialize(jsValue)
  }

  @MainActor
  func finalize(_ jsValue: JSValue, bridge: JavaScriptBridge) { }
}

// MARK: - JavaScriptCallable

/// A type that can call methods/functions on its underlying `JSValue`.
protocol JavaScriptCallable {
  /// The underlying JavaScript value for the object.
  ///
  /// - precondition: This value must be an object (ie. `jsValue.isObject` must be `true`).
  var jsValue: JSValue { get }
  var bridge: JavaScriptBridge { get }
}

extension JavaScriptCallable {

  // MARK: Invoke Method

  @MainActor
  func invokeMethod(
    _ methodName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> JSValue {
    try bridge.invokeMethod(methodName, on: jsValue, with: arguments)
  }

  @MainActor
  func invokeMethod<Decodable: JavaScriptValueDecodable>(
    _ methodName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.init(try bridge.invokeMethod(methodName, on: jsValue, with: arguments))
  }

  @MainActor
  func invokeMethod<Decodable: JavaScriptObjectDecodable>(
    _ methodName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.fromJSValue(
      try bridge.invokeMethod(methodName, on: jsValue, with: arguments),
      bridge: self.bridge
    )
  }

  // MARK: Call Function

  @MainActor
  func call(
    _ functionName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> JSValue {
    try bridge.call(functionName, on: jsValue, with: arguments)
  }

  @MainActor
  func call<Decodable: JavaScriptValueDecodable>(
    _ functionName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.init(try bridge.call(functionName, on: jsValue, with: arguments))
  }

  @MainActor
  func call<Decodable: JavaScriptObjectDecodable>(
    _ functionName: String,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.fromJSValue(
      try bridge.call(functionName, on: jsValue, with: arguments),
      bridge: self.bridge
    )
  }

  // MARK: Construct Object

  @MainActor
  func construct<Wrapper: JavaScriptObjectDecodable>(
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Wrapper {
    return try bridge.construct(from: jsValue, with: arguments)
  }

  // MARK: Get Property

  subscript(property: Any) -> JSValue {
    return jsValue[property]
  }

  subscript<Value: JavaScriptValueDecodable>(property: Any) -> Value {
    return Value.init(jsValue[property])
  }

  @MainActor
  subscript<Object: JavaScriptObjectDecodable>(property: Any) -> Object {
    return Object.fromJSValue(jsValue[property], bridge: bridge)
  }
}

/// A default object type to be initialized when an unregistered type is initialized from
/// a `JavaScriptBridge`.
public class JavaScriptObject: JavaScriptReferencedObject, JavaScriptCallable {
  /// The underlying JavaScript value for the object.
  ///
  /// - precondition: This value must be an object (ie. `jsValue.isObject` must be `true`).
  let jsValue: JSValue
  let bridge: JavaScriptBridge

  @MainActor
  static func initializeNewObject(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    self.init(jsValue, bridge: bridge)
  }

  @MainActor
  required init(_ jsValue: JSValue, bridge: JavaScriptBridge) {
    precondition(jsValue.isObject)
        
    self.jsValue = jsValue
    self.bridge = bridge
  }

}

extension JavaScriptObject: CustomDebugStringConvertible {
  @objc public var debugDescription: String {
    return "<\(type(of: self)): \(jsValue.toString()!)>"
  }
}

// MARK: - JavaScriptBridge

/// The JavaScript bridge is responsible for converting values to and from type-safe wrapper objects. It also ensures
/// exceptions thrown from JavaScript wrapped and rethrown.
@MainActor
final class JavaScriptBridge {

  public enum Error: Swift.Error {
    case failedToCreateJSContext
    case unrecognizedJavaScriptErrorThrown(JSValue)
  }

  private struct WeakRef {
    weak var value: (any JavaScriptReferencedObject)?

    init(_ value: any JavaScriptReferencedObject) {
      self.value = value
    }
  }

  private let virtualMachine = JSVirtualMachine()

  let context: JSContext
  
  // In JavaScript, classes are represented by constructor functions. We need access to these when checking
  // the type of a received value in `wrap(_)` below.
  // We keep a bidirectional mapping between constructors and wrapper types so we can both access the
  // corresponding wrapper type, and perform an `instanceof` check based on the corresponding constructor
  // for the expected wrapper type in case there isn't a direct match and we are receiving a subtype.
  private var constructorToWrapperType: [JSValue /* constructor function */: any JavaScriptObjectDecodable.Type] = [:]
  private var wrapperTypeToConstructor: [AnyHashable /* JavaScriptObjectDecodable.Type */: JSValue] = [:]

  /// We keep a map between `JSValue` objects and wrapper objects, to avoid repeatedly creating new
  /// wrappers and to guarantee referential equality.
  /// Making the keys `ObjectIdentifiers` here, prevents us from retaining all of the JSValues,
  /// otherwise they would never be deallocated.
  /// ('JSValue` is an Objective-C object that uses `JSValueProtect` to mark the underlying
  /// JavaScript object as ineligible for garbage collection.)
  private var wrapperMap: [ObjectIdentifier /* JSValue */: WeakRef] = [:]

  init() throws {
    guard let context = JSContext(virtualMachine: virtualMachine) else {
      throw Error.failedToCreateJSContext
    }

    self.context = context
    
    register(JavaScriptObject.self, forJavaScriptClass: "Object", from: context.globalObject)
    register(JavaScriptError.self, forJavaScriptClass: "Error", from: context.globalObject)
  }

  public func register(
    _ wrapperType: any JavaScriptObjectDecodable.Type,
    forJavaScriptClass className: String? = nil,
    from scope: JSValue
  ) {
    let className = className ?? String(describing: wrapperType)
    
    let constructor = scope[className]
    precondition(constructor.isObject, "Couldn't find JavaScript constructor function for class \(className). Make sure the class is exported from the library's entry point.")

    constructorToWrapperType[constructor] = wrapperType
    wrapperTypeToConstructor[ObjectIdentifier(wrapperType)] = constructor
  }

  public func register(
    _ wrapperType: any JavaScriptObjectDecodable.Type,
    forJavaScriptClass className: String? = nil,
    from scope: any JavaScriptCallable
  ) {
    register(wrapperType, forJavaScriptClass: className, from: scope.jsValue)
  }

  func getReferenceOrInitialize<Wrapper: JavaScriptReferencedObject>(
    _ jsValue: JSValue
  ) -> Wrapper {
    precondition(jsValue.context === self.context)
    let weakJSValue = ObjectIdentifier(jsValue)
    if let wrapper = wrapperMap[weakJSValue]?.value {
      return checkedDowncast(wrapper)
    }
    
    precondition(jsValue.isObject, "Expected JavaScript object but found: \(jsValue)")

    let wrapperType = wrapperTypeForInitializingObject(
     from: jsValue,
     defaultType: Wrapper.self
   )

    guard let wrapperType = wrapperType as? any JavaScriptReferencedObject.Type else {
      preconditionFailure("Expected JavaScriptReferencedObject.Type, got \(wrapperType).")
    }

    let wrapper = wrapperType.init(jsValue, bridge: self)
    wrapperMap[weakJSValue] = WeakRef(wrapper)
    wrapper.finalize(jsValue, bridge: self)
    return checkedDowncast(wrapper)
  }

  private func wrapperTypeForInitializingObject(
    from jsValue: JSValue,
    defaultType: any JavaScriptObjectDecodable.Type
  ) -> any JavaScriptObjectDecodable.Type {
    let constructor = jsValue["constructor"]

    // If an object doesn't have a prototype or has `Object` as its direct prototype,
    // we assume it is of the expected type and let the wrapper handle further type checks if needed.
    // This occurs for pseudo-classes like the AST nodes for example, that rely on a `kind` property
    // to indicate their type instead of a prototype.
    if constructor.isUndefined || constructor["name"].toString() == "Object" {
      return defaultType

    } else if let registeredType = constructorToWrapperType[constructor] {
      // We have a wrapper type registered for the JavaScript class.
      return registeredType

    } else {
      // We may have received an unregistered subtype of the expected type, and we don't necessarily
      // have a wrapper registered for every subtype (this is likely to happen with
      // subtypes of `Error` for example). So if we can verify the value is indeed an instance of
      // the expected type we use that as the wrapper.

      guard let expectedConstructor = wrapperTypeToConstructor[ObjectIdentifier(defaultType)] else {
        preconditionFailure("""
          Couldn't find JavaScript constructor for wrapper type \(defaultType). \
          Make sure the type is registered with the bridge."
          """)
      }

      if jsValue.isInstance(of: expectedConstructor) {
        return defaultType
      } else {
        preconditionFailure("""
          Object with JavaScript constructor \(constructor["name"]) doesn't seem to be \
          an instance of expected type \(expectedConstructor["name"])"
          """)
      }
    }
  }

  // MARK: Invoke Method

  func invokeMethod(
    _ methodName: String,
    on jsValue: JSValue,
    with arguments: [any JavaScriptValueConvertible]
  ) throws -> JSValue {
    return try throwingJavaScriptErrorIfNeeded { `self` in
      jsValue.invokeMethod(methodName, withArguments: self.unwrap(arguments))
    }
  }

  func invokeMethod(
    _ methodName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> JSValue {
    try invokeMethod(methodName, on: jsValue, with: arguments)
  }

  func invokeMethod<Decodable: JavaScriptValueDecodable>(
    _ methodName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.init(try invokeMethod(methodName, on: jsValue, with: arguments))
  }

  func invokeMethod<Decodable: JavaScriptObjectDecodable>(
    _ methodName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.fromJSValue(
      try invokeMethod(methodName, on: jsValue, with: arguments),
      bridge: self
    )
  }

  // MARK: Call Function

  func call(
    _ functionName: String,
    on jsValue: JSValue,
    with arguments: [any JavaScriptValueConvertible]
  ) throws -> JSValue {
    return try throwingJavaScriptErrorIfNeeded { `self` in
      let function = jsValue[functionName]

      precondition(!function.isUndefined, "Function \(functionName) is undefined")

      return function.call(withArguments: self.unwrap(arguments))!
    }
  }

  func call(
    _ functionName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> JSValue {
    try call(functionName, on: jsValue, with: arguments)
  }

  func call<Decodable: JavaScriptValueDecodable>(
    _ functionName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.init(
      try call(functionName, on: jsValue, with: arguments)
    )
  }

  func call<Decodable: JavaScriptObjectDecodable>(
    _ functionName: String,
    on jsValue: JSValue,
    with arguments: any JavaScriptValueConvertible...
  ) throws -> Decodable {
    return Decodable.fromJSValue(
      try call(functionName, on: jsValue, with: arguments),
      bridge: self
    )
  }

  // MARK: Construct

  func construct<Wrapper: JavaScriptObjectDecodable>(
    from jsValue: JSValue,
    with arguments: [any JavaScriptValueConvertible]
  ) throws -> Wrapper {
    return try throwingJavaScriptErrorIfNeeded { `self` in
      return Wrapper.fromJSValue(
        jsValue.construct(withArguments: self.unwrap(arguments)),
        bridge: self)
    }
  }

  // MARK: Error Handling

  @discardableResult func throwingJavaScriptErrorIfNeeded<ReturnValue>(
    body: @MainActor (JavaScriptBridge) -> ReturnValue
  ) throws -> ReturnValue {
    let previousExceptionHandler = context.exceptionHandler

    var exception: JSValue? = nil
    context.exceptionHandler = { _, thrownException in
      exception = thrownException
    }

    let result = body(self)

    // Errors thrown from JavaScript are stored on the context and ignored by default.
    // To surface these to callers, we wrap them in a `JavaScriptError` and throw.
    if let exception = exception {
      typealias JavaScriptErrorType = Swift.Error & JavaScriptObjectDecodable

      let errorType = wrapperTypeForInitializingObject(
        from: exception,
        defaultType: JavaScriptError.self
      )

      guard let errorType = errorType as? any JavaScriptErrorType.Type else {
        throw Error.unrecognizedJavaScriptErrorThrown(exception)
      }

      throw errorType.fromJSValue(exception, bridge: self)
    }

    context.exceptionHandler = previousExceptionHandler
    return result
  }

  private func unwrap(_ values: [any JavaScriptValueConvertible]) -> [Any] {
    values.map { $0.unwrapJSValue }
  }
}

// MARK: - JavaScriptObjectDecodable

/// A type that can decode itself from a JavaScript value that represents an object.
protocol JavaScriptObjectDecodable {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self
}

extension Optional: JavaScriptObjectDecodable where Wrapped: JavaScriptObjectDecodable {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    if jsValue.isUndefined || jsValue.isNull {
      return .none
    } else {
      return .some(Wrapped.fromJSValue(jsValue, bridge: bridge))
    }
  }
}

extension Array: JavaScriptObjectDecodable where Element: JavaScriptObjectDecodable {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    jsValue.toArray { Element.fromJSValue($0, bridge: bridge) }
  }
}

extension Dictionary: JavaScriptObjectDecodable where Key == String, Value: JavaScriptObjectDecodable {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    jsValue.toDictionary { Value.fromJSValue($0, bridge: bridge) }
  }
}

extension OrderedDictionary: JavaScriptObjectDecodable where Key == String, Value: JavaScriptObjectDecodable {
  @MainActor
  static func fromJSValue(_ jsValue: JSValue, bridge: JavaScriptBridge) -> Self {
    jsValue.toOrderedDictionary { Value.fromJSValue($0, bridge: bridge) }
  }
}

// MARK: - JavaScriptValueDecodable

/// A value type that can decode itself from a JavaScript value.
protocol JavaScriptValueDecodable {
  init(_ jsValue: JSValue)
}

extension Optional: JavaScriptValueDecodable where Wrapped: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    if jsValue.isUndefined || jsValue.isNull {
      self = nil
    } else {
      self = Wrapped.init(jsValue)
    }
  }
}

extension Array: JavaScriptValueDecodable where Element: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    self = jsValue.toArray { Element.init($0) }
  }
}

extension Dictionary: JavaScriptValueDecodable where Key == String, Value: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    self = jsValue.toDictionary { Value.init($0) }
  }
}

extension OrderedDictionary: JavaScriptValueDecodable where Key == String, Value: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    self = jsValue.toOrderedDictionary { Value.init($0) }
  }
}

extension String: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    precondition(jsValue.isString, "Expected JavaScript string but found: \(jsValue)")
    self = jsValue.toString()
  }
}

extension Int: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    precondition(jsValue.isNumber, "Expected JavaScript number but found: \(jsValue)")
    self = jsValue.toInt()
  }
}

extension Bool: JavaScriptValueDecodable {
  init(_ jsValue: JSValue) {
    precondition(jsValue.isBoolean, "Expected JavaScript boolean but found: \(jsValue)")
    self = jsValue.toBool()
  }
}

extension JSValue {
  subscript(_ property: Any) -> JSValue {
    return objectForKeyedSubscript(property)
  }

  subscript<Value: JavaScriptValueDecodable>(property: Any) -> Value {
    return Value.init(self[property])
  }

  func toInt() -> Int {
    return Int(toInt32())
  }
  
  // The regular `toArray()` does a deep convert of all elements, which means JavaScript objects
  // will be converted to `NSDictionary` and we lose the ability to pass references back to JavaScript.
  // That's why we manually construct an array by iterating over the indexes here.
  func toArray<Element>(_ transform: (JSValue) throws -> Element) rethrows -> [Element] {
    precondition(isArray, "Expected JavaScript array but found: \(self)")
    
    let length = self["length"].toInt()
    
    var array = [Element]()
    array.reserveCapacity(length)
    
    for index in 0..<length {
      let element = try transform(self[index])
      array.append(element)
    }
    
    return array
  }
  
  // The regular `toDictionary()` does a deep convert of all elements, which means JavaScript objects
  // will be converted to `NSDictionary` and we lose the ability to pass references back to JavaScript.
  // That's why we manually construct a dictionary by iterating over the keys here.
  func toDictionary<Value>(_ transform: (JSValue) throws -> Value) rethrows -> [String: Value] {
    precondition(isObject, "Expected JavaScript object but found: \(self)")
    
    guard let keys = context.globalObject["Object"].invokeMethod("keys", withArguments: [self])?.toArray() as? [String] else {
      preconditionFailure("Couldn't get keys for object \(self)")
    }
        
    var dictionary = [String: Value]()
    
    for key in keys {
      let element = try transform(self.objectForKeyedSubscript(key))
      dictionary[key] = element
    }
    
    return dictionary
  }

  // The regular `toDictionary()` creates an `NSDictionary` that while it preserves the order of
  // `keys` from JavaScript during initialization, there is no order afterwards. `OrderedDictionary`
  // provides for the preservation and subsequent use of ordering in the collection.
  func toOrderedDictionary<Value>(_ transform: (JSValue) throws -> Value) rethrows -> OrderedDictionary<String, Value> {
    precondition(isObject, "Expected JavaScript object but found: \(self)")

    guard let keys = context.globalObject["Object"].invokeMethod("keys", withArguments: [self])?.toArray() as? [String] else {
      preconditionFailure("Couldn't get keys for object \(self)")
    }

    var dictionary = OrderedDictionary<String, Value>()

    for key in keys {
      let element = try transform(self.objectForKeyedSubscript(key))
      dictionary[key] = element
    }

    return dictionary
  }

  // The regular `toDictionary()` creates an `NSDictionary` that while it preserves the order of
  // `keys` from JavaScript during initialization, there is no order afterwards. `OrderedDictionary`
  // provides for the preservation and subsequent use of ordering in the collection.
  func toOrderedDictionary<Value>(_ transform: (JSValue) throws -> (String, Value)) rethrows -> OrderedDictionary<String, Value> {
    precondition(isArray, "Expected JavaScript array but found: \(self)")

    let length = self["length"].toInt()

    var dictionary = OrderedDictionary<String, Value>()
    dictionary.reserveCapacity(length)

    for index in 0..<length {
      let (key, value) = try transform(self[index])
      dictionary[key] = value
    }

    return dictionary
  }
}

private func checkedDowncast<ExpectedType: AnyObject>(_ object: AnyObject) -> ExpectedType {
  guard let expected = object as? ExpectedType else {
    preconditionFailure("Expected type to be \(ExpectedType.self), but found \(type(of: object))")
  }
  
  return expected
}

protocol JavaScriptValueConvertible {
  var unwrapJSValue: Any { get }
}

extension JavaScriptObject: JavaScriptValueConvertible {
  var unwrapJSValue: Any {
    return jsValue
  }
}

extension Optional: JavaScriptValueConvertible where Wrapped: JavaScriptValueConvertible {
  var unwrapJSValue: Any {
    return map(\.unwrapJSValue) as Any
  }
}

extension Array: JavaScriptValueConvertible where Element: JavaScriptValueConvertible {
  var unwrapJSValue: Any {
    return map(\.unwrapJSValue)
  }
}

extension Dictionary: JavaScriptValueConvertible where Key == String, Value: JavaScriptValueConvertible {
  var unwrapJSValue: Any {
    return mapValues(\.unwrapJSValue)
  }
}

extension String: JavaScriptValueConvertible {
  var unwrapJSValue: Any { self }
}

extension Bool: JavaScriptValueConvertible {
  var unwrapJSValue: Any { self }
}
