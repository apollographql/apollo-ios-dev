
import Testing
import Foundation
import SwapiSchema
@_spi(Execution) import Apollo

struct CodableTests {
  @Test
  func testSimpleFragment() throws {
    let json = """
      {
        "__typename": "Film",
        "director": "George Lucas",
        "episodeID": 1
      }
      """.utf8Data
    
    let value = try JSONDecoder().decode(FilmFragment.self, from: json)
    let encoded = try JSONEncoder().encode(value)
    
    #expect(encoded.jsonString() == json.jsonString())
  }
  
  @Test
  func testSimpleFragment_failsWithBadData() throws {
    let json = """
      {
        "__typename": "Film",
        "director": "George Lucas"
      }
      """.utf8Data
    
    try expect({
      try JSONDecoder().decode(FilmFragment.self, from: json)
    }, toThrow: { error in
      guard let decodingError = error as? DecodingError else {
        throw error
      }
      switch decodingError {
      case .keyNotFound(let key, _):
        #expect(key.stringValue == "episodeID")
      default:
        throw decodingError
      }
    })
  }
  
  @Test
  func testComplexFragment_withSpecies() throws {
    let json = """
      {
        "__typename": "Species",
        "id": "123",
      }
      """.utf8Data
    
    let value = try JSONDecoder().decode(NodeFragment.self, from: json)
    let encoded = try JSONEncoder().encode(value)
    
    #expect(encoded.jsonString() == json.jsonString())
    #expect(value.id == "123")
    #expect(value.__typename == "Species")
    #expect(value.asPerson == nil)
    #expect(value.asPlanet == nil)
  }
  
  @Test
  func testComplexFragment_withPerson() throws {
//    let apolloClient = ApolloClient(url: URL(string: "http://localhost:4000/graphql")!)
//    apolloClient.fetch(query: TestQuery(after: .none, before: .none, first: .none, last: .none)) { result in
//      guard let data = try? result.get().data else { return }
//    }

    
    
    
    let json = """
      {
        "__typename": "Person",
        "id": "123",
        "name": "Luke",
        "goodOrBad": "GOOD",
        "homeworld": {
          "__typename": "Planet",
          "name": "Tatooine",
          "climates": [],
        },
        "nestedStringArray": [[["one", "two"], ["three", "four"]]],
        "nestedPlanetArray": [[[{ "__typename": "Planet", "name": "Tatouine" }], [{ "__typename": "Planet", "name": "Naboo" }]]],
      }
      """.utf8Data
    
    let dataEntry = try JSONSerialization.jsonObject(with: json, options: []) as! JSONObject
    
    let res = try GraphQLExecutor(executionSource: NetworkResponseExecutionSource()).execute(
          selectionSet: NodeFragment.self,
          on: dataEntry, // JSONObject
          withRootCacheReference: nil,
          variables: nil,
          accumulator: GraphQLSelectionSetMapper<NodeFragment>()
        )
    
    let homeworld: NodeFragment.AsPerson.Homeworld? = res.__data["homeworld"]
    let homeworld2: PersonOrPlanetInfo.AsPerson.Homeworld? = res.__data["homeworld"]
    
    let encodedData = try JSONEncoder().encode(res.__data)
    let encodedStr = encodedData.jsonString()
    
    let value = try JSONDecoder().decode(NodeFragment.self, from: json)
    let encoded = try JSONEncoder().encode(value)
    
    #expect(encoded.jsonString() == json.jsonString())
    #expect(value.id == "123")
    #expect(value.__typename == "Person")
    #expect(value.asPerson?.goodOrBad == .case(.good))
    
  }
  
  @Test
  func testComplexFragment_failsWithBadData() throws {
    let json = """
      {
        "__typename": "Film",
        "director": "George Lucas"
      }
      """.utf8Data
    
    try expect({
      try JSONDecoder().decode(NodeFragment.self, from: json)
    }, toThrow: { error in
      guard let decodingError = error as? DecodingError else {
        throw error
      }
      switch decodingError {
      case .keyNotFound(let key, _):
        #expect(key.stringValue == "episodeID")
      default:
        throw decodingError
      }
    })
  }
  
  private func expect<T>(_ operation: () throws -> T, toThrow: (Error) throws -> Void) throws {
    do {
      _ = try operation()
      Issue.record("Expected operation to throw an error, but it did not.")
    } catch {
      try toThrow(error)
    }
  }
    
}
