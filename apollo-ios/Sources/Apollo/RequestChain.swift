#if !COCOAPODS
import ApolloAPI
#endif

//public protocol RequestChain: Sendable, Cancellable {
//
//  var isCancelled: Bool { get }
//
//  func kickoff<Operation: GraphQLOperation>(
//    request: HTTPRequest<Operation>
//  ) async -> Result<GraphQLResult<Operation.Data>, any Error>
//
//  func proceed<Operation: GraphQLOperation>(
//    request: HTTPRequest<Operation>,
//    response: HTTPResponse<Operation>?,
//    interceptor: any ApolloInterceptor
//  ) async -> Result<GraphQLResult<Operation.Data>, any Error>
//
//  func retry<Operation: GraphQLOperation>(
//    request: HTTPRequest<Operation>
//  ) async -> Result<GraphQLResult<Operation.Data>, any Error>
//
//  func handleErrorAsync<Operation: GraphQLOperation>(
//    _ error: any Error,
//    request: HTTPRequest<Operation>,
//    response: HTTPResponse<Operation>?
//  ) async -> Result<GraphQLResult<Operation.Data>, any Error>
//
//  func returnValueAsync<Operation: GraphQLOperation>(
//    for request: HTTPRequest<Operation>,
//    value: GraphQLResult<Operation.Data>
//  ) async -> Result<GraphQLResult<Operation.Data>, any Error>
//
//}
