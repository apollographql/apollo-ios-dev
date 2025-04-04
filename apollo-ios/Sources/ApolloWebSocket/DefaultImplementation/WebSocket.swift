//  Created by Dalton Cherry on 7/16/14.
//  Copyright (c) 2014-2017 Dalton Cherry.
//  Modified by Anthony Miller & Apollo GraphQL on 8/12/21
//
//  This is a derived work derived from
//  Starscream (https://github.com/daltoniam/Starscream)
//
//  Original Work License: http://www.apache.org/licenses/LICENSE-2.0
//  Derived Work License: https://github.com/apollographql/apollo-ios/blob/main/LICENSE

import Foundation
import CommonCrypto

//Standard WebSocket close codes
enum CloseCode : UInt16 {
  case normal                 = 1000
  case goingAway              = 1001
  case protocolError          = 1002
  case protocolUnhandledType  = 1003
  // 1004 reserved.
  case noStatusReceived       = 1005
  //1006 reserved.
  case encoding               = 1007
  case policyViolated         = 1008
  case messageTooBig          = 1009
}

//SSL settings for the stream
public struct SSLSettings {
  public let useSSL: Bool
  public let disableCertValidation: Bool
  public var overrideTrustHostname: Bool
  public var desiredTrustHostname: String?
  public let sslClientCertificate: SSLClientCertificate?
  #if os(Linux)
  #else
  public let cipherSuites: [SSLCipherSuite]?
  #endif
}

//WebSocket implementation

public final class WebSocket: NSObject, WebSocketClient, StreamDelegate, WebSocketStreamDelegate, SOCKSProxyable {

  public enum OpCode : UInt8 {
    case continueFrame = 0x0
    case textFrame = 0x1
    case binaryFrame = 0x2
    // 3-7 are reserved.
    case connectionClose = 0x8
    case ping = 0x9
    case pong = 0xA
    // B-F reserved.
  }

  public struct WSError: Swift.Error {
    public enum ErrorType {
      case outputStreamWriteError //output stream error during write
      case invalidSSLError //Invalid SSL certificate
      case writeTimeoutError //The socket timed out waiting to be ready to write
      case protocolError //There was an error parsing the WebSocket frames
      case upgradeError //There was an error during the HTTP upgrade
      case closeError //There was an error during the close (socket probably has been dereferenced)
    }

    public let type: ErrorType
    public let message: String
    public let code: Int
  }

  /// The GraphQL over WebSocket protocols supported by apollo-ios.
  public enum WSProtocol: CustomStringConvertible {
    /// WebSocket protocol `graphql-ws`. This is implemented by the [subscriptions-transport-ws](https://github.com/apollographql/subscriptions-transport-ws)
    /// and AWS AppSync libraries.
    case graphql_ws
    /// WebSocket protocol `graphql-transport-ws`. This is implemented by the [graphql-ws](https://github.com/enisdenjo/graphql-ws)
    /// library.
    case graphql_transport_ws

    public var description: String {
      switch self {
      case .graphql_ws: return "graphql-ws"
      case .graphql_transport_ws: return "graphql-transport-ws"
      }
    }
  }

  @_spi(Testable)
  public struct Constants {
    static let headerWSUpgradeName     = "Upgrade"
    static let headerWSUpgradeValue    = "websocket"
    static let headerWSHostName        = "Host"
    static let headerWSConnectionName  = "Connection"
    static let headerWSConnectionValue = "Upgrade"
    public static let headerWSProtocolName    = "Sec-WebSocket-Protocol"
    static let headerWSVersionName     = "Sec-WebSocket-Version"
    static let headerWSVersionValue    = "13"
    static let headerWSExtensionName   = "Sec-WebSocket-Extensions"
    static let headerWSKeyName         = "Sec-WebSocket-Key"
    static let headerOriginName        = "Origin"
    static let headerWSAcceptName      = "Sec-WebSocket-Accept"
    static let BUFFER_MAX              = 4096
    static let FinMask: UInt8          = 0x80
    static let OpCodeMask: UInt8       = 0x0F
    static let RSVMask: UInt8          = 0x70
    static let RSV1Mask: UInt8         = 0x40
    static let MaskMask: UInt8         = 0x80
    static let PayloadLenMask: UInt8   = 0x7F
    static let MaxFrameSize: Int       = 32
    static let httpSwitchProtocolCode  = 101
    static let supportedSSLSchemes     = ["wss", "https"]
    static let WebsocketDisconnectionErrorKeyName = "WebsocketDisconnectionErrorKeyName"

    struct Notifications {
      static let WebsocketDidConnect = "WebsocketDidConnectNotification"
      static let WebsocketDidDisconnect = "WebsocketDidDisconnectNotification"
    }
  }

  class WSResponse {
    var isFin = false
    public var code: OpCode = .continueFrame
    var bytesLeft = 0
    public var frameCount = 0
    public var buffer: NSMutableData?
    public let firstFrame = {
      return Date()
    }()
  }

