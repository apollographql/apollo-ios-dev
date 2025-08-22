// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct CreateReviewForEpisodeMutation: GraphQLMutation {
  public static let operationName: String = "CreateReviewForEpisode"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    operationIdentifier: "3edcd1f17839f43db021eccbe2ecd41ad7dcb1ba6cd4b7e9897afb4162e4c223",
    definition: .init(
      #"mutation CreateReviewForEpisode($episode: Episode!, $review: ReviewInput!) { createReview(episode: $episode, review: $review) { __typename stars commentary } }"#
    ))

  public var episode: GraphQLEnum<Episode>
  public var review: ReviewInput

  public init(
    episode: GraphQLEnum<Episode>,
    review: ReviewInput
  ) {
    self.episode = episode
    self.review = review
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "episode": episode,
    "review": review
  ] }

  public struct Data: StarWarsAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("createReview", CreateReview?.self, arguments: [
        "episode": .variable("episode"),
        "review": .variable("review")
      ]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      CreateReviewForEpisodeMutation.Data.self
    ] }

    public var createReview: CreateReview? { __data["createReview"] }

    public init(
      createReview: CreateReview? = nil
    ) {
      self.init(unsafelyWithData: [
        "__typename": StarWarsAPI.Objects.Mutation.typename,
        "createReview": createReview._fieldData,
      ])
    }

    /// CreateReview
    ///
    /// Parent Type: `Review`
    public struct CreateReview: StarWarsAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { StarWarsAPI.Objects.Review }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("stars", Int.self),
        .field("commentary", String?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CreateReviewForEpisodeMutation.Data.CreateReview.self
      ] }

      /// The number of stars this review gave, 1-5
      public var stars: Int { __data["stars"] }
      /// Comment about the movie
      public var commentary: String? { __data["commentary"] }

      public init(
        stars: Int,
        commentary: String? = nil
      ) {
        self.init(unsafelyWithData: [
          "__typename": StarWarsAPI.Objects.Review.typename,
          "stars": stars,
          "commentary": commentary,
        ])
      }
    }
  }
}
