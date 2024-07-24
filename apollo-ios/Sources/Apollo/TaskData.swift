import Foundation

/// A wrapper for data about a particular task handled by `URLSessionClient`
public class TaskData {

  public let completionBlock: URLSessionClient.Completion
  private(set) var data: Data = Data()
  private(set) var response: HTTPURLResponse? = nil
  
  init(completionBlock: @escaping URLSessionClient.Completion) {
    self.completionBlock = completionBlock
  }
  
  func append(additionalData: Data) {
    self.data.append(additionalData)
  }

  func reset(data: Data?) {
    guard let data, !data.isEmpty else {
      self.data = Data()
      return
    }

    self.data = data
  }
  
  func responseReceived(response: URLResponse) {
    if let httpResponse = response as? HTTPURLResponse {
      self.response = httpResponse
    }
  }
}
