import Foundation
#if !COCOAPODS
@_spi(unsafe_JSON) import ApolloAPI
#endif

/// Parses JSON response data into a `GraphQLResult`.
public struct JSONResponseParser {

  public enum ParsingError: Error, LocalizedError {
    case noResponseToParse
    case couldNotParseToJSON(data: Data)
    case mismatchedCurrentResultType
    case couldNotParseIncrementalJSON(json: JSONValue)

    public var errorDescription: String? {
      switch self {
      case .noResponseToParse:
        return "The JSON response parsing interceptor was called before a response was received. Double-check the order of your interceptors."

      case .couldNotParseToJSON(let data):
        var errorStrings = [String]()
        errorStrings.append("Could not parse data to JSON format.")
        if let dataString = String(bytes: data, encoding: .utf8) {
          errorStrings.append("Data received as a String was:")
          errorStrings.append(dataString)
        } else {
          errorStrings.append("Data of count \(data.count) also could not be parsed into a String.")
        }

        return errorStrings.joined(separator: " ")

      case .mismatchedCurrentResultType:
        return "Partial result type operation does not match incremental result type operation."

      case let .couldNotParseIncrementalJSON(json):
        return "Could not parse incremental values - got \(json)."
      }
    }
  }

  public var id: String = UUID().uuidString
  private let resultStorage = ResultStorage()

  private actor ResultStorage {
    var currentResult: Any?
    var currentCacheRecords: RecordSet?

    func mutate<T>(_ block: (isolated ResultStorage) throws -> T) rethrows -> T {
      try block(self)
    }
  }

  public init() { }

  public func parseJSONResult<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>
  ) async throws -> (result: GraphQLResult<Operation.Data>, cacheRecords: RecordSet?) {
    guard
      let body = try? JSONSerializationFormat.deserialize(data: response.rawData) as? JSONObject
    else {
      throw ParsingError.couldNotParseToJSON(data: response.rawData)
    }

    return try await resultStorage.mutate { isolatedStorage in
      try Task.checkCancellation()

      let parsed = try parseResponse(with: body, storage: isolatedStorage)

      isolatedStorage.currentResult = parsed.result
      isolatedStorage.currentCacheRecords = parsed.cacheRecords

      return parsed
    }

    func parseResponse(
      with body: JSONObject,
      storage: isolated ResultStorage
    ) throws -> (result: GraphQLResult<Operation.Data>, cacheRecords: RecordSet?) {
      if let currentResult = storage.currentResult {
        return try parseIncrementalResponse(
          adding: body,
          to: (currentResult, storage.currentCacheRecords)
        )
      } else {
        return try parseNonIncrementalResponse(with: body)
      }

      func parseIncrementalResponse(
        adding body: JSONObject,
        to previous: (result: Any, cacheRecords: RecordSet?)
      ) throws -> (GraphQLResult<Operation.Data>, RecordSet?) {
        guard var currentResult = previous.result as? GraphQLResult<Operation.Data> else {
          throw ParsingError.mismatchedCurrentResultType
        }

        guard let incrementalItems = body["incremental"] as? [JSONObject] else {
          throw ParsingError.couldNotParseIncrementalJSON(json: body)
        }

        var currentCacheRecords = previous.cacheRecords ?? RecordSet()

        for item in incrementalItems {
          let incrementalResponse = try IncrementalGraphQLResponse<Operation>(
            operation: request.operation,
            body: item
          )
          let (incrementalResult, incrementalCacheRecords) = try incrementalResponse.parseIncrementalResult(
            withCachePolicy: request.cachePolicy
          )
          currentResult = try currentResult.merging(incrementalResult)

          if let incrementalCacheRecords {
            currentCacheRecords.merge(records: incrementalCacheRecords)
          }
        }

        return (currentResult, currentCacheRecords)
      }

      func parseNonIncrementalResponse(
        with body: JSONObject
      ) throws -> (GraphQLResult<Operation.Data>, RecordSet?) {
        let graphQLResponse = GraphQLResponse(
          operation: request.operation,
          body: SendableJSONObject(unsafe: body)
        )
        return try graphQLResponse.parseResult(withCachePolicy: request.cachePolicy)
      }
    }
  }

}
