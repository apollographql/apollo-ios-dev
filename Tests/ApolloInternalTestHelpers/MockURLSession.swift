import Foundation
import Apollo
import ApolloAPI

/// In order to allow mutable stubbing of response data and capturing of requests, **this mock is
/// not thread-safe**. It uses `nonisolated(unsafe)` to disable Strict Concurrency checks.
public final class MockURLSessionClient: URLSessionClient {

  nonisolated(unsafe) public var requestCount = 0

  public var lastRequest: URLRequest? { _lastRequest.wrappedValue }
  nonisolated(unsafe) private var _lastRequest: Atomic<URLRequest?> = .init(wrappedValue: nil)

  nonisolated(unsafe) public var jsonData: JSONObject?
  nonisolated(unsafe) public var data: Data?
  var responseData: Data? {
    if let data = data { return data }
    if let jsonData = jsonData {
      return try! JSONSerializationFormat.serialize(value: jsonData)
    }
    return nil
  }

  nonisolated(unsafe) public var response: HTTPURLResponse?
  nonisolated(unsafe) public var error: (any Error)?

  private let callbackQueue: DispatchQueue
  
  public init(callbackQueue: DispatchQueue? = nil, response: HTTPURLResponse? = nil, data: Data? = nil) {
    self.callbackQueue = callbackQueue ?? .main
    self.response = response
    self.data = data
  }

  public override func sendRequest(_ request: URLRequest,
                                   taskDescription: String? = nil,
                                   rawTaskCompletionHandler: URLSessionClient.RawCompletion? = nil,
                                   completion: @escaping URLSessionClient.Completion) -> URLSessionTask {
    self._lastRequest.mutate {
      $0 = request
      self.requestCount += 1
    }

    // Capture data, response, and error instead of self to ensure we complete with the current state
    // even if it is changed before the block runs.
    callbackQueue.async { [responseData, response, error] in
      rawTaskCompletionHandler?(responseData, response, error)
      
      if let error = error {
        completion(.failure(error))
      } else {
        guard let data = responseData else {
          completion(.failure(URLSessionClientError.dataForRequestNotFound(request: request)))
          return
        }
        
        guard let response = response else {
          completion(.failure(URLSessionClientError.noHTTPResponse(request: request)))
          return
        }
        
        completion(.success((data, response)))
      }
    }

    let mockTaskType: any URLSessionDataTaskMockProtocol.Type = URLSessionDataTaskMock.self
    let mockTask = mockTaskType.init() as! URLSessionDataTaskMock
    return mockTask
  }
}

protocol URLSessionDataTaskMockProtocol {
  init()
}

private final class URLSessionDataTaskMock: URLSessionDataTask, URLSessionDataTaskMockProtocol, @unchecked Sendable {

  override func resume() {
    // No-op
  }

  override func cancel() {}
}
