// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class TestComplexQuery: GraphQLQuery {
  public static let operationName: String = "TestComplexQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query TestComplexQuery($after: String, $before: String, $first: Int, $last: Int) { allFilms(after: $after, before: $before, first: $first, last: $last) { __typename films { __typename ...FilmFragment } } }"#,
      fragments: [FilmFragment.self]
    ))

  public var after: GraphQLNullable<String>
  public var before: GraphQLNullable<String>
  public var first: GraphQLNullable<Int>
  public var last: GraphQLNullable<Int>

  public init(
    after: GraphQLNullable<String>,
    before: GraphQLNullable<String>,
    first: GraphQLNullable<Int>,
    last: GraphQLNullable<Int>
  ) {
    self.after = after
    self.before = before
    self.first = first
    self.last = last
  }

  public var __variables: Variables? { [
    "after": after,
    "before": before,
    "first": first,
    "last": last
  ] }

  public struct Data: SwapiSchema.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }
    public static func validate(value: Self?) throws {
      guard let value else { throw ValidationError.dataIsNil }
      try value.validate(AllFilms?.self, for: "allFilms")
    }
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: String.self)
      __data = DataDict(data: [
        "__typename": try container.decode(String.self, forKey: "__typename"),
        "allFilms": try container.decode(AllFilms?.self, forKey: "allFilms")
      ], fulfilledFragments: [
      ])
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: String.self)
      try container.encode(__typename, forKey: "__typename")
      try container.encode(allFilms, forKey: "allFilms")
    }

    public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Root }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("allFilms", AllFilms?.self, arguments: [
        "after": .variable("after"),
        "before": .variable("before"),
        "first": .variable("first"),
        "last": .variable("last")
      ]),
    ] }

    public var allFilms: AllFilms? { __data["allFilms"] }

    /// AllFilms
    ///
    /// Parent Type: `FilmsConnection`
    public struct AllFilms: SwapiSchema.SelectionSet, Validatable, Codable {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }
      public static func validate(value: Self?) throws {
        guard let value else { throw ValidationError.dataIsNil }
        try value.validate([Film?]?.self, for: "films")
      }
      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: String.self)
        __data = DataDict(data: [
          "__typename": try container.decode(String.self, forKey: "__typename"),
          "films": try container.decode([Film?]?.self, forKey: "films")
        ], fulfilledFragments: [
        ])
      }

      public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: String.self)
        try container.encode(__typename, forKey: "__typename")
        try container.encode(films, forKey: "films")
      }

      public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.FilmsConnection }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("films", [Film?]?.self),
      ] }

      /// A list of all of the objects returned in the connection. This is a convenience
      /// field provided for quickly exploring the API; rather than querying for
      /// "{ edges { node } }" when no edge data is needed, this field can be be used
      /// instead. Note that when clients like Relay need to fetch the "cursor" field on
      /// the edge to enable efficient pagination, this shortcut cannot be used, and the
      /// full "{ edges { node } }" version should be used instead.
      public var films: [Film?]? { __data["films"] }

      /// AllFilms.Film
      ///
      /// Parent Type: `Film`
      public struct Film: SwapiSchema.SelectionSet, Validatable, Codable {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }
        public static func validate(value: Self?) throws {
          guard let value else { throw ValidationError.dataIsNil }
          try value.validate(String?.self, for: "director")
          try value.validate(Int?.self, for: "episodeID")
        }
        public init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: String.self)
          __data = DataDict(data: [
            "__typename": try container.decode(String.self, forKey: "__typename"),
            "director": try container.decode(String?.self, forKey: "director"),
            "episodeID": try container.decode(Int?.self, forKey: "episodeID")
          ], fulfilledFragments: [
          ])
        }

        public func encode(to encoder: Encoder) throws {
          var container = encoder.container(keyedBy: String.self)
          try container.encode(__typename, forKey: "__typename")
          try container.encode(director, forKey: "director")
          try container.encode(episodeID, forKey: "episodeID")
        }

        public static var __parentType: any ApolloAPI.ParentType { SwapiSchema.Objects.Film }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(FilmFragment.self),
        ] }

        /// The name of the director of this film.
        public var director: String? { __data["director"] }
        /// The episode number of this film.
        public var episodeID: Int? { __data["episodeID"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var filmFragment: FilmFragment { _toFragment() }
        }
      }
    }
  }
}
