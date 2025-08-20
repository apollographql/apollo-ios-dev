// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

public struct UploadMultipleFilesToDifferentParametersMutation: GraphQLMutation {
  public static let operationName: String = "UploadMultipleFilesToDifferentParameters"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation UploadMultipleFilesToDifferentParameters($singleFile: Upload!, $multipleFiles: [Upload!]!) { multipleParameterUpload(singleFile: $singleFile, multipleFiles: $multipleFiles) { __typename id path filename mimetype } }"#
    ))

  public var singleFile: Upload
  public var multipleFiles: [Upload]

  public init(
    singleFile: Upload,
    multipleFiles: [Upload]
  ) {
    self.singleFile = singleFile
    self.multipleFiles = multipleFiles
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "singleFile": singleFile,
    "multipleFiles": multipleFiles
  ] }

  public struct Data: UploadAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { UploadAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("multipleParameterUpload", [MultipleParameterUpload].self, arguments: [
        "singleFile": .variable("singleFile"),
        "multipleFiles": .variable("multipleFiles")
      ]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      UploadMultipleFilesToDifferentParametersMutation.Data.self
    ] }

    public var multipleParameterUpload: [MultipleParameterUpload] { __data["multipleParameterUpload"] }

    /// MultipleParameterUpload
    ///
    /// Parent Type: `File`
    public struct MultipleParameterUpload: UploadAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { UploadAPI.Objects.File }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", UploadAPI.ID.self),
        .field("path", String.self),
        .field("filename", String.self),
        .field("mimetype", String.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        UploadMultipleFilesToDifferentParametersMutation.Data.MultipleParameterUpload.self
      ] }

      public var id: UploadAPI.ID { __data["id"] }
      public var path: String { __data["path"] }
      public var filename: String { __data["filename"] }
      public var mimetype: String { __data["mimetype"] }
    }
  }
}
