import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// A marker protocol to set up an object to pass through the request chain.
///
/// Used to allow additional context-specific information to pass the length of the request chain.
///
/// This allows the various interceptors to make modifications, or perform actions, with information
/// that they cannot get just from the existing operation. It can be anything that conforms to this protocol.
public protocol RequestContext {}

/// A specialized request context that specifies configuration details for the URLRequest.
public protocol RequestConfigurationContext: RequestContext {
  /// The timeout interval specifies the limit on the idle interval allotted to a request in the process of
  /// loading. This timeout interval is measured in seconds.
  var requestTimeout: TimeInterval { get }
}
