import Foundation

public enum MockURLError: Swift.Error {
  case requestNotHandled
}

public final class MockURLProtocol<RequestProvider: MockResponseProvider>: URLProtocol {

  override class public func canInit(with request: URLRequest) -> Bool {
    return true
  }
  
  override class public func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  private var asyncTask: Task<Void, any Error>?

  override public func startLoading() {
    self.asyncTask = Task {
      guard
        let url = self.request.url,
        let handler = await RequestProvider.requestHandler(for: url)
      else {
        self.client?.urlProtocol(self, didFailWithError: MockURLError.requestNotHandled)
        return
      }

      do {
        defer {
          self.client?.urlProtocolDidFinishLoading(self)
        }

        let (response, dataStream) = try await handler(self.request)

        try Task.checkCancellation()

        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        guard let dataStream else {
          return
        }

        for try await data in dataStream {
          try Task.checkCancellation()

          self.client?.urlProtocol(self, didLoad: data)
        }

      } catch {
        self.client?.urlProtocol(self, didFailWithError: error)
      }
    }
  }
  
  override public func stopLoading() {
    self.asyncTask?.cancel()
  }
  
}
