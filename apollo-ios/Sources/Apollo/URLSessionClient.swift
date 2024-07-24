import Foundation

/// A class to handle URL Session calls that will support background execution,
/// but still (mostly) use callbacks for its primary method of communication.
///
/// **NOTE:** Delegate methods implemented here are not documented inline because
/// Apple has their own documentation for them. Please consult Apple's
/// documentation for how the delegate methods work and what needs to be overridden
/// and handled within your app, particularly in regards to what needs to be called
/// when for background sessions.
open class URLSessionClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
  #warning("TODO: This is only open for test mocking. Can we get rid of that mock and make this: (final, private, actor)?")

  public enum URLSessionClientError: Error, LocalizedError {
    case noHTTPResponse(request: URLRequest?)
    case sessionBecameInvalidWithoutUnderlyingError
    case dataForRequestNotFound(request: URLRequest?)
    case networkError(data: Data, response: HTTPURLResponse?, underlying: any Error)
    case sessionInvalidated
    case missingMultipartBoundary
    case cannotParseBoundaryData
    
    public var errorDescription: String? {
      switch self {
      case .noHTTPResponse(let request):
        return "The request did not receive an HTTP response. Request: \(String(describing: request))"
      case .sessionBecameInvalidWithoutUnderlyingError:
        return "The URL session became invalid, but no underlying error was returned."
      case .dataForRequestNotFound(let request):
        return "URLSessionClient was not able to locate the stored data for request \(String(describing: request))"
      case .networkError(_, _, let underlyingError):
        return "A network error occurred: \(underlyingError.localizedDescription)"
      case .sessionInvalidated:
        return "Attempting to create a new request after the session has been invalidated!"
      case .missingMultipartBoundary:
        return "A multipart HTTP response was received without specifying a boundary!"
      case .cannotParseBoundaryData:
        return "Cannot parse the multipart boundary data!"
      }
    }
  }

  /// A completion block returning a result. On `.success` it will contain a tuple with non-nil `Data` and its corresponding `HTTPURLResponse`. On `.failure` it will contain an error.
  public typealias Completion = @Sendable (Result<(Data, HTTPURLResponse), any Error>) -> Void
  
  @Atomic private var tasks: [Int: TaskData] = [:]
  
  /// The raw URLSession being used for this client
  open private(set) var session: URLSession!
  
  @Atomic private var hasBeenInvalidated: Bool = false
  
  private var hasNotBeenInvalidated: Bool {
    !self.hasBeenInvalidated
  }
  
  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - sessionConfiguration: The `URLSessionConfiguration` to use to set up the URL session.
  ///   - callbackQueue: [optional] The `OperationQueue` to tell the URL session to call back to this class on, which will in turn call back to your class. Defaults to `.main`.
  ///   - sessionDescription: [optional] A human-readable string that you can use for debugging purposes.
  public init(sessionConfiguration: URLSessionConfiguration = .default,
              callbackQueue: OperationQueue? = .main,
              sessionDescription: String? = nil) {
    super.init()
      
    let session = URLSession(configuration: sessionConfiguration, 
                             delegate: self,
                             delegateQueue: callbackQueue)
    session.sessionDescription = sessionDescription
    self.session = session
  }
  
  /// Cleans up and invalidates everything related to this session client.
  ///
  /// NOTE: This must be called from the `deinit` of anything holding onto this client in order to break a retain cycle with the delegate.
  #warning("TODO: tasks must be cancelled on invalidation and all removals from client!! This is to make sure the continuation is called!")
  public func invalidate() {
    self.$hasBeenInvalidated.mutate { $0 = true }
    func cleanup() {
      self.session = nil
      self.clearAllTasks()
    }

    guard let session = self.session else {
      // Session's already gone, just cleanup.
      cleanup()
      return
    }

    session.invalidateAndCancel()
    cleanup()
  }
  
  /// Clears underlying dictionaries of any data related to a particular task identifier.
  ///
  /// - Parameter identifier: The identifier of the task to clear.
  open func clear(task identifier: Int) {
    self.$tasks.mutate { _ = $0.removeValue(forKey: identifier) }
  }
  
  /// Clears underlying dictionaries of any data related to all tasks.
  ///
  /// Mostly useful for cleanup and/or after invalidation of the `URLSession`.
  open func clearAllTasks() {
    guard !self.tasks.isEmpty else {
      // Nothing to clear
      return
    }
    
    self.$tasks.mutate { $0.removeAll() }
  }
  
  /// The main method to perform a request.
  ///
  /// - Parameters:
  ///   - request: The request to perform.
  ///   - taskDescription: [optional] A description to add to the `URLSessionTask` for debugging purposes.
  ///
  /// - Returns: The data and response for the request.
  @discardableResult
  open func send(
    _ request: URLRequest,
    taskDescription: String? = nil    
  ) async throws -> (Data, HTTPURLResponse) {
    guard self.hasNotBeenInvalidated else {
      throw URLSessionClientError.sessionInvalidated
    }

    let task = self.session.dataTask(with: request)
    task.taskDescription = taskDescription

    return try await withTaskCancellationHandler {
      return try await withCheckedThrowingContinuation { continuation in
        let taskData = TaskData() {
          switch ($0) {
          case let .success(response):
            continuation.resume(returning: response)

          case let .failure(error):
            continuation.resume(throwing: error)
          }
        }

        self.$tasks.mutate { $0[task.taskIdentifier] = taskData }
        task.resume()
      }

    } onCancel: {
      task.cancel()
    }
  }

  /// Cancels a given task and clears out its underlying data.
  ///
  /// NOTE: You will not receive any kind of "This was cancelled" error when this is called.
  ///
  /// - Parameter task: The task you wish to cancel.
  open func cancel(task: URLSessionTask) {
    self.clear(task: task.taskIdentifier)
    task.cancel()
  }
  
  // MARK: - URLSessionDelegate
  
  open func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
    let finalError = error ?? URLSessionClientError.sessionBecameInvalidWithoutUnderlyingError
    for task in self.tasks.values {
      task.completionBlock(.failure(finalError))
    }
    
    self.clearAllTasks()
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       didFinishCollecting metrics: URLSessionTaskMetrics) {
    // No default implementation
  }
  
  open func urlSession(_ session: URLSession,
                       didReceive challenge: URLAuthenticationChallenge,
                       completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    completionHandler(.performDefaultHandling, nil)
  }
  
  #if os(iOS) || os(tvOS) || os(watchOS)
  open func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    // No default implementation
  }
  #endif
  
  // MARK: - NSURLSessionTaskDelegate
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       didReceive challenge: URLAuthenticationChallenge,
                       completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    completionHandler(.performDefaultHandling, nil)
  }
  
  open func urlSession(_ session: URLSession,
                       taskIsWaitingForConnectivity task: URLSessionTask) {
    // No default implementation
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       didCompleteWithError error: (any Error)?) {
    defer {
      self.clear(task: task.taskIdentifier)
    }
    
    guard let taskData = self.tasks[task.taskIdentifier] else {
      // No completion blocks, the task has likely been cancelled. Bail out.
      return
    }
    
    let data = taskData.data
    let response = taskData.response

    let completion = taskData.completionBlock
    
    if let finalError = error {
      completion(.failure(URLSessionClientError.networkError(data: data, response: response, underlying: finalError)))
    } else {
      guard let finalResponse = response else {
        completion(.failure(URLSessionClientError.noHTTPResponse(request: task.originalRequest)))
        return
      }
      
      completion(.success((data, finalResponse)))
    }
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
    completionHandler(nil)
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       didSendBodyData bytesSent: Int64,
                       totalBytesSent: Int64,
                       totalBytesExpectedToSend: Int64) {
    // No default implementation
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       willBeginDelayedRequest request: URLRequest,
                       completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
    completionHandler(.continueLoading, request)
  }
  
  open func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       willPerformHTTPRedirection response: HTTPURLResponse,
                       newRequest request: URLRequest,
                       completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(request)
  }
  
  // MARK: - URLSessionDataDelegate
  
  open func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard dataTask.state != .canceling else {
      // Task is in the process of cancelling, don't bother handling its data.
      return
    }

    guard let taskData = self.tasks[dataTask.taskIdentifier] else {
      assertionFailure("No data found for task \(dataTask.taskIdentifier), cannot append received data")
      return
    }

    taskData.append(additionalData: data)

    if let httpResponse = dataTask.response as? HTTPURLResponse, httpResponse.isMultipart {
      let multipartHeaderComponents = httpResponse.multipartHeaderComponents
      guard let boundaryString = multipartHeaderComponents.boundary else {
        taskData.completionBlock(.failure(URLSessionClientError.missingMultipartBoundary))
        return
      }

      let boundaryMarker = "--\(boundaryString)"
      guard
        let dataString = String(data: taskData.data, encoding: .utf8)?.trimmingCharacters(in: .newlines),
        let lastBoundaryIndex = dataString.range(of: boundaryMarker, options: .backwards)?.upperBound,
        let boundaryData = dataString.prefix(upTo: lastBoundaryIndex).data(using: .utf8)
      else {
        taskData.completionBlock(.failure(URLSessionClientError.cannotParseBoundaryData))
        return
      }

      let remainingData = dataString.suffix(from: lastBoundaryIndex).data(using: .utf8)
      taskData.reset(data: remainingData)

      taskData.completionBlock(.success((boundaryData, httpResponse)))
    }
  }
  
  open func urlSession(_ session: URLSession,
                       dataTask: URLSessionDataTask,
                       didBecome streamTask: URLSessionStreamTask) {
    // No default implementation
  }
  
  open func urlSession(_ session: URLSession,
                       dataTask: URLSessionDataTask,
                       didBecome downloadTask: URLSessionDownloadTask) {
    // No default implementation
  }
  
  open func urlSession(_ session: URLSession,
                       dataTask: URLSessionDataTask,
                       willCacheResponse proposedResponse: CachedURLResponse,
                       completionHandler: @escaping (CachedURLResponse?) -> Void) {
    completionHandler(proposedResponse)
  }
  
  open func urlSession(_ session: URLSession,
                       dataTask: URLSessionDataTask,
                       didReceive response: URLResponse,
                       completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    defer {
      completionHandler(.allow)
    }
    
    self.$tasks.mutate {
      guard let taskData = $0[dataTask.taskIdentifier] else {
        return
      }
      
      taskData.responseReceived(response: response)
    }
  }
}