  // MARK: - Delegates

  /// Responds to callback about new messages coming in over the WebSocket
  /// and also connection/disconnect messages.
  public weak var delegate: (any WebSocketClientDelegate)?

  // Where the callback is executed. It defaults to the main UI thread queue.
  public var callbackQueue = DispatchQueue.main

  public var onConnect: (() -> Void)?
  public var onDisconnect: (((any Error)?) -> Void)?
  public var onText: ((String) -> Void)?
  public var onData: ((Data) -> Void)?
  public var onPong: ((Data?) -> Void)?
  public var onHttpResponseHeaders: (([String: String]) -> Void)?

  public var disableSSLCertValidation = false
  public var overrideTrustHostname = false
  public var desiredTrustHostname: String? = nil
  public var sslClientCertificate: SSLClientCertificate? = nil

  public var enableCompression = true
  #if os(Linux)
  #else
  public var security: (any SSLTrustValidator)?
  public var enabledSSLCipherSuites: [SSLCipherSuite]?
  #endif

  public var isConnected: Bool {
    mutex.lock()
    let isConnected = connected
    mutex.unlock()
    return isConnected
  }
  public var request: URLRequest //this is only public to allow headers, timeout, etc to be modified on reconnect
  public var currentURL: URL { return request.url! }

  public var respondToPingWithPong: Bool = true

  /// Determines whether a SOCKS proxy is enabled on the underlying request.
  /// Mostly useful for debugging with tools like Charles Proxy.
  /// Note: Will return `false` from the getter and no-op the setter for implementations that do not conform to `SOCKSProxyable`.
  public var enableSOCKSProxy: Bool {
    get {
      guard let stream = stream as? (any SOCKSProxyable) else {
        // If it's not proxyable, then the proxy can't be enabled
        return false
      }

      return stream.enableSOCKSProxy
    }

    set {
      guard var stream = stream as? (any SOCKSProxyable) else {
        // If it's not proxyable, there's nothing to do here.
        return
      }

      stream.enableSOCKSProxy = newValue
    }
  }

  // MARK: - Private

  private struct CompressionState {
    var supportsCompression = false
    var messageNeedsDecompression = false
    var serverMaxWindowBits = 15
    var clientMaxWindowBits = 15
    var clientNoContextTakeover = false
    var serverNoContextTakeover = false
    var decompressor:Decompressor? = nil
    var compressor:Compressor? = nil
  }

  private var stream: any WebSocketStream
  private var connected = false
  private var isConnecting = false
  private let mutex = NSLock()
  private let serialQueue = DispatchQueue(label: "com.apollographql.WebSocket.serial", qos: .background)
  private var compressionState = CompressionState()
  private var writeQueue = OperationQueue()
  private var readStack = [WSResponse]()
  private var inputQueue = [Data]()
  private var fragBuffer: Data?
  private var certValidated = false
  private var didDisconnect = false
  private var readyToWrite = false
  private var headerSecKey = ""
  private var canDispatch: Bool {
    mutex.lock()
    let canWork = readyToWrite
    mutex.unlock()
    return canWork
  }

  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - request: A URL request object that provides request-specific information such as the URL.
  ///   - protocol: Protocol to use for communication over the web socket.
  public init(request: URLRequest, protocol: WSProtocol) {
    self.request = request
    self.stream = FoundationStream()
    if request.value(forHTTPHeaderField: Constants.headerOriginName) == nil {
      guard let url = request.url else {return}
      var origin = url.absoluteString
      if let hostUrl = URL (string: "/", relativeTo: url) {
        origin = hostUrl.absoluteString
        origin.remove(at: origin.index(before: origin.endIndex))
      }
      self.request.setValue(origin, forHTTPHeaderField: Constants.headerOriginName)
    }

    self.request.setValue(`protocol`.description, forHTTPHeaderField: Constants.headerWSProtocolName)

    writeQueue.maxConcurrentOperationCount = 1
  }

  /// Convenience initializer to specify the URL and web socket protocol.
  ///
  /// - Parameters:
  ///   - url: The destination URL to connect to.
  ///   - protocol: Protocol to use for communication over the web socket.
  public convenience init(url: URL, protocol: WSProtocol) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 5

