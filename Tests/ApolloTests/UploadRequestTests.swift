import ApolloInternalTestHelpers
import Nimble
import UploadAPI
import XCTest

@testable import Apollo

class UploadRequestTests: XCTestCase {

  func testSingleFileWithUploadRequest() throws {
    let alphaFileUrl = TestFileHelper.fileURLForFile(named: "a", extension: "txt")

    let alphaFile = try GraphQLFile(
      fieldName: "file",
      originalName: "a.txt",
      mimeType: "text/plain",
      fileURL: alphaFileUrl
    )
    let operation = UploadOneFileMutation(file: alphaFile.originalName)

    var uploadRequest = UploadRequest(
      operation: operation,
      graphQLEndpoint: TestURL.mockServer.url,
      files: [alphaFile],
      multipartBoundary: "TEST.BOUNDARY",
      writeResultsToCache: false
    )
    uploadRequest.additionalHeaders = ["headerKey": "headerValue"]

    let urlRequest = try uploadRequest.toURLRequest()
    XCTAssertEqual(urlRequest.allHTTPHeaderFields?["headerKey"], "headerValue")

    let formData = try uploadRequest.requestMultipartFormData()
    let actual = try formData.toTestString()

    let expectedString = """
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="operations"

      {"operationName":"UploadOneFile","query":"mutation UploadOneFile($file: Upload!) { singleUpload(file: $file) { __typename id path filename mimetype } }","variables":{"file":null}}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="map"

      {"0":["variables.file"]}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="0"; filename="a.txt"
      Content-Type: text/plain

      Alpha file content.

      --TEST.BOUNDARY--
      """
    expect(actual).to(equal(expectedString))
  }

  func testMultipleFilesWithUploadRequest() throws {
    let alphaFileURL = TestFileHelper.fileURLForFile(named: "a", extension: "txt")
    let alphaFile = try GraphQLFile(
      fieldName: "files",
      originalName: "a.txt",
      mimeType: "text/plain",
      fileURL: alphaFileURL
    )

    let betaFileURL = TestFileHelper.fileURLForFile(named: "b", extension: "txt")
    let betaFile = try GraphQLFile(
      fieldName: "files",
      originalName: "b.txt",
      mimeType: "text/plain",
      fileURL: betaFileURL
    )

    let files = [alphaFile, betaFile]
    let operation = UploadMultipleFilesToTheSameParameterMutation(files: files.map { $0.originalName })

    let uploadRequest = UploadRequest(
      operation: operation,
      graphQLEndpoint: TestURL.mockServer.url,
      files: [alphaFile, betaFile],
      multipartBoundary: "TEST.BOUNDARY",
      writeResultsToCache: false
    )

    let urlRequest = try uploadRequest.toURLRequest()

    let multipartData = try uploadRequest.requestMultipartFormData()
    let actual = try multipartData.toTestString()

    let expectedString = """
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="operations"

      {"operationName":"UploadMultipleFilesToTheSameParameter","query":"mutation UploadMultipleFilesToTheSameParameter($files: [Upload!]!) { multipleUpload(files: $files) { __typename id path filename mimetype } }","variables":{"files":[null,null]}}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="map"

      {"0":["variables.files.0"],"1":["variables.files.1"]}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="0"; filename="a.txt"
      Content-Type: text/plain

      Alpha file content.

      --TEST.BOUNDARY
      Content-Disposition: form-data; name="1"; filename="b.txt"
      Content-Type: text/plain

      Bravo file content.

      --TEST.BOUNDARY--
      """
    expect(actual).to(equal(expectedString))
  }

  func testMultipleFilesWithMultipleFieldsWithUploadRequest() throws {
    let alphaFileURL = TestFileHelper.fileURLForFile(named: "a", extension: "txt")
    let alphaFile = try GraphQLFile(
      fieldName: "uploads",
      originalName: "a.txt",
      mimeType: "text/plain",
      fileURL: alphaFileURL
    )

    let betaFileURL = TestFileHelper.fileURLForFile(named: "b", extension: "txt")
    let betaFile = try GraphQLFile(
      fieldName: "uploads",
      originalName: "b.txt",
      mimeType: "text/plain",
      fileURL: betaFileURL
    )

    let charlieFileUrl = TestFileHelper.fileURLForFile(named: "c", extension: "txt")
    let charlieFile = try GraphQLFile(
      fieldName: "secondField",
      originalName: "c.txt",
      mimeType: "text/plain",
      fileURL: charlieFileUrl
    )

    let operation = UploadMultipleFilesToDifferentParametersMutation(
      singleFile: alphaFile.originalName,
      multipleFiles: [betaFile, charlieFile].map { $0.originalName }
    )

    let uploadRequest = UploadRequest(
      operation: operation,
      graphQLEndpoint: TestURL.mockServer.url,
      files: [alphaFile, betaFile, charlieFile],
      multipartBoundary: "TEST.BOUNDARY",
      writeResultsToCache: false
    )        

    let urlRequest = try uploadRequest.toURLRequest()

    let multipartData = try uploadRequest.requestMultipartFormData()
    let actual = try multipartData.toTestString()

    let expectedString = """
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="operations"

      {"operationName":"UploadMultipleFilesToDifferentParameters","query":"mutation UploadMultipleFilesToDifferentParameters($singleFile: Upload!, $multipleFiles: [Upload!]!) { multipleParameterUpload(singleFile: $singleFile, multipleFiles: $multipleFiles) { __typename id path filename mimetype } }","variables":{"multipleFiles":["b.txt","c.txt"],"secondField":null,"singleFile":"a.txt","uploads":null}}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="map"

      {"0":["variables.secondField"],"1":["variables.uploads.0"],"2":["variables.uploads.1"]}
      --TEST.BOUNDARY
      Content-Disposition: form-data; name="0"; filename="c.txt"
      Content-Type: text/plain

      Charlie file content.

      --TEST.BOUNDARY
      Content-Disposition: form-data; name="1"; filename="a.txt"
      Content-Type: text/plain

      Alpha file content.

      --TEST.BOUNDARY
      Content-Disposition: form-data; name="2"; filename="b.txt"
      Content-Type: text/plain

      Bravo file content.

      --TEST.BOUNDARY--
      """
    expect(actual).to(equal(expectedString))
  }
}
