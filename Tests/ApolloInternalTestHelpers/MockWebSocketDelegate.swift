import Foundation
import ApolloWebSocket

public class MockWebSocketDelegate: WebSocketClientDelegate {
  public var didReceiveMessage: ((String) -> Void)?

  public init() {}

  public func websocketDidConnect(socket: any WebSocketClient) {}

  public func websocketDidDisconnect(socket: any WebSocketClient, error: (any Error)?) {}

  public func websocketDidReceiveMessage(socket: any WebSocketClient, text: String) {
    didReceiveMessage?(text)
  }

  public func websocketDidReceiveData(socket: any WebSocketClient, data: Data) {}
}