    self.init(request: request, protocol: `protocol`)
  }

  /// Convenience initializer to specify the URL and web socket protocol with a specific quality of
  /// service on the write queue.
  ///
  /// - Parameters:
  ///   - url: The destination URL to connect to.
  ///   - writeQueueQOS: Specifies the quality of service for the write queue.
  ///   - protocol: Protocol to use for communication over the web socket.
  public convenience init(
    url: URL,
    writeQueueQOS: QualityOfService,
    protocol: WSProtocol
  ) {
    self.init(url: url, protocol: `protocol`)
    writeQueue.qualityOfService = writeQueueQOS
  }

  /**
   Connect to the WebSocket server on a background thread.
   */
  public func connect() {
    serialQueue.sync {
      guard !self.isConnecting else { return }
      self.didDisconnect = false
      self.isConnecting = true
      self.createHTTPRequest()
    }
  }

  /**
   Disconnect from the server. Send a Close control frame to the server, then expect the server to
   respond with a Close control frame and close the socket from its end. Notify the delegate once
   the socket has been closed.

   If `forceTimeout` > 0, wait at most that long (in seconds) for the server to close the socket.
   After the timeout expires, close the socket (without sending a Close control frame) and notify
   the delegate.

   If `forceTimeout` <= 0, immediately close the socket (without sending a Close control frame)
   and notify the delegate.

   If `forceTimeout` is `nil`, send the Close control frame to the server.

   - Parameter forceTimeout: Maximum time to wait for the server to close the socket.
   - Parameter closeCode: The code to send on disconnect. The default is the normal close code for
   cleanly disconnecting a webSocket.
   */
  func disconnect(
    forceTimeout: TimeInterval? = nil,
    closeCode: UInt16 = CloseCode.normal.rawValue
  ) {
    guard isConnected else { return }
    switch forceTimeout {
    case .some(let seconds) where seconds > 0:
      let milliseconds = Int(seconds * 1_000)
      callbackQueue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak self] in
        self?.disconnectStream(nil)
      }
      fallthrough
    case .none:
      writeError(closeCode)
    default:
      disconnectStream(nil)
      break
    }
  }

  /**
   Disconnect from the server. Send a Close control frame to the server, then expect the server to
   respond with a Close control frame and close the socket from its end. Notify the delegate once
   the socket has been closed.

   If `forceTimeout` > 0, wait at most that long (in seconds) for the server to close the socket.
   After the timeout expires, close the socket (without sending a Close control frame) and notify
   the delegate.

   If `forceTimeout` <= 0, immediately close the socket (without sending a Close control frame)
   and notify the delegate.

   If `forceTimeout` is `nil`, send the Close control frame to the server.

   - Parameter forceTimeout: Maximum time to wait for the server to close the socket.
   */
  public func disconnect(forceTimeout: TimeInterval?) {
    self.disconnect(forceTimeout: forceTimeout, closeCode: CloseCode.normal.rawValue)
  }

  /**
   Write a string to the websocket. This sends it as a text frame.

   If you supply a non-nil completion block, I will perform it when the write completes.

   - parameter string:        The string to write.
   - parameter completion: The (optional) completion handler.
   */
  func write(string: String, completion: (() -> ())? = nil) {
    guard isConnected else { return }
    dequeueWrite(string.data(using: String.Encoding.utf8)!, code: .textFrame, writeCompletion: completion)
  }

  public func write(string: String) {
    self.write(string: string, completion: nil)
  }

  /**
   Write binary data to the websocket. This sends it as a binary frame.

   If you supply a non-nil completion block, I will perform it when the write completes.

   - parameter data:       The data to write.
   - parameter completion: The (optional) completion handler.
   */
  func write(data: Data, completion: (() -> ())? = nil) {
    guard isConnected else { return }
    dequeueWrite(data, code: .binaryFrame, writeCompletion: completion)
  }

  /**
   Write a ping to the websocket. This sends it as a control frame.
   */
  public func write(ping: Data, completion: (() -> ())? = nil) {
    guard isConnected else { return }
    dequeueWrite(ping, code: .ping, writeCompletion: completion)
  }

  /**
   Write a pong to the websocket. This sends it as a control frame.
   */
  func write(pong: Data, completion: (() -> ())? = nil) {
    guard isConnected else { return }
    dequeueWrite(pong, code: .pong, writeCompletion: completion)
  }

  /**
   Private method that starts the connection.
   */
  private func createHTTPRequest() {
    guard let url = request.url else {return}
    var port = url.port
    if port == nil {
      if Constants.supportedSSLSchemes.contains(url.scheme!) {
        port = 443
      } else {
        port = 80
      }
    }
    request.setValue(Constants.headerWSUpgradeValue,
                     forHTTPHeaderField: Constants.headerWSUpgradeName)
    request.setValue(Constants.headerWSConnectionValue,
                     forHTTPHeaderField: Constants.headerWSConnectionName)
    headerSecKey = generateWebSocketKey()
    request.setValue(Constants.headerWSVersionValue,
                     forHTTPHeaderField: Constants.headerWSVersionName)
    request.setValue(headerSecKey,
                     forHTTPHeaderField: Constants.headerWSKeyName)

    if enableCompression {
      let val = "permessage-deflate; client_max_window_bits; server_max_window_bits=15"
      request.setValue(val, forHTTPHeaderField: Constants.headerWSExtensionName)
    }

    if request.allHTTPHeaderFields?[Constants.headerWSHostName] == nil {
      request.setValue("\(url.host!):\(port!)", forHTTPHeaderField: Constants.headerWSHostName)
    }

    var path = url.absoluteString
    let offset = (url.scheme?.count ?? 2) + 3
    path = String(path[path.index(path.startIndex, offsetBy: offset)..<path.endIndex])
    if let range = path.range(of: "/") {
      path = String(path[range.lowerBound..<path.endIndex])
    } else {
      path = "/"
      if let query = url.query {
        path += "?" + query
      }
    }

    var httpBody = "\(request.httpMethod ?? "GET") \(path) HTTP/1.1\r\n"
    if let headers = request.allHTTPHeaderFields {
      for (key, val) in headers {
        httpBody += "\(key): \(val)\r\n"
      }
    }
    httpBody += "\r\n"

    initStreamsWithData(httpBody.data(using: .utf8)!, Int(port!))
  }

  /**
   Generate a WebSocket key as needed in RFC.
   */
  private func generateWebSocketKey() -> String {
    var key = ""
    let seed = 16
    for _ in 0..<seed {
      let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
      key += "\(Character(uni!))"
    }
    let data = key.data(using: String.Encoding.utf8)
    let baseKey = data?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    return baseKey!
  }

  /**
   Start the stream connection and write the data to the output stream.
   */
  private func initStreamsWithData(_ data: Data, _ port: Int) {

    guard let url = request.url else {
      disconnectStream(nil, runDelegate: true)
      return

    }
    // Disconnect and clean up any existing streams before setting up a new pair
    disconnectStream(nil, runDelegate: false)

    let useSSL = Constants.supportedSSLSchemes.contains(url.scheme!)
    #if os(Linux)
    let settings = SSLSettings(useSSL: useSSL,
                               disableCertValidation: disableSSLCertValidation,
                               overrideTrustHostname: overrideTrustHostname,
                               desiredTrustHostname: desiredTrustHostname),
      sslClientCertificate: sslClientCertificate
    #else
    let settings = SSLSettings(useSSL: useSSL,
                               disableCertValidation: disableSSLCertValidation,
                               overrideTrustHostname: overrideTrustHostname,
                               desiredTrustHostname: desiredTrustHostname,
                               sslClientCertificate: sslClientCertificate,
                               cipherSuites: self.enabledSSLCipherSuites)
    #endif
    certValidated = !useSSL
    let timeout = request.timeoutInterval * 1_000_000
    stream.delegate = self
    stream.connect(url: url, port: port, timeout: timeout, ssl: settings, completion: { [weak self] (error) in
      guard let self = self else {return}
      if error != nil {
        self.disconnectStream(error)
        return
      }
      let operation = BlockOperation()
      operation.addExecutionBlock { [weak self, weak operation] in
        guard let sOperation = operation, let self = self else { return }
        guard !sOperation.isCancelled else { return }
        // Do the pinning now if needed
        #if os(Linux) || os(watchOS)
        self.certValidated = false
        #else
        if let sec = self.security, !self.certValidated {
          let trustObj = self.stream.sslTrust()
          if let possibleTrust = trustObj.trust {
            self.certValidated = sec.isValid(possibleTrust, domain: trustObj.domain)
          } else {
            self.certValidated = false
          }
          if !self.certValidated {
            self.disconnectStream(WSError(type: .invalidSSLError, message: "Invalid SSL certificate", code: 0))
            return
          }
        }
        #endif
        let _ = self.stream.write(data: data)
      }
      self.writeQueue.addOperation(operation)
    })

    self.mutex.lock()
    self.readyToWrite = true
    self.mutex.unlock()
  }

  /**
   Delegate for the stream methods. Processes incoming bytes
   */

  public func newBytesInStream() {
    processInputStream()
  }

  public func streamDidError(error: (any Error)?) {
    disconnectStream(error)
  }

  /**
   Disconnect the stream object and notifies the delegate.
   */
  private func disconnectStream(_ error: (any Error)?, runDelegate: Bool = true) {
    if error == nil {
      writeQueue.waitUntilAllOperationsAreFinished()
    } else {
      writeQueue.cancelAllOperations()
    }

    mutex.lock()
    cleanupStream()
    connected = false
    mutex.unlock()
    if runDelegate {
      doDisconnect(error)
    }
  }

  /**
   cleanup the streams.
   */
  private func cleanupStream() {
    stream.cleanup()
    fragBuffer = nil
  }

  /**
   Handles the incoming bytes and sending them to the proper processing method.
   */
  private func processInputStream() {
    let data = stream.read()
    guard let d = data else { return }
    var process = false
    if inputQueue.isEmpty {
      process = true
    }
    inputQueue.append(d)
    if process {
      dequeueInput()
    }
  }

  /**
   Dequeue the incoming input so it is processed in order.
   */
  private func dequeueInput() {
    while !inputQueue.isEmpty {
      autoreleasepool {
        let data = inputQueue[0]
        var work = data
        if let buffer = fragBuffer {
          var combine = NSData(data: buffer) as Data
          combine.append(data)
          work = combine
          fragBuffer = nil
        }
        let buffer = UnsafeRawPointer((work as NSData).bytes).assumingMemoryBound(to: UInt8.self)
        let length = work.count
        if !connected {
          processTCPHandshake(buffer, bufferLen: length)
        } else {
          processRawMessagesInBuffer(buffer, bufferLen: length)
        }
        inputQueue = inputQueue.filter{ $0 != data }
      }
    }
  }

  /**
   Handle checking the inital connection status
   */
  private func processTCPHandshake(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) {
    let code = processHTTP(buffer, bufferLen: bufferLen)
    switch code {
    case 0:
      break
    case -1:
      fragBuffer = Data(bytes: buffer, count: bufferLen)
      break // do nothing, we are going to collect more data
    default:
      doDisconnect(WSError(type: .upgradeError, message: "Invalid HTTP upgrade", code: code))
    }
  }

  /**
   Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
   */
  private func processHTTP(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
    let CRLFBytes = [UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\n")]
    var k = 0
    var totalSize = 0
    for i in 0..<bufferLen {
      if buffer[i] == CRLFBytes[k] {
        k += 1
        if k == 4 {
          totalSize = i + 1
          break
        }
      } else {
        k = 0
      }
    }
    if totalSize > 0 {
      let code = validateResponse(buffer, bufferLen: totalSize)
      if code != 0 {
        return code
      }
      isConnecting = false
      mutex.lock()
      connected = true
      mutex.unlock()
      didDisconnect = false
      if canDispatch {
        callbackQueue.async { [weak self] in
          guard let self = self else { return }
          self.onConnect?()
          self.delegate?.websocketDidConnect(socket: self)
          NotificationCenter.default
            .post(name: NSNotification.Name(Constants.Notifications.WebsocketDidConnect),
                  object: self)
        }
      }
      //totalSize += 1 //skip the last \n
      let restSize = bufferLen - totalSize
      if restSize > 0 {
        processRawMessagesInBuffer(buffer + totalSize, bufferLen: restSize)
      }
      return 0 //success
    }
    return -1 // Was unable to find the full TCP header.
  }

  /**
   Validates the HTTP is a 101 as per the RFC spec.
   */
  private func validateResponse(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
    guard let str = String(data: Data(bytes: buffer, count: bufferLen), encoding: .utf8) else { return -1 }
    let splitArr = str.components(separatedBy: "\r\n")
    var code = -1
    var i = 0
    var headers = [String: String]()
    for str in splitArr {
      if i == 0 {
        let responseSplit = str.components(separatedBy: .whitespaces)
        guard responseSplit.count > 1 else { return -1 }
        if let c = Int(responseSplit[1]) {
          code = c
        }
      } else {
        let responseSplit = str.components(separatedBy: ":")
        guard responseSplit.count > 1 else { break }
        let key = responseSplit[0].trimmingCharacters(in: .whitespaces)
        let val = responseSplit[1].trimmingCharacters(in: .whitespaces)
        headers[key.lowercased()] = val
      }
      i += 1
    }
    onHttpResponseHeaders?(headers)
    if code != Constants.httpSwitchProtocolCode {
      return code
    }

    if let extensionHeader = headers[Constants.headerWSExtensionName.lowercased()] {
      processExtensionHeader(extensionHeader)
    }

    if let acceptKey = headers[Constants.headerWSAcceptName.lowercased()] {
      if acceptKey.count > 0 {
        if headerSecKey.count > 0 {
          let sha = "\(headerSecKey)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".sha1Base64()
          if sha != acceptKey as String {
            return -1
          }
        }
        return 0
      }
    }
    return -1
  }

  /**
   Parses the extension header, setting up the compression parameters.
   */
  func processExtensionHeader(_ extensionHeader: String) {
    let parts = extensionHeader.components(separatedBy: ";")
    for p in parts {
      let part = p.trimmingCharacters(in: .whitespaces)
      if part == "permessage-deflate" {
        compressionState.supportsCompression = true
      } else if part.hasPrefix("server_max_window_bits=") {
        let valString = part.components(separatedBy: "=")[1]
        if let val = Int(valString.trimmingCharacters(in: .whitespaces)) {
          compressionState.serverMaxWindowBits = val
        }
      } else if part.hasPrefix("client_max_window_bits=") {
        let valString = part.components(separatedBy: "=")[1]
        if let val = Int(valString.trimmingCharacters(in: .whitespaces)) {
          compressionState.clientMaxWindowBits = val
        }
      } else if part == "client_no_context_takeover" {
        compressionState.clientNoContextTakeover = true
      } else if part == "server_no_context_takeover" {
        compressionState.serverNoContextTakeover = true
      }
    }
    if compressionState.supportsCompression {
      compressionState.decompressor = Decompressor(windowBits: compressionState.serverMaxWindowBits)
      compressionState.compressor = Compressor(windowBits: compressionState.clientMaxWindowBits)
    }
  }

  /**
   Read a 16 bit big endian value from a buffer
   */
  private static func readUint16(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt16 {
    return (UInt16(buffer[offset + 0]) << 8) | UInt16(buffer[offset + 1])
  }

  /**
   Read a 64 bit big endian value from a buffer
   */
  private static func readUint64(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt64 {
    var value = UInt64(0)
    for i in 0...7 {
      value = (value << 8) | UInt64(buffer[offset + i])
    }
    return value
  }

  /**
   Write a 16-bit big endian value to a buffer.
   */
  private static func writeUint16(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt16) {
    buffer[offset + 0] = UInt8(value >> 8)
    buffer[offset + 1] = UInt8(value & 0xff)
  }

  /**
   Write a 64-bit big endian value to a buffer.
   */
  private static func writeUint64(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt64) {
    for i in 0...7 {
      buffer[offset + i] = UInt8((value >> (8*UInt64(7 - i))) & 0xff)
    }
  }

  /**
   Process one message at the start of `buffer`. Return another buffer (sharing storage) that contains the leftover contents of `buffer` that I didn't process.
   */
  private func processOneRawMessage(inBuffer buffer: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
    let response = readStack.last
    guard let baseAddress = buffer.baseAddress else {return emptyBuffer}
    let bufferLen = buffer.count
    if response != nil && bufferLen < 2 {
      fragBuffer = Data(buffer: buffer)
      return emptyBuffer
    }
    if let response = response, response.bytesLeft > 0 {
      var len = response.bytesLeft
      var extra = bufferLen - response.bytesLeft
      if response.bytesLeft > bufferLen {
        len = bufferLen
        extra = 0
      }
      response.bytesLeft -= len
      response.buffer?.append(Data(bytes: baseAddress, count: len))
      _ = processResponse(response)
      return buffer.fromOffset(bufferLen - extra)
    } else {
      let isFin = (Constants.FinMask & baseAddress[0])
      let receivedOpcodeRawValue = (Constants.OpCodeMask & baseAddress[0])
      let receivedOpcode = OpCode(rawValue: receivedOpcodeRawValue)
      let isMasked = (Constants.MaskMask & baseAddress[1])
      let payloadLen = (Constants.PayloadLenMask & baseAddress[1])
      var offset = 2
      if compressionState.supportsCompression && receivedOpcode != .continueFrame {
        compressionState.messageNeedsDecompression = (Constants.RSV1Mask & baseAddress[0]) > 0
      }
      if (isMasked > 0 || (Constants.RSVMask & baseAddress[0]) > 0) && receivedOpcode != .pong && !compressionState.messageNeedsDecompression {
        let errCode = CloseCode.protocolError.rawValue
        doDisconnect(WSError(type: .protocolError, message: "masked and rsv data is not currently supported", code: Int(errCode)))
        writeError(errCode)
        return emptyBuffer
      }
      let isControlFrame = (receivedOpcode == .connectionClose || receivedOpcode == .ping)
      if !isControlFrame && (receivedOpcode != .binaryFrame && receivedOpcode != .continueFrame &&
                              receivedOpcode != .textFrame && receivedOpcode != .pong) {
        let errCode = CloseCode.protocolError.rawValue
        doDisconnect(WSError(type: .protocolError, message: "unknown opcode: \(receivedOpcodeRawValue)", code: Int(errCode)))
        writeError(errCode)
        return emptyBuffer
      }
      if isControlFrame && isFin == 0 {
        let errCode = CloseCode.protocolError.rawValue
        doDisconnect(WSError(type: .protocolError, message: "control frames can't be fragmented", code: Int(errCode)))
        writeError(errCode)
        return emptyBuffer
      }
      var closeCode = CloseCode.normal.rawValue
      if receivedOpcode == .connectionClose {
        if payloadLen == 1 {
          closeCode = CloseCode.protocolError.rawValue
        } else if payloadLen > 1 {
          closeCode = WebSocket.readUint16(baseAddress, offset: offset)
          if closeCode < 1000 || (closeCode > 1003 && closeCode < 1007) || (closeCode > 1013 && closeCode < 3000) {
            closeCode = CloseCode.protocolError.rawValue
          }
        }
        if payloadLen < 2 {
          doDisconnect(WSError(type: .protocolError, message: "connection closed by server", code: Int(closeCode)))
          writeError(closeCode)
          return emptyBuffer
        }
      } else if isControlFrame && payloadLen > 125 {
        writeError(CloseCode.protocolError.rawValue)
        return emptyBuffer
      }
      var dataLength = UInt64(payloadLen)
      if dataLength == 127 {
        dataLength = WebSocket.readUint64(baseAddress, offset: offset)
        offset += MemoryLayout<UInt64>.size
      } else if dataLength == 126 {
        dataLength = UInt64(WebSocket.readUint16(baseAddress, offset: offset))
        offset += MemoryLayout<UInt16>.size
      }
      if bufferLen < offset || UInt64(bufferLen - offset) < dataLength {
        fragBuffer = Data(bytes: baseAddress, count: bufferLen)
        return emptyBuffer
      }
      var len = dataLength
      if dataLength > UInt64(bufferLen) {
        len = UInt64(bufferLen-offset)
      }
      if receivedOpcode == .connectionClose && len > 0 {
        let size = MemoryLayout<UInt16>.size
        offset += size
        len -= UInt64(size)
      }
      let data: Data
      if compressionState.messageNeedsDecompression, let decompressor = compressionState.decompressor {
        do {
          data = try decompressor.decompress(bytes: baseAddress+offset, count: Int(len), finish: isFin > 0)
          if isFin > 0 && compressionState.serverNoContextTakeover {
            try decompressor.reset()
          }
        } catch {
          let closeReason = "Decompression failed: \(error)"
          let closeCode = CloseCode.encoding.rawValue
          doDisconnect(WSError(type: .protocolError, message: closeReason, code: Int(closeCode)))
          writeError(closeCode)
          return emptyBuffer
        }
      } else {
        data = Data(bytes: baseAddress+offset, count: Int(len))
      }

      if receivedOpcode == .connectionClose {
        var closeReason = "connection closed by server"
        if let customCloseReason = String(data: data, encoding: .utf8) {
          closeReason = customCloseReason
        } else {
          closeCode = CloseCode.protocolError.rawValue
        }
        doDisconnect(WSError(type: .protocolError, message: closeReason, code: Int(closeCode)))
        writeError(closeCode)
        return emptyBuffer
      }
      if receivedOpcode == .pong {
        if canDispatch {
          callbackQueue.async { [weak self] in
            guard let self = self else { return }
            let pongData: Data? = data.count > 0 ? data : nil
            self.onPong?(pongData)
          }
        }
        return buffer.fromOffset(offset + Int(len))
      }
      var response = readStack.last
      if isControlFrame {
        response = nil // Don't append pings.
      }
      if isFin == 0 && receivedOpcode == .continueFrame && response == nil {
        let errCode = CloseCode.protocolError.rawValue
        doDisconnect(WSError(type: .protocolError, message: "continue frame before a binary or text frame", code: Int(errCode)))
        writeError(errCode)
        return emptyBuffer
      }
      var isNew = false
      if response == nil {
        if receivedOpcode == .continueFrame {
          let errCode = CloseCode.protocolError.rawValue
          doDisconnect(WSError(type: .protocolError, message: "first frame can't be a continue frame", code: Int(errCode)))
          writeError(errCode)
          return emptyBuffer
        }
        isNew = true
        response = WSResponse()
        response!.code = receivedOpcode!
        response!.bytesLeft = Int(dataLength)
        response!.buffer = NSMutableData(data: data)
      } else {
        if receivedOpcode == .continueFrame {
          response!.bytesLeft = Int(dataLength)
        } else {
          let errCode = CloseCode.protocolError.rawValue
          doDisconnect(WSError(type: .protocolError, message: "second and beyond of fragment message must be a continue frame", code: Int(errCode)))
          writeError(errCode)
          return emptyBuffer
        }
        response!.buffer!.append(data)
      }
      if let response = response {
        response.bytesLeft -= Int(len)
        response.frameCount += 1
        response.isFin = isFin > 0 ? true : false
        if isNew {
          readStack.append(response)
        }
        _ = processResponse(response)
      }

      let step = Int(offset + numericCast(len))
      return buffer.fromOffset(step)
    }
  }

  /**
   Process all messages in the buffer if possible.
   */
  private func processRawMessagesInBuffer(_ pointer: UnsafePointer<UInt8>, bufferLen: Int) {
    var buffer = UnsafeBufferPointer(start: pointer, count: bufferLen)
    repeat {
      buffer = processOneRawMessage(inBuffer: buffer)
    } while buffer.count >= 2
    if buffer.count > 0 {
      fragBuffer = Data(buffer: buffer)
    }
  }

  /**
   Process the finished response of a buffer.
   */
  private func processResponse(_ response: WSResponse) -> Bool {
    if response.isFin && response.bytesLeft <= 0 {
      if response.code == .ping {
        if respondToPingWithPong {
          let data = response.buffer! // local copy so it is perverse for writing
          dequeueWrite(data as Data, code: .pong)
        }
      } else if response.code == .textFrame {
        guard let str = String(data: response.buffer! as Data, encoding: .utf8) else {
          writeError(CloseCode.encoding.rawValue)
          return false
        }
        if canDispatch {
          callbackQueue.async { [weak self] in
            guard let self = self else { return }
            self.onText?(str)
            self.delegate?.websocketDidReceiveMessage(socket: self, text: str)
          }
        }
      } else if response.code == .binaryFrame {
        if canDispatch {
          let data = response.buffer! // local copy so it is perverse for writing
          callbackQueue.async { [weak self] in
            guard let self = self else { return }
            self.onData?(data as Data)
            self.delegate?.websocketDidReceiveData(socket: self, data: data as Data)
          }
        }
      }
      readStack.removeLast()
      return true
    }
    return false
  }

  /**
   Write an error to the socket
   */
  private func writeError(_ code: UInt16) {
    let buf = NSMutableData(capacity: MemoryLayout<UInt16>.size)
    let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
    WebSocket.writeUint16(buffer, offset: 0, value: code)
    dequeueWrite(Data(bytes: buffer, count: MemoryLayout<UInt16>.size), code: .connectionClose)
  }

  /**
   Used to write things to the stream
   */
  private func dequeueWrite(_ data: Data, code: OpCode, writeCompletion: (() -> ())? = nil) {
    let operation = BlockOperation()
    operation.addExecutionBlock { [weak self, weak operation] in
      //stream isn't ready, let's wait
      guard let self = self else { return }
      guard let sOperation = operation else { return }
      var offset = 2
      var firstByte:UInt8 = Constants.FinMask | code.rawValue
      var data = data
      if [.textFrame, .binaryFrame].contains(code), let compressor = self.compressionState.compressor {
        do {
          data = try compressor.compress(data)
          if self.compressionState.clientNoContextTakeover {
            try compressor.reset()
          }
          firstByte |= Constants.RSV1Mask
        } catch {
          // TODO: report error?  We can just send the uncompressed frame.
        }
      }
      let dataLength = data.count
      let frame = NSMutableData(capacity: dataLength + Constants.MaxFrameSize)
      let buffer = UnsafeMutableRawPointer(frame!.mutableBytes).assumingMemoryBound(to: UInt8.self)
      buffer[0] = firstByte
      if dataLength < 126 {
        buffer[1] = CUnsignedChar(dataLength)
      } else if dataLength <= Int(UInt16.max) {
        buffer[1] = 126
        WebSocket.writeUint16(buffer, offset: offset, value: UInt16(dataLength))
        offset += MemoryLayout<UInt16>.size
      } else {
        buffer[1] = 127
        WebSocket.writeUint64(buffer, offset: offset, value: UInt64(dataLength))
        offset += MemoryLayout<UInt64>.size
      }
      buffer[1] |= Constants.MaskMask
      let maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
      _ = SecRandomCopyBytes(kSecRandomDefault, Int(MemoryLayout<UInt32>.size), maskKey)
      offset += MemoryLayout<UInt32>.size

      for i in 0..<dataLength {
        buffer[offset] = data[i] ^ maskKey[i % MemoryLayout<UInt32>.size]
        offset += 1
      }
      var total = 0
      while !sOperation.isCancelled {
        if !self.readyToWrite {
          self.doDisconnect(WSError(type: .outputStreamWriteError, message: "output stream had an error during write", code: 0))
          break
        }
        let stream = self.stream
        let writeBuffer = UnsafeRawPointer(frame!.bytes+total).assumingMemoryBound(to: UInt8.self)
        let len = stream.write(data: Data(bytes: writeBuffer, count: offset-total))
        if len <= 0 {
          self.doDisconnect(WSError(type: .outputStreamWriteError, message: "output stream had an error during write", code: 0))
          break
        } else {
          total += len
        }
        if total >= offset {
          if let callback = writeCompletion {
            self.callbackQueue.async {
              callback()
            }
          }

          break
        }
      }
    }
    writeQueue.addOperation(operation)
  }

  /**
   Used to preform the disconnect delegate
   */
  private func doDisconnect(_ error: (any Error)?) {
    serialQueue.sync {
      guard !self.didDisconnect else { return }
      self.didDisconnect = true
      self.isConnecting = false
      self.mutex.lock()
      self.connected = false
      self.mutex.unlock()
      guard self.canDispatch else {return}
      self.callbackQueue.async { [weak self] in
        guard let self = self else { return }
        self.onDisconnect?(error)
        self.delegate?.websocketDidDisconnect(socket: self, error: error)
        let userInfo = error.map{ [Constants.WebsocketDisconnectionErrorKeyName: $0] }
        NotificationCenter.default.post(name: NSNotification.Name(Constants.Notifications.WebsocketDidDisconnect), object: self, userInfo: userInfo)
      }
    }
  }

  // MARK: - Deinit

  deinit {
    mutex.lock()
    readyToWrite = false
    cleanupStream()
    mutex.unlock()
    writeQueue.cancelAllOperations()
  }

}

extension String {
  func sha1Base64() -> String {
    let data = self.data(using: String.Encoding.utf8)!
    var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
    return Data(digest).base64EncodedString()
  }
}

private extension Data {

  init(buffer: UnsafeBufferPointer<UInt8>) {
    self.init(bytes: buffer.baseAddress!, count: buffer.count)
  }

}

private extension UnsafeBufferPointer {

  func fromOffset(_ offset: Int) -> UnsafeBufferPointer<Element> {
    return UnsafeBufferPointer<Element>(start: baseAddress?.advanced(by: offset), count: count - offset)
  }

}

private let emptyBuffer = UnsafeBufferPointer<UInt8>(start: nil, count: 0)

#if swift(>=4)
#else
fileprivate extension String {
  var count: Int {
    return self.characters.count
  }
}
#endif
