// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Interfaces {
  /// Metadata for an audit entry with action oauth_application.*
  static let OauthApplicationAuditEntryData = ApolloAPI.Interface(
    name: "OauthApplicationAuditEntryData",
    keyFields: nil,
    implementingObjects: [
      "OauthApplicationCreateAuditEntry",
      "OrgOauthAppAccessApprovedAuditEntry",
      "OrgOauthAppAccessDeniedAuditEntry",
      "OrgOauthAppAccessRequestedAuditEntry"
    ]
  )
}