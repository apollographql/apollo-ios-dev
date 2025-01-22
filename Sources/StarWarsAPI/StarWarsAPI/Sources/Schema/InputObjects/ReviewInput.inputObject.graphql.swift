// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

/// The input object sent when someone is creating a new review
public struct ReviewInput: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    stars: Int,
    commentary: GraphQLNullable<String> = nil,
    favoriteColor: GraphQLNullable<ColorInput> = nil
  ) {
    __data = InputDict([
      "stars": stars,
      "commentary": commentary,
      "favorite_color": favoriteColor
    ])
  }

  /// 0-5 stars
  public var stars: Int {
    get { __data["stars"] }
    set { __data["stars"] = newValue }
  }

  /// Comment about the movie, optional
  public var commentary: GraphQLNullable<String> {
    get { __data["commentary"] }
    set { __data["commentary"] = newValue }
  }

  /// Favorite color, optional
  public var favoriteColor: GraphQLNullable<ColorInput> {
    get { __data["favorite_color"] }
    set { __data["favorite_color"] = newValue }
  }
}
