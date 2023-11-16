import XCTest
import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class GraphQLResultTests: XCTestCase {

  var server: MockGraphQLServer!
  var client: ApolloClient!
  
  override func setUpWithError() throws {
    try super.setUpWithError()
    
    let store = ApolloStore()
    
    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)
    
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDownWithError() throws {
    server = nil
    client = nil
    
    try super.tearDownWithError()
  }
  
  // TODO: Add tests

}
