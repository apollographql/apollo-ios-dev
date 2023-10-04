import Foundation
import ApolloCodegenLib

/// Generic representation of a schema download provider.
public protocol SchemaDownloadProvider {
  static func fetch(
    configuration: ApolloSchemaDownloadConfiguration,
    withRootURL rootURL: URL?
  ) async throws
}

extension ApolloSchemaDownloader: SchemaDownloadProvider { }
