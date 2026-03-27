// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Objects {
  /// Audit log entry for a repo.remove_member event.
  nonisolated static let RepoRemoveMemberAuditEntry = ApolloAPI.Object(
    typename: "RepoRemoveMemberAuditEntry",
    implementedInterfaces: [
      Interfaces.AuditEntry.self,
      Interfaces.Node.self,
      Interfaces.OrganizationAuditEntryData.self,
      Interfaces.RepositoryAuditEntryData.self
    ],
    keyFields: nil
  )
}