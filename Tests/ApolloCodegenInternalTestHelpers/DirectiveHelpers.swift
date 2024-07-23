import Foundation

extension String {
  // This function will only be needed until @defer is merged into the GraphQL spec and is
  // considered a first-class directive in graphql-js. Right now it is a valid directive but must
  // be 'enabled' through explicit declaration in the schema.
  public func appendingDeferDirective() -> String {
    guard !contains("directive @defer") else { return self }

    return appending("""
    
    directive @defer(label: String, if: Boolean! = true) on FRAGMENT_SPREAD | INLINE_FRAGMENT
    """)
  }
}
