// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public extension Interfaces {
  /// Represents a subject that can be reacted on.
  static let Reactable = ApolloAPI.Interface(
    name: "Reactable",
    keyFields: nil,
    implementingObjects: [
      "CommitComment",
      "Issue",
      "IssueComment",
      "PullRequest",
      "PullRequestReview",
      "PullRequestReviewComment",
      "TeamDiscussion",
      "TeamDiscussionComment"
    ]
  )
}