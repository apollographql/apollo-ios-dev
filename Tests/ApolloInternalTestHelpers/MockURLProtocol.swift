import Foundation

public class MockURLProtocol<RequestProvider: MockRequestProvider>: URLProtocol {
  
  override class public func canInit(with request: URLRequest) -> Bool {
    return true
  }
  
  override class public func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }
  
  @MainActor
  override public func startLoading() {
    guard let url = self.request.url,
          let handler = RequestProvider.requestHandlers[url] else {
      fatalError("No MockRequestHandler available for URL.")
    }

    Task {
      try await Task.sleep(nanoseconds: UInt64(.random(in: 0.0...0.25) * 1_000_000_000))
    
      defer {
        RequestProvider.requestHandlers.removeValue(forKey: url)
      }
      
      do {
        let result = try handler(request)
        
        switch result {
        case let .success((response, data)):
          self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          
          if let data = data {
            self.client?.urlProtocol(self, didLoad: data)
          }
          
          self.client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
          self.client?.urlProtocol(self, didFailWithError: error)
        }
        
      } catch {
        self.client?.urlProtocol(self, didFailWithError: error)
      }
    }
  }
  
  override public func stopLoading() {
  }
  
}

public protocol MockRequestProvider {
  typealias MockRequestHandler = (@Sendable (URLRequest) throws -> Result<(HTTPURLResponse, Data?), any Error>)

  // Dictionary of mock request handlers where the `key` is the URL of the request.
  static var requestHandlers: [URL: MockRequestHandler] { get set }
}
