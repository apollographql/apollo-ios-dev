// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct IssuesAndCommentsForRepositoryQuery: GraphQLQuery {
  public static let operationName: String = "IssuesAndCommentsForRepository"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query IssuesAndCommentsForRepository { repository(name: "apollo-ios", owner: "apollographql") { __typename name issues(last: 100) { __typename nodes { __typename title author { __typename ...AuthorDetails } body comments(last: 100) { __typename nodes { __typename body author { __typename ...AuthorDetails } } } } } } }"#,
      fragments: [AuthorDetails.self]
    ))

  public init() {}

  public struct Data: GitHubAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("repository", Repository?.self, arguments: [
        "name": "apollo-ios",
        "owner": "apollographql"
      ]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      IssuesAndCommentsForRepositoryQuery.Data.self
    ] }

    /// Lookup a given repository by the owner and repository name.
    public var repository: Repository? { __data["repository"] }

    /// Repository
    ///
    /// Parent Type: `Repository`
    public struct Repository: GitHubAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.Repository }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .field("issues", Issues.self, arguments: ["last": 100]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        IssuesAndCommentsForRepositoryQuery.Data.Repository.self
      ] }

      /// The name of the repository.
      public var name: String { __data["name"] }
      /// A list of issues that have been opened in the repository.
      public var issues: Issues { __data["issues"] }

      /// Repository.Issues
      ///
      /// Parent Type: `IssueConnection`
      public struct Issues: GitHubAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.IssueConnection }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("nodes", [Node?]?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.self
        ] }

        /// A list of nodes.
        public var nodes: [Node?]? { __data["nodes"] }

        /// Repository.Issues.Node
        ///
        /// Parent Type: `Issue`
        public struct Node: GitHubAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.Issue }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("title", String.self),
            .field("author", Author?.self),
            .field("body", String.self),
            .field("comments", Comments.self, arguments: ["last": 100]),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.self
          ] }

          /// Identifies the issue title.
          public var title: String { __data["title"] }
          /// The actor who authored the comment.
          public var author: Author? { __data["author"] }
          /// Identifies the body of the issue.
          public var body: String { __data["body"] }
          /// A list of comments associated with the Issue.
          public var comments: Comments { __data["comments"] }

          /// Repository.Issues.Node.Author
          ///
          /// Parent Type: `Actor`
          public struct Author: GitHubAPI.SelectionSet {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Interfaces.Actor }
            @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .fragment(AuthorDetails.self),
            ] }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Author.self,
              AuthorDetails.self
            ] }

            /// The username of the actor.
            public var login: String { __data["login"] }

            public var asUser: AsUser? { _asInlineFragment() }

            public struct Fragments: FragmentContainer {
              @_spi(Unsafe) public let __data: DataDict
              @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

              public var authorDetails: AuthorDetails { _toFragment() }
            }

            /// Repository.Issues.Node.Author.AsUser
            ///
            /// Parent Type: `User`
            public struct AsUser: GitHubAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
              @_spi(Unsafe) public let __data: DataDict
              @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

              public typealias RootEntityType = IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Author
              @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.User }
              @_spi(Execution) public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
                IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Author.self,
                AuthorDetails.self,
                AuthorDetails.AsUser.self
              ] }
              @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
                IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Author.self,
                IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Author.AsUser.self,
                AuthorDetails.self,
                AuthorDetails.AsUser.self
              ] }

              /// The username of the actor.
              public var login: String { __data["login"] }
              public var id: GitHubAPI.ID { __data["id"] }
              /// The user's public profile name.
              public var name: String? { __data["name"] }

              public struct Fragments: FragmentContainer {
                @_spi(Unsafe) public let __data: DataDict
                @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

                public var authorDetails: AuthorDetails { _toFragment() }
              }
            }
          }

          /// Repository.Issues.Node.Comments
          ///
          /// Parent Type: `IssueCommentConnection`
          public struct Comments: GitHubAPI.SelectionSet {
            @_spi(Unsafe) public let __data: DataDict
            @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

            @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.IssueCommentConnection }
            @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("nodes", [Node?]?.self),
            ] }
            @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.self
            ] }

            /// A list of nodes.
            public var nodes: [Node?]? { __data["nodes"] }

            /// Repository.Issues.Node.Comments.Node
            ///
            /// Parent Type: `IssueComment`
            public struct Node: GitHubAPI.SelectionSet {
              @_spi(Unsafe) public let __data: DataDict
              @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

              @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.IssueComment }
              @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
                .field("__typename", String.self),
                .field("body", String.self),
                .field("author", Author?.self),
              ] }
              @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
                IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.self
              ] }

              /// The body as Markdown.
              public var body: String { __data["body"] }
              /// The actor who authored the comment.
              public var author: Author? { __data["author"] }

              /// Repository.Issues.Node.Comments.Node.Author
              ///
              /// Parent Type: `Actor`
              public struct Author: GitHubAPI.SelectionSet {
                @_spi(Unsafe) public let __data: DataDict
                @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

                @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Interfaces.Actor }
                @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
                  .field("__typename", String.self),
                  .fragment(AuthorDetails.self),
                ] }
                @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
                  IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.Author.self,
                  AuthorDetails.self
                ] }

                /// The username of the actor.
                public var login: String { __data["login"] }

                public var asUser: AsUser? { _asInlineFragment() }

                public struct Fragments: FragmentContainer {
                  @_spi(Unsafe) public let __data: DataDict
                  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

                  public var authorDetails: AuthorDetails { _toFragment() }
                }

                /// Repository.Issues.Node.Comments.Node.Author.AsUser
                ///
                /// Parent Type: `User`
                public struct AsUser: GitHubAPI.InlineFragment, ApolloAPI.CompositeInlineFragment {
                  @_spi(Unsafe) public let __data: DataDict
                  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

                  public typealias RootEntityType = IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.Author
                  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { GitHubAPI.Objects.User }
                  @_spi(Execution) public static var __mergedSources: [any ApolloAPI.SelectionSet.Type] { [
                    IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.Author.self,
                    AuthorDetails.self,
                    AuthorDetails.AsUser.self
                  ] }
                  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
                    IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.Author.self,
                    IssuesAndCommentsForRepositoryQuery.Data.Repository.Issues.Node.Comments.Node.Author.AsUser.self,
                    AuthorDetails.self,
                    AuthorDetails.AsUser.self
                  ] }

                  /// The username of the actor.
                  public var login: String { __data["login"] }
                  public var id: GitHubAPI.ID { __data["id"] }
                  /// The user's public profile name.
                  public var name: String? { __data["name"] }

                  public struct Fragments: FragmentContainer {
                    @_spi(Unsafe) public let __data: DataDict
                    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

                    public var authorDetails: AuthorDetails { _toFragment() }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
