// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Interfaces {
  /// Metadata for an audit entry with action repo.*
  static let RepositoryAuditEntryData = ApolloAPI.Interface(
    name: "RepositoryAuditEntryData",
    keyFields: nil,
    implementingObjects: [
      "OrgRestoreMemberMembershipRepositoryAuditEntryData",
      "PrivateRepositoryForkingDisableAuditEntry",
      "PrivateRepositoryForkingEnableAuditEntry",
      "RepoAccessAuditEntry",
      "RepoAddMemberAuditEntry",
      "RepoAddTopicAuditEntry",
      "RepoArchivedAuditEntry",
      "RepoChangeMergeSettingAuditEntry",
      "RepoConfigDisableAnonymousGitAccessAuditEntry",
      "RepoConfigDisableCollaboratorsOnlyAuditEntry",
      "RepoConfigDisableContributorsOnlyAuditEntry",
      "RepoConfigDisableSockpuppetDisallowedAuditEntry",
      "RepoConfigEnableAnonymousGitAccessAuditEntry",
      "RepoConfigEnableCollaboratorsOnlyAuditEntry",
      "RepoConfigEnableContributorsOnlyAuditEntry",
      "RepoConfigEnableSockpuppetDisallowedAuditEntry",
      "RepoConfigLockAnonymousGitAccessAuditEntry",
      "RepoConfigUnlockAnonymousGitAccessAuditEntry",
      "RepoCreateAuditEntry",
      "RepoDestroyAuditEntry",
      "RepoRemoveMemberAuditEntry",
      "RepoRemoveTopicAuditEntry",
      "TeamAddRepositoryAuditEntry",
      "TeamRemoveRepositoryAuditEntry"
    ]
  )
}