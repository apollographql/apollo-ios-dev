import Foundation
@_spi(Testable) import ApolloWebSocket

public class MockWebSocket: WebSocketClient {
  
  public var request: URLRequest
  public var callbackQueue: DispatchQueue = DispatchQueue.main
  public var delegate: (any WebSocketClientDelegate)? = nil
  public var isConnected: Bool = false
    
  public required init(request: URLRequest, protocol: WebSocket.WSProtocol) {
    self.request = request

    self.request.setValue(`protocol`.description, forHTTPHeaderField: WebSocket.Constants.headerWSProtocolName)
  }
  
  open func reportDidConnect() {
    nonisolated(unsafe) let unsafeSelf = self
    callbackQueue.async {
      unsafeSelf.delegate?.websocketDidConnect(socket: unsafeSelf)
    }
  }
  
  open func write(string: String) {
    nonisolated(unsafe) let unsafeSelf = self
    callbackQueue.async {
      unsafeSelf.delegate?.websocketDidReceiveMessage(socket: unsafeSelf, text: string)
    }
  }
  
  open func write(ping: Data, completion: (() -> ())?) {
  }

  public func disconnect(forceTimeout: TimeInterval?) {
  }
  
  public func connect() {
  }
}

public class ProxyableMockWebSocket: MockWebSocket, SOCKSProxyable {
  public var enableSOCKSProxy: Bool = false
}
