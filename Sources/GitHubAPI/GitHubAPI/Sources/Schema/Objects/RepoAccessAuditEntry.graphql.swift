// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Objects {
  /// Audit log entry for a repo.access event.
  nonisolated static let RepoAccessAuditEntry = ApolloAPI.Object(
    typename: "RepoAccessAuditEntry",
    implementedInterfaces: [
      Interfaces.AuditEntry.self,
      Interfaces.Node.self,
      Interfaces.OrganizationAuditEntryData.self,
      Interfaces.RepositoryAuditEntryData.self
    ],
    keyFields: nil
  )
}