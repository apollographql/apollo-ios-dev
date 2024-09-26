import Foundation

public class MockURLProtocol<RequestProvider: MockRequestProvider>: URLProtocol {
  private let workQueue = DispatchQueue(label: "com.mockurlprotocol.work", qos: .userInitiated)

  override class public func canInit(with request: URLRequest) -> Bool {
    return true
  }
  
  override class public func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }
  
  override public func startLoading() {
    guard let url = self.request.url,
          let handler = RequestProvider.requestHandlers[url] else {
      fatalError("No MockRequestHandler available for URL.")
    }

    workQueue.asyncAfter(deadline: .now() + Double.random(in: 0.0...0.25)) {
      defer {
        RequestProvider.requestHandlers.removeValue(forKey: url)
      }
      
      do {
        let result = try handler(self.request)
        
        switch result {
        case let .success((response, data, chunkingConfig)):
          self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

          if let data = data {
            if let config = chunkingConfig {
                // Simulate chunked data
                 var offset = 0

                 while offset < data.count {
                     let end = min(offset + config.chunkSize, data.count)
                     let chunk = data[offset..<end]

                     self.client?.urlProtocol(self, didLoad: Data(chunk))
                     offset = end

                     if offset < data.count {
                         Thread.sleep(forTimeInterval: 0.1)
                     }
                 }
            } else {
              // Send all data at once
              self.client?.urlProtocol(self, didLoad: data)
            }
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
  typealias MockRequestHandler = ((URLRequest) throws -> Result<(HTTPURLResponse, Data?, ChunkingConfig?), any Error>)

  // Dictionary of mock request handlers where the `key` is the URL of the request.
  static var requestHandlers: [URL: MockRequestHandler] { get set }
}

public struct ChunkingConfig {
    let chunkSize: Int

    public init(chunkSize: Int = 10) {
        self.chunkSize = chunkSize
    }
}
