// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == GitHubAPI.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == GitHubAPI.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == GitHubAPI.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == GitHubAPI.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "AddedToProjectEvent": return GitHubAPI.Objects.AddedToProjectEvent
    case "App": return GitHubAPI.Objects.App
    case "AssignedEvent": return GitHubAPI.Objects.AssignedEvent
    case "AutomaticBaseChangeFailedEvent": return GitHubAPI.Objects.AutomaticBaseChangeFailedEvent
    case "AutomaticBaseChangeSucceededEvent": return GitHubAPI.Objects.AutomaticBaseChangeSucceededEvent
    case "BaseRefChangedEvent": return GitHubAPI.Objects.BaseRefChangedEvent
    case "BaseRefForcePushedEvent": return GitHubAPI.Objects.BaseRefForcePushedEvent
    case "Blob": return GitHubAPI.Objects.Blob
    case "Bot": return GitHubAPI.Objects.Bot
    case "BranchProtectionRule": return GitHubAPI.Objects.BranchProtectionRule
    case "CheckRun": return GitHubAPI.Objects.CheckRun
    case "CheckSuite": return GitHubAPI.Objects.CheckSuite
    case "ClosedEvent": return GitHubAPI.Objects.ClosedEvent
    case "CodeOfConduct": return GitHubAPI.Objects.CodeOfConduct
    case "CommentDeletedEvent": return GitHubAPI.Objects.CommentDeletedEvent
    case "Commit": return GitHubAPI.Objects.Commit
    case "CommitComment": return GitHubAPI.Objects.CommitComment
    case "CommitCommentThread": return GitHubAPI.Objects.CommitCommentThread
    case "ConnectedEvent": return GitHubAPI.Objects.ConnectedEvent
    case "ConvertToDraftEvent": return GitHubAPI.Objects.ConvertToDraftEvent
    case "ConvertedNoteToIssueEvent": return GitHubAPI.Objects.ConvertedNoteToIssueEvent
    case "CrossReferencedEvent": return GitHubAPI.Objects.CrossReferencedEvent
    case "DemilestonedEvent": return GitHubAPI.Objects.DemilestonedEvent
    case "DependencyGraphManifest": return GitHubAPI.Objects.DependencyGraphManifest
    case "DeployKey": return GitHubAPI.Objects.DeployKey
    case "DeployedEvent": return GitHubAPI.Objects.DeployedEvent
    case "Deployment": return GitHubAPI.Objects.Deployment
    case "DeploymentEnvironmentChangedEvent": return GitHubAPI.Objects.DeploymentEnvironmentChangedEvent
    case "DeploymentStatus": return GitHubAPI.Objects.DeploymentStatus
    case "DisconnectedEvent": return GitHubAPI.Objects.DisconnectedEvent
    case "Enterprise": return GitHubAPI.Objects.Enterprise
    case "EnterpriseAdministratorInvitation": return GitHubAPI.Objects.EnterpriseAdministratorInvitation
    case "EnterpriseIdentityProvider": return GitHubAPI.Objects.EnterpriseIdentityProvider
    case "EnterpriseRepositoryInfo": return GitHubAPI.Objects.EnterpriseRepositoryInfo
    case "EnterpriseServerInstallation": return GitHubAPI.Objects.EnterpriseServerInstallation
    case "EnterpriseServerUserAccount": return GitHubAPI.Objects.EnterpriseServerUserAccount
    case "EnterpriseServerUserAccountEmail": return GitHubAPI.Objects.EnterpriseServerUserAccountEmail
    case "EnterpriseServerUserAccountsUpload": return GitHubAPI.Objects.EnterpriseServerUserAccountsUpload
    case "EnterpriseUserAccount": return GitHubAPI.Objects.EnterpriseUserAccount
    case "ExternalIdentity": return GitHubAPI.Objects.ExternalIdentity
    case "Gist": return GitHubAPI.Objects.Gist
    case "GistComment": return GitHubAPI.Objects.GistComment
    case "HeadRefDeletedEvent": return GitHubAPI.Objects.HeadRefDeletedEvent
    case "HeadRefForcePushedEvent": return GitHubAPI.Objects.HeadRefForcePushedEvent
    case "HeadRefRestoredEvent": return GitHubAPI.Objects.HeadRefRestoredEvent
    case "IpAllowListEntry": return GitHubAPI.Objects.IpAllowListEntry
    case "Issue": return GitHubAPI.Objects.Issue
    case "IssueComment": return GitHubAPI.Objects.IssueComment
    case "IssueCommentConnection": return GitHubAPI.Objects.IssueCommentConnection
    case "IssueConnection": return GitHubAPI.Objects.IssueConnection
    case "Label": return GitHubAPI.Objects.Label
    case "LabeledEvent": return GitHubAPI.Objects.LabeledEvent
    case "Language": return GitHubAPI.Objects.Language
    case "License": return GitHubAPI.Objects.License
    case "LockedEvent": return GitHubAPI.Objects.LockedEvent
    case "Mannequin": return GitHubAPI.Objects.Mannequin
    case "MarkedAsDuplicateEvent": return GitHubAPI.Objects.MarkedAsDuplicateEvent
    case "MarketplaceCategory": return GitHubAPI.Objects.MarketplaceCategory
    case "MarketplaceListing": return GitHubAPI.Objects.MarketplaceListing
    case "MembersCanDeleteReposClearAuditEntry": return GitHubAPI.Objects.MembersCanDeleteReposClearAuditEntry
    case "MembersCanDeleteReposDisableAuditEntry": return GitHubAPI.Objects.MembersCanDeleteReposDisableAuditEntry
    case "MembersCanDeleteReposEnableAuditEntry": return GitHubAPI.Objects.MembersCanDeleteReposEnableAuditEntry
    case "MentionedEvent": return GitHubAPI.Objects.MentionedEvent
    case "MergedEvent": return GitHubAPI.Objects.MergedEvent
    case "Milestone": return GitHubAPI.Objects.Milestone
    case "MilestonedEvent": return GitHubAPI.Objects.MilestonedEvent
    case "MovedColumnsInProjectEvent": return GitHubAPI.Objects.MovedColumnsInProjectEvent
    case "OauthApplicationCreateAuditEntry": return GitHubAPI.Objects.OauthApplicationCreateAuditEntry
    case "OrgAddBillingManagerAuditEntry": return GitHubAPI.Objects.OrgAddBillingManagerAuditEntry
    case "OrgAddMemberAuditEntry": return GitHubAPI.Objects.OrgAddMemberAuditEntry
    case "OrgBlockUserAuditEntry": return GitHubAPI.Objects.OrgBlockUserAuditEntry
    case "OrgConfigDisableCollaboratorsOnlyAuditEntry": return GitHubAPI.Objects.OrgConfigDisableCollaboratorsOnlyAuditEntry
    case "OrgConfigEnableCollaboratorsOnlyAuditEntry": return GitHubAPI.Objects.OrgConfigEnableCollaboratorsOnlyAuditEntry
    case "OrgCreateAuditEntry": return GitHubAPI.Objects.OrgCreateAuditEntry
    case "OrgDisableOauthAppRestrictionsAuditEntry": return GitHubAPI.Objects.OrgDisableOauthAppRestrictionsAuditEntry
    case "OrgDisableSamlAuditEntry": return GitHubAPI.Objects.OrgDisableSamlAuditEntry
    case "OrgDisableTwoFactorRequirementAuditEntry": return GitHubAPI.Objects.OrgDisableTwoFactorRequirementAuditEntry
    case "OrgEnableOauthAppRestrictionsAuditEntry": return GitHubAPI.Objects.OrgEnableOauthAppRestrictionsAuditEntry
    case "OrgEnableSamlAuditEntry": return GitHubAPI.Objects.OrgEnableSamlAuditEntry
    case "OrgEnableTwoFactorRequirementAuditEntry": return GitHubAPI.Objects.OrgEnableTwoFactorRequirementAuditEntry
    case "OrgInviteMemberAuditEntry": return GitHubAPI.Objects.OrgInviteMemberAuditEntry
    case "OrgInviteToBusinessAuditEntry": return GitHubAPI.Objects.OrgInviteToBusinessAuditEntry
    case "OrgOauthAppAccessApprovedAuditEntry": return GitHubAPI.Objects.OrgOauthAppAccessApprovedAuditEntry
    case "OrgOauthAppAccessDeniedAuditEntry": return GitHubAPI.Objects.OrgOauthAppAccessDeniedAuditEntry
    case "OrgOauthAppAccessRequestedAuditEntry": return GitHubAPI.Objects.OrgOauthAppAccessRequestedAuditEntry
    case "OrgRemoveBillingManagerAuditEntry": return GitHubAPI.Objects.OrgRemoveBillingManagerAuditEntry
    case "OrgRemoveMemberAuditEntry": return GitHubAPI.Objects.OrgRemoveMemberAuditEntry
    case "OrgRemoveOutsideCollaboratorAuditEntry": return GitHubAPI.Objects.OrgRemoveOutsideCollaboratorAuditEntry
    case "OrgRestoreMemberAuditEntry": return GitHubAPI.Objects.OrgRestoreMemberAuditEntry
    case "OrgRestoreMemberMembershipOrganizationAuditEntryData": return GitHubAPI.Objects.OrgRestoreMemberMembershipOrganizationAuditEntryData
    case "OrgRestoreMemberMembershipRepositoryAuditEntryData": return GitHubAPI.Objects.OrgRestoreMemberMembershipRepositoryAuditEntryData
    case "OrgRestoreMemberMembershipTeamAuditEntryData": return GitHubAPI.Objects.OrgRestoreMemberMembershipTeamAuditEntryData
    case "OrgUnblockUserAuditEntry": return GitHubAPI.Objects.OrgUnblockUserAuditEntry
    case "OrgUpdateDefaultRepositoryPermissionAuditEntry": return GitHubAPI.Objects.OrgUpdateDefaultRepositoryPermissionAuditEntry
    case "OrgUpdateMemberAuditEntry": return GitHubAPI.Objects.OrgUpdateMemberAuditEntry
    case "OrgUpdateMemberRepositoryCreationPermissionAuditEntry": return GitHubAPI.Objects.OrgUpdateMemberRepositoryCreationPermissionAuditEntry
    case "OrgUpdateMemberRepositoryInvitationPermissionAuditEntry": return GitHubAPI.Objects.OrgUpdateMemberRepositoryInvitationPermissionAuditEntry
    case "Organization": return GitHubAPI.Objects.Organization
    case "OrganizationIdentityProvider": return GitHubAPI.Objects.OrganizationIdentityProvider
    case "OrganizationInvitation": return GitHubAPI.Objects.OrganizationInvitation
    case "Package": return GitHubAPI.Objects.Package
    case "PackageFile": return GitHubAPI.Objects.PackageFile
    case "PackageTag": return GitHubAPI.Objects.PackageTag
    case "PackageVersion": return GitHubAPI.Objects.PackageVersion
    case "PinnedEvent": return GitHubAPI.Objects.PinnedEvent
    case "PinnedIssue": return GitHubAPI.Objects.PinnedIssue
    case "PrivateRepositoryForkingDisableAuditEntry": return GitHubAPI.Objects.PrivateRepositoryForkingDisableAuditEntry
    case "PrivateRepositoryForkingEnableAuditEntry": return GitHubAPI.Objects.PrivateRepositoryForkingEnableAuditEntry
    case "Project": return GitHubAPI.Objects.Project
    case "ProjectCard": return GitHubAPI.Objects.ProjectCard
    case "ProjectColumn": return GitHubAPI.Objects.ProjectColumn
    case "PublicKey": return GitHubAPI.Objects.PublicKey
    case "PullRequest": return GitHubAPI.Objects.PullRequest
    case "PullRequestCommit": return GitHubAPI.Objects.PullRequestCommit
    case "PullRequestCommitCommentThread": return GitHubAPI.Objects.PullRequestCommitCommentThread
    case "PullRequestReview": return GitHubAPI.Objects.PullRequestReview
    case "PullRequestReviewComment": return GitHubAPI.Objects.PullRequestReviewComment
    case "PullRequestReviewThread": return GitHubAPI.Objects.PullRequestReviewThread
    case "Push": return GitHubAPI.Objects.Push
    case "PushAllowance": return GitHubAPI.Objects.PushAllowance
    case "Query": return GitHubAPI.Objects.Query
    case "Reaction": return GitHubAPI.Objects.Reaction
    case "ReadyForReviewEvent": return GitHubAPI.Objects.ReadyForReviewEvent
    case "Ref": return GitHubAPI.Objects.Ref
    case "ReferencedEvent": return GitHubAPI.Objects.ReferencedEvent
    case "Release": return GitHubAPI.Objects.Release
    case "ReleaseAsset": return GitHubAPI.Objects.ReleaseAsset
    case "RemovedFromProjectEvent": return GitHubAPI.Objects.RemovedFromProjectEvent
    case "RenamedTitleEvent": return GitHubAPI.Objects.RenamedTitleEvent
    case "ReopenedEvent": return GitHubAPI.Objects.ReopenedEvent
    case "RepoAccessAuditEntry": return GitHubAPI.Objects.RepoAccessAuditEntry
    case "RepoAddMemberAuditEntry": return GitHubAPI.Objects.RepoAddMemberAuditEntry
    case "RepoAddTopicAuditEntry": return GitHubAPI.Objects.RepoAddTopicAuditEntry
    case "RepoArchivedAuditEntry": return GitHubAPI.Objects.RepoArchivedAuditEntry
    case "RepoChangeMergeSettingAuditEntry": return GitHubAPI.Objects.RepoChangeMergeSettingAuditEntry
    case "RepoConfigDisableAnonymousGitAccessAuditEntry": return GitHubAPI.Objects.RepoConfigDisableAnonymousGitAccessAuditEntry
    case "RepoConfigDisableCollaboratorsOnlyAuditEntry": return GitHubAPI.Objects.RepoConfigDisableCollaboratorsOnlyAuditEntry
    case "RepoConfigDisableContributorsOnlyAuditEntry": return GitHubAPI.Objects.RepoConfigDisableContributorsOnlyAuditEntry
    case "RepoConfigDisableSockpuppetDisallowedAuditEntry": return GitHubAPI.Objects.RepoConfigDisableSockpuppetDisallowedAuditEntry
    case "RepoConfigEnableAnonymousGitAccessAuditEntry": return GitHubAPI.Objects.RepoConfigEnableAnonymousGitAccessAuditEntry
    case "RepoConfigEnableCollaboratorsOnlyAuditEntry": return GitHubAPI.Objects.RepoConfigEnableCollaboratorsOnlyAuditEntry
    case "RepoConfigEnableContributorsOnlyAuditEntry": return GitHubAPI.Objects.RepoConfigEnableContributorsOnlyAuditEntry
    case "RepoConfigEnableSockpuppetDisallowedAuditEntry": return GitHubAPI.Objects.RepoConfigEnableSockpuppetDisallowedAuditEntry
    case "RepoConfigLockAnonymousGitAccessAuditEntry": return GitHubAPI.Objects.RepoConfigLockAnonymousGitAccessAuditEntry
    case "RepoConfigUnlockAnonymousGitAccessAuditEntry": return GitHubAPI.Objects.RepoConfigUnlockAnonymousGitAccessAuditEntry
    case "RepoCreateAuditEntry": return GitHubAPI.Objects.RepoCreateAuditEntry
    case "RepoDestroyAuditEntry": return GitHubAPI.Objects.RepoDestroyAuditEntry
    case "RepoRemoveMemberAuditEntry": return GitHubAPI.Objects.RepoRemoveMemberAuditEntry
    case "RepoRemoveTopicAuditEntry": return GitHubAPI.Objects.RepoRemoveTopicAuditEntry
    case "Repository": return GitHubAPI.Objects.Repository
    case "RepositoryInvitation": return GitHubAPI.Objects.RepositoryInvitation
    case "RepositoryTopic": return GitHubAPI.Objects.RepositoryTopic
    case "RepositoryVisibilityChangeDisableAuditEntry": return GitHubAPI.Objects.RepositoryVisibilityChangeDisableAuditEntry
    case "RepositoryVisibilityChangeEnableAuditEntry": return GitHubAPI.Objects.RepositoryVisibilityChangeEnableAuditEntry
    case "RepositoryVulnerabilityAlert": return GitHubAPI.Objects.RepositoryVulnerabilityAlert
    case "ReviewDismissalAllowance": return GitHubAPI.Objects.ReviewDismissalAllowance
    case "ReviewDismissedEvent": return GitHubAPI.Objects.ReviewDismissedEvent
    case "ReviewRequest": return GitHubAPI.Objects.ReviewRequest
    case "ReviewRequestRemovedEvent": return GitHubAPI.Objects.ReviewRequestRemovedEvent
    case "ReviewRequestedEvent": return GitHubAPI.Objects.ReviewRequestedEvent
    case "SavedReply": return GitHubAPI.Objects.SavedReply
    case "SecurityAdvisory": return GitHubAPI.Objects.SecurityAdvisory
    case "SponsorsListing": return GitHubAPI.Objects.SponsorsListing
    case "SponsorsTier": return GitHubAPI.Objects.SponsorsTier
    case "Sponsorship": return GitHubAPI.Objects.Sponsorship
    case "Status": return GitHubAPI.Objects.Status
    case "StatusCheckRollup": return GitHubAPI.Objects.StatusCheckRollup
    case "StatusContext": return GitHubAPI.Objects.StatusContext
    case "SubscribedEvent": return GitHubAPI.Objects.SubscribedEvent
    case "Tag": return GitHubAPI.Objects.Tag
    case "Team": return GitHubAPI.Objects.Team
    case "TeamAddMemberAuditEntry": return GitHubAPI.Objects.TeamAddMemberAuditEntry
    case "TeamAddRepositoryAuditEntry": return GitHubAPI.Objects.TeamAddRepositoryAuditEntry
    case "TeamChangeParentTeamAuditEntry": return GitHubAPI.Objects.TeamChangeParentTeamAuditEntry
    case "TeamDiscussion": return GitHubAPI.Objects.TeamDiscussion
    case "TeamDiscussionComment": return GitHubAPI.Objects.TeamDiscussionComment
    case "TeamRemoveMemberAuditEntry": return GitHubAPI.Objects.TeamRemoveMemberAuditEntry
    case "TeamRemoveRepositoryAuditEntry": return GitHubAPI.Objects.TeamRemoveRepositoryAuditEntry
    case "Topic": return GitHubAPI.Objects.Topic
    case "TransferredEvent": return GitHubAPI.Objects.TransferredEvent
    case "Tree": return GitHubAPI.Objects.Tree
    case "UnassignedEvent": return GitHubAPI.Objects.UnassignedEvent
    case "UnlabeledEvent": return GitHubAPI.Objects.UnlabeledEvent
    case "UnlockedEvent": return GitHubAPI.Objects.UnlockedEvent
    case "UnmarkedAsDuplicateEvent": return GitHubAPI.Objects.UnmarkedAsDuplicateEvent
    case "UnpinnedEvent": return GitHubAPI.Objects.UnpinnedEvent
    case "UnsubscribedEvent": return GitHubAPI.Objects.UnsubscribedEvent
    case "User": return GitHubAPI.Objects.User
    case "UserBlockedEvent": return GitHubAPI.Objects.UserBlockedEvent
    case "UserContentEdit": return GitHubAPI.Objects.UserContentEdit
    case "UserStatus": return GitHubAPI.Objects.UserStatus
    default: return nil
    }
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
