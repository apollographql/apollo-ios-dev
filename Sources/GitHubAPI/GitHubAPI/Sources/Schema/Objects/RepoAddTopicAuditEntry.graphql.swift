// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Objects {
  /// Audit log entry for a repo.add_topic event.
  static let RepoAddTopicAuditEntry = ApolloAPI.Object(
    typename: "RepoAddTopicAuditEntry",
    implementedInterfaces: [
      Interfaces.AuditEntry.self,
      Interfaces.Node.self,
      Interfaces.OrganizationAuditEntryData.self,
      Interfaces.RepositoryAuditEntryData.self,
      Interfaces.TopicAuditEntryData.self
    ],
    keyFields: nil
  )
}