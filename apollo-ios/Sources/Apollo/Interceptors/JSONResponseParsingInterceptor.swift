import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// An interceptor which parses JSON response data into a `GraphQLResult` and attaches it to the
/// `HTTPResponse`.
///
/// This interceptor can also parse multipart response data. Multipart response are seperated into
/// chunks which are each forwarded to the next interceptor using
/// `RequestChain.NextAction.multiProceed`.
public struct JSONResponseParsingInterceptor: ApolloInterceptor {

  public enum ParsingError: Error, LocalizedError, Equatable {
    case noResponseToParse
    case cannotParseMultipartResponse
    case cannotParseResponseData

    public var errorDescription: String? {
      switch self {
      case .noResponseToParse:
        return "There is no response to parse. Check the order of your interceptors."
      case .cannotParseMultipartResponse:
        return "The multi-part response data could not be parsed."
      case .cannotParseResponseData:
        return "The response data could not be parsed."
      }
    }
  }

  private static let multipartResponseParsers: [String: any MultipartResponseSpecificationParser.Type] = [
    MultipartResponseSubscriptionParser.protocolSpec: MultipartResponseSubscriptionParser.self,
    MultipartResponseDeferParser.protocolSpec: MultipartResponseDeferParser.self,
  ]

  public var id: String = UUID().uuidString

  private let responseParser = JSONResponseParser()

  public init() { }

  public func intercept<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPResponse<Operation>?
  ) async throws -> RequestChain.NextAction<Operation> {

    guard let response else {
        throw ParsingError.noResponseToParse
    }

    switch response.httpResponse.isMultipart {
    case false:
      let parsedResponse = try await parseSingleResponse(
        request: request,
        response: response.httpResponse,
        rawData: response.rawData
      )

      return .proceed(request: request, response: parsedResponse)

    case true:
      return try await parseAndStreamMultipartResponseResults(
        request: request,
        multipartResponse: response
      )
    }
  }

  private func parseSingleResponse<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    response: HTTPURLResponse,
    rawData: Data
  ) async throws -> HTTPResponse<Operation> {
    var response = HTTPResponse<Operation>(
      response: response,
      rawData: rawData,
      parsedResult: nil,
      cacheRecords: nil
    )

    let parsed = try await responseParser.parseJSONResult(
      request: request,
      response: response
    )
    response.parsedResult = parsed.result
    response.cacheRecords = parsed.cacheRecords
    return response
  }

  private func parseAndStreamMultipartResponseResults<Operation: GraphQLOperation>(
    request: HTTPRequest<Operation>,
    multipartResponse response: HTTPResponse<Operation>
  ) async throws -> RequestChain.NextAction<Operation> {
    let multipartComponents = response.httpResponse.multipartHeaderComponents

    guard
      let boundary = multipartComponents.boundary,
      let `protocol` = multipartComponents.protocol,
      let parser = Self.multipartResponseParsers[`protocol`]
    else {
      throw ParsingError.cannotParseMultipartResponse
    }

    guard let dataString = String(data: response.rawData, encoding: .utf8) else {
      throw ParsingError.cannotParseResponseData
    }

    return .multiProceed(AsyncThrowingStream() { continuation in
      let task = Task {
        for chunk in dataString.components(separatedBy: "--\(boundary)") {
          if chunk.isEmpty || chunk.isBoundaryMarker { continue }

          switch parser.parse(chunk) {
          case let .success(data):
            // Some chunks can be successfully parsed but do not require to be passed on to the next
            // interceptor, such as an HTTP subscription heartbeat message.
            if let data {
              let parsedResponse = try await parseSingleResponse(
                request: request,
                response: response.httpResponse,
                rawData: data
              )
              continuation.yield(.proceed(request: request, response: parsedResponse))
            }

          case let .failure(parserError):
            throw parserError
          }

          continuation.finish()
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    })
  }
}

fileprivate extension String {
  var isBoundaryMarker: Bool { self == "--" }
}
