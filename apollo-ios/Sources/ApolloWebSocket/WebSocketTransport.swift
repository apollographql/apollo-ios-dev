import Apollo
import ApolloAPI
import Foundation

public actor WebSocketTransport: SubscriptionNetworkTransport {

  public enum Error: Swift.Error {
    /// WebSocketTransport has not yet been implemented for Apollo iOS 2.0. This will be implemented in a future
    /// release.
    case notImplemented
  }

  struct Constants {
//    static let headerWSUpgradeName     = "Upgrade"
//    static let headerWSUpgradeValue    = "websocket"
//    static let headerWSHostName        = "Host"
//    static let headerWSConnectionName  = "Connection"
//    static let headerWSConnectionValue = "Upgrade"
    static let headerWSProtocolName    = "Sec-WebSocket-Protocol"
//    static let headerWSVersionName     = "Sec-WebSocket-Version"
//    static let headerWSVersionValue    = "13"
//    static let headerWSExtensionName   = "Sec-WebSocket-Extensions"
//    static let headerWSKeyName         = "Sec-WebSocket-Key"
    static let headerOriginName        = "Origin"
//    static let headerWSAcceptName      = "Sec-WebSocket-Accept"
//    static let BUFFER_MAX              = 4096
//    static let FinMask: UInt8          = 0x80
//    static let OpCodeMask: UInt8       = 0x0F
//    static let RSVMask: UInt8          = 0x70
//    static let RSV1Mask: UInt8         = 0x40
//    static let MaskMask: UInt8         = 0x80
//    static let PayloadLenMask: UInt8   = 0x7F
//    static let MaxFrameSize: Int       = 32
//    static let httpSwitchProtocolCode  = 101
//    static let supportedSSLSchemes     = ["wss", "https"]
//    static let WebsocketDisconnectionErrorKeyName = "WebsocketDisconnectionErrorKeyName"
//
//    struct Notifications {
//      static let WebsocketDidConnect = "WebsocketDidConnectNotification"
//      static let WebsocketDidDisconnect = "WebsocketDidDisconnectNotification"
//    }
  }

  public let session: WebSocketURLSession

  private let request: URLRequest

  private var connection: WebSocketConnection?

  public init(
    url: URL,
    session: WebSocketURLSession,
    protocol: WebSocketProtocol
  ) {
    self.session = session
    self.request = Self.makeRequest(url: url, protocol: `protocol`)
    self.connection = WebSocketConnection(task: session.webSocketTask(with: request))
  }

  private static func makeRequest(
    url: URL,
    protocol: WebSocketProtocol
  ) -> URLRequest {
    var request = URLRequest(url: url)

    if request.value(forHTTPHeaderField: Constants.headerOriginName) == nil {
      var origin = url.absoluteString
      if let hostUrl = URL (string: "/", relativeTo: url) {
        origin = hostUrl.absoluteString
        origin.remove(at: origin.index(before: origin.endIndex))
      }
      request.setValue(origin, forHTTPHeaderField: Constants.headerOriginName)
    }

    request.setValue(`protocol`.description, forHTTPHeaderField: Constants.headerWSProtocolName)

    return request
  }

  nonisolated public func send<Subscription: GraphQLSubscription>(
    subscription: Subscription,
    fetchBehavior: Apollo.FetchBehavior,
    requestConfiguration: Apollo.RequestConfiguration
  ) throws -> AsyncThrowingStream<Apollo.GraphQLResponse<Subscription>, any Swift.Error> {
    throw Error.notImplemented
  }

}

public final class WebSocketConnection: Sendable {

  //  enum State {
  //    case notStarted
  //    case connecting
  //    case connected
  //    case disconnected
  //  }

  //  private unowned let transport: WebSocketTransport
  private let webSocketTask: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) {
    self.webSocketTask = task
  }

  deinit {
    self.webSocketTask.cancel(with: .goingAway, reason: nil)
  }

  func openConnection() async throws -> AsyncThrowingStream<URLSessionWebSocketTask.Message, any Swift.Error> {
    webSocketTask.resume()
    return AsyncThrowingStream { [weak self] in
      guard let self else { return nil }

      try Task.checkCancellation()

      let message = try await self.webSocketTask.receive()

      return Task.isCancelled ? nil : message
    }
  }

  func send(with: Any) throws {

  }

}

public protocol GraphQLWebSocketRequest<Operation>: Sendable {
  associatedtype Operation: GraphQLOperation

  /// The GraphQL Operation to execute
  var operation: Operation { get set }

  /// The ``FetchBehavior`` to use for this request.
  /// Determines if fetching will include cache/network.
  var fetchBehavior: FetchBehavior { get set }

  /// Determines if the results of a network fetch should be written to the local cache.
  var writeResultsToCache: Bool { get set }

  /// The timeout interval specifies the limit on the idle interval allotted to a request in the process of
  /// loading. This timeout interval is measured in seconds.
  var requestTimeout: TimeInterval? { get set }
}
