import Foundation
import Combine
#if !COCOAPODS
import ApolloAPI
#endif

public struct JSONResponseParser<Operation: GraphQLOperation>: Sendable {

  public enum Error: Swift.Error, LocalizedError {
    case couldNotParseToJSON(data: Data)
    case missingMultipartBoundary
    case invalidMultipartProtocol
    case couldNotParseIncrementalJSON(json: JSONObject)

    public var errorDescription: String? {
      switch self {
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

      case .missingMultipartBoundary:
        return "Missing multipart boundary in the response 'content-type' header."

      case .invalidMultipartProtocol:
        return "Missing, or unknown, multipart specification protocol in the response 'content-type' header."

      case let .couldNotParseIncrementalJSON(json):
        return "Could not parse incremental values - got \(json)."
      }
    }
  }

  public typealias ParsedResult = (GraphQLResult<Operation.Data>, RecordSet?)
  typealias ParsedResultStream = AsyncThrowingStream<ParsedResult, any Swift.Error>

  let response: HTTPURLResponse
  let operationVariables: Operation.Variables?
  let includeCacheRecords: Bool

  init(
    response: HTTPURLResponse,
    operationVariables: Operation.Variables?,
    includeCacheRecords: Bool
  ) {
    self.response = response
    self.operationVariables = operationVariables
    self.includeCacheRecords = includeCacheRecords
  }

  func parsedJSONResultPublisher(
    byteStream: URLSession.AsyncBytes
  ) -> AnyPublisher<ParsedResult, any Swift.Error> {
    let subject = PassthroughSubject<ParsedResult, any Swift.Error>()

    Task {
      do {
        defer { subject.send(completion: .finished) }
        try Task.checkCancellation()

        for try await result in parseJSONtoResults(
          fromByteStream: byteStream
        ) {
          try Task.checkCancellation()
          subject.send(result)
        }

      } catch {
        subject.send(completion: .failure(error))
      }
    }

    return AnyPublisher(subject)
  }

  func parseJSONtoResults(
    fromByteStream byteStream: URLSession.AsyncBytes
  ) -> ParsedResultStream {
    AsyncThrowingStream { continuation in
      #warning("Do we need to catch and yield errors inside the Task, or will they throw properly on their own?")
      let task = Task {
        switch response.isMultipart {
        case false:
          var data = Data()
          for try await byte in byteStream {
            data.append(byte)
          }
          try Task.checkCancellation()

          let response = try await parseSingleResponse(data: data)
          try Task.checkCancellation()

          continuation.yield(response)

        case true:
          let multipartHeader = response.multipartHeaderComponents
          guard let boundary = multipartHeader.boundary else {
            throw Error.missingMultipartBoundary
          }

          guard
            let `protocol` = multipartHeader.`protocol`,
            let parser = multipartParser(forProtocol: `protocol`)
          else {
            continuation.finish(throwing: Error.invalidMultipartProtocol)
            return
          }

          let parsedChunksStream = parseChunksFrom(
            multipartResponseDataStream: byteStream,
            withMultipartParser: parser,
            multipartBoundary: boundary
          )

          if let incrementalParser = parser as? any IncrementalResponseSpecificationParser.Type {
            try await executeIncrementalResponses(from: parsedChunksStream, into: continuation)

          } else {
            for try await chunk in parsedChunksStream {
              let response = try await parseSingleResponse(body: chunk)
              try Task.checkCancellation()

              continuation.yield(response)
            }
          }
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - Single Response Parsing

  private func parseSingleResponse(data: Data) async throws -> ParsedResult {
    guard
      let body = try? JSONSerializationFormat.deserialize(data: data) as JSONObject
    else {
      throw Error.couldNotParseToJSON(data: data)
    }

    return try await parseSingleResponse(body: body)
  }

  private func parseSingleResponse(body: JSONObject) async throws -> ParsedResult {
    let executionHandler = SingleResponseExecutionHandler(
      responseBody: body,
      operationVariables: operationVariables
    )
    return try await executionHandler.execute(includeCacheRecords: includeCacheRecords)
  }

  // MARK: - Multipart Response Parsing

  private func parseChunksFrom(
    multipartResponseDataStream byteStream: URLSession.AsyncBytes,
    withMultipartParser parser: any MultipartResponseSpecificationParser.Type,
    multipartBoundary: String
  ) -> AsyncThrowingStream<JSONObject, any Swift.Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var currentChunkString = String()

          for try await line in byteStream.lines {
            try Task.checkCancellation()

            if line == "--\(multipartBoundary)" {
              defer { currentChunkString = String() }
              let chunk = currentChunkString

              if chunk.isEmpty { continue }
              let chunkData = try parser.parse(multipartChunk: chunk)

              // Some chunks can be successfully parsed but do not require to be passed on to the next
              // interceptor, such as an HTTP subscription heartbeat message.
              if let chunkData {
                continuation.yield(chunkData)
              }

            } else {
              currentChunkString.append(line)
            }
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func multipartParser(
    forProtocol protocol: String
  ) -> (any MultipartResponseSpecificationParser.Type)? {
    switch `protocol` {
    case MultipartResponseSubscriptionParser.protocolSpec:
      return MultipartResponseSubscriptionParser.self

    case MultipartResponseDeferParser.protocolSpec:
      return MultipartResponseDeferParser.self

    default: return nil
    }
  }

  private func executeIncrementalResponses(
    from parsedChunksStream: AsyncThrowingStream<JSONObject, any Swift.Error>,
    into resultStreamContinuation: AsyncThrowingStream<ParsedResult, any Swift.Error>.Continuation
  ) async throws {
    var currentResult: GraphQLResult<Operation.Data>!
    var currentCacheRecords: RecordSet?

    for try await chunk in parsedChunksStream {
      try Task.checkCancellation()

      if currentResult == nil {
        // Parse initial incremental chunk
        (currentResult, currentCacheRecords) = try await parseSingleResponse(body: chunk)
        try Task.checkCancellation()

        resultStreamContinuation.yield((currentResult, currentCacheRecords))
        continue
      }

      guard let incrementalItems = chunk["incremental"] as? [JSONObject] else {
        throw Error.couldNotParseIncrementalJSON(json: chunk)
      }

      for item in incrementalItems {
        let (incrementalResult, incrementalCacheRecords) = try await executeIncrementalItem(
          itemBody: item
        )
        try Task.checkCancellation()

        currentResult = try currentResult.merging(incrementalResult)

        if let incrementalCacheRecords {
          currentCacheRecords?.merge(records: incrementalCacheRecords)
        }
      }

      resultStreamContinuation.yield((currentResult, currentCacheRecords))
    }
  }

  private func executeIncrementalItem(
    itemBody: JSONObject
  ) async throws -> (IncrementalGraphQLResult, RecordSet?) {
    let incrementalExecutionHandler = try IncrementalResponseExecutionHandler(
      responseBody: itemBody,
      operationVariables: operationVariables
    )

    return try await incrementalExecutionHandler.execute(includeCacheRecords: includeCacheRecords)
  }

}

// MARK: - Helper Extensions

fileprivate extension String {
  var isBoundaryMarker: Bool { self == "--" }
}
