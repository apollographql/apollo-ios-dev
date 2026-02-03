import Apollo
import ApolloAPI
import Foundation

public actor WebSocketTransport: SubscriptionNetworkTransport, NetworkTransport {

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
    static let headerWSProtocolName = "Sec-WebSocket-Protocol"
    //    static let headerWSVersionName     = "Sec-WebSocket-Version"
    //    static let headerWSVersionValue    = "13"
    //    static let headerWSExtensionName   = "Sec-WebSocket-Extensions"
    //    static let headerWSKeyName         = "Sec-WebSocket-Key"
    static let headerOriginName = "Origin"
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

  public let urlSession: WebSocketURLSession

  public let store: ApolloStore

  private let request: URLRequest

  private var connection: WebSocketConnection?

  public init(
    urlSession: WebSocketURLSession,
    store: ApolloStore,
    endpointURL: URL,
    protocol: WebSocketProtocol
  ) {
    self.urlSession = urlSession
    self.store = store
    self.request = Self.makeRequest(endpointURL: endpointURL, protocol: `protocol`)
    self.connection = WebSocketConnection(task: urlSession.webSocketTask(with: request))
  }

  private static func makeRequest(
    endpointURL: URL,
    protocol: WebSocketProtocol
  ) -> URLRequest {
    var request = URLRequest(url: endpointURL)

    if request.value(forHTTPHeaderField: Constants.headerOriginName) == nil {
      var origin = endpointURL.absoluteString
      if let hostUrl = URL(string: "/", relativeTo: endpointURL) {
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

  nonisolated public func send<Mutation: GraphQLMutation>(
    mutation: Mutation,
    requestConfiguration: RequestConfiguration
  ) throws -> AsyncThrowingStream<GraphQLResponse<Mutation>, any Swift.Error> {
    throw Error.notImplemented
  }

  nonisolated public func send<Query: GraphQLQuery>(
    query: Query,
    fetchBehavior: FetchBehavior,
    requestConfiguration: RequestConfiguration
  ) throws
    -> AsyncThrowingStream<GraphQLResponse<Query>, any Swift.Error>
  {
    throw Error.notImplemented
  }

}
