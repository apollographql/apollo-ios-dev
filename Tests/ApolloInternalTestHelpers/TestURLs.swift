import Foundation

/// URLs used in testing
public enum TestURL {
  case mockServer
  case mockPort8080
  case mockWebSocket

  public var url: URL {
    let urlString: String
    switch self {
    case .mockServer:
      urlString = "http://localhost/dummy_url"
    case .mockPort8080:
      urlString = "http://localhost:8080/graphql"
    case .mockWebSocket:
      urlString = "ws://localhost:8080/subscriptions"
    }
    
    return URL(string: urlString)!
  }
}
