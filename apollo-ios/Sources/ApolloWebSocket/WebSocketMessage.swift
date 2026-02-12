import Apollo
import ApolloAPI

extension WebSocketTransport {
  typealias OperationID = Int

  /// GraphQL Websocket Transport Protocol Messages
  ///
  /// The messages sent and recieved by a websocket in conformance with the the `graphql-ws` protocol.
  /// This implementation is in conformance as of Feb. 2026 according to the protocol as defined at:
  /// https://github.com/enisdenjo/graphql-ws/blob/6a31f46cce25644d30253da351978e452ae583a7/PROTOCOL.md
  enum Message {
    enum Outgoing {
      /// Indicates that the client wants to establish a connection within the existing socket.
      /// This connection is not the actual WebSocket communication channel, but is rather a frame within it asking
      /// the server to allow future operation requests.
      ///
      /// The server must receive the connection initialisation message within the allowed waiting time specified in
      /// the `connectionInitWaitTimeout` parameter during the server setup. If the client does not request a
      /// connection within the allowed timeout, the server will close the socket with the event:
      /// `4408: Connection initialisation timeout.`
      ///
      /// If the server receives more than one ConnectionInit message at any given time, the server will close the
      /// socket with the event
      /// `4429: Too many initialisation requests.`
      ///
      /// If the server wishes to reject the connection, for example during authentication, it is recommended to close
      /// the socket with
      /// `4403: Forbidden.`
      case connectionInit(payload: JSONObject?)

      /// Useful for detecting failed connections, displaying latency metrics or other types of network probing.
      ///
      /// A Pong must be sent in response from the receiving party as soon as possible.
      ///
      /// The Ping message can be sent at any time within the established socket.
      ///
      /// The optional payload field can be used to transfer additional details about the ping.
      case ping(payload: JSONObject?)

      /// The response to the Ping message. Must be sent as soon as the Ping message is received.
      ///
      /// The Pong message can be sent at any time within the established socket.
      /// Furthermore, the Pong message may even be sent unsolicited as an unidirectional heartbeat.
      ///
      /// The optional payload field can be used to transfer additional details about the pong.
      case pong(payload: JSONObject?)

      /// Requests an operation specified in the message payload. This message provides a unique ID field to connect
      /// published messages to the operation requested by this message.
      ///
      /// If there is already an active subscriber for an operation matching the provided ID, regardless of the
      /// operation type, the server must close the socket immediately with the event
      /// `4409: Subscriber for <unique-operation-id> already exists.`
      ///
      /// The server needs only keep track of IDs for as long as the subscription is active.
      /// Once a client completes an operation, it is free to re-use that ID.
      ///
      /// Executing operations is allowed only after the server has acknowledged the connection through the
      /// ConnectionAck message, if the connection is not acknowledged, the socket will be closed immediately with the
      /// event `4401: Unauthorized.`
      case subscribe(id: OperationID, payload: SubscribePayload)
    }

    enum Incoming {
      ///Expected response to the ConnectionInit message from the client acknowledging a successful connection with
      ///the server.
      ///
      ///The server can use the optional payload field to transfer additional details about the connection.
      ///
      ///The client is now ready to request subscription operations.
      case connectionAck(payload: JSONObject?)

      /// Useful for detecting failed connections, displaying latency metrics or other types of network probing.
      ///
      /// A Pong must be sent in response from the receiving party as soon as possible.
      ///
      /// The Ping message can be sent at any time within the established socket.
      ///
      /// The optional payload field can be used to transfer additional details about the ping.
      case ping(payload: JSONObject?)

      /// The response to the Ping message. Must be sent as soon as the Ping message is received.
      ///
      /// The Pong message can be sent at any time within the established socket.
      /// Furthermore, the Pong message may even be sent unsolicited as an unidirectional heartbeat.
      ///
      /// The optional payload field can be used to transfer additional details about the pong.
      case pong(payload: JSONObject?)

      /// Operation execution result(s) from the source stream created by the binding Subscribe message.
      /// After all results have been emitted, the Complete message will follow indicating stream completion.
      case next(id: OperationID, payload: JSONObject)

      /// Operation execution error(s) in response to the Subscribe message.
      /// This can occur before execution starts, usually due to validation errors, or during the execution of the
      /// request. This message terminates the operation and no further messages will be sent.
      case error(id: OperationID, payload: [GraphQLError])
    }

  }

  struct SubscribePayload {
    let operationName: String?
    let query: String
    let variables: GraphQLOperation.Variables?
    let extensions: JSONObject?
  }

}

// MARK: - Message Type Values

extension WebSocketTransport.Message.Outgoing {
  var type: String {
    switch self {
    case .connectionInit: return "connection_init"
    case .ping: return "ping"
    case .pong: return "pong"
    case .subscribe: return "subscribe"
    }
  }
}

extension WebSocketTransport.Message.Incoming {
  var type: String {
    switch self {
    case .connectionAck: return "connection_ack"
    case .ping: return "ping"
    case .pong: return "pong"
    case .next: return "next"
    case .error: return "error"
    }
  }
}
