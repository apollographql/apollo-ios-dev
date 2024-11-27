# Summary

This document proposes a new GraphQL directive named `@apollo_client_ios_identity`, to be used to mark a field which can uniquely identify an object.

# Introduction

SwiftUI makes heavy use of the [Identifiable](https://developer.apple.com/documentation/swift/identifiable) protocol, which is used to track the identity of entities across data changes. If an object with a List is replaced with a different object with the same identity, SwiftUI will animate the item changing instead of animating an insertion. Objects that do not conform to the Identifiable protocol require additional boilerplate to be usable inside SwiftUI.

Apollo Client iOS could assist the developer by adding conformance to the Identifiable protocol to its generated models. Selecting the field to be used as an identity is done by adding a new GraphQL directive.

# Definition

The directive is defined as:
```graphql
directive @apollo_client_ios_identity on FIELD | FIELD_DEFINITION
```

This directive MUST be used on a field with a non-nullable scalar type. 

## Usage in types

A type MAY have a field annotated with the directive.

```graphql
type Animal {
	id: ID! @apollo_client_ios_identity
	name: String
}
```

Within a type, the directive MUST NOT be used on more than one field.

## Usage in interfaces

It's possible for interfaces to use the directive on a field.

```graphql
interface Identifiable {
	id: ID! @apollo_client_ios_identity
}
```

Implementations of this interface MUST copy the directive to the same field.

## Usage in operations

It's likely that an external schema will not use this directive. In this case, an identity MAY be chosen when writing a query. The directive does not need to be included in the query sent to the GraphQL server.

```graphql
query GetAllAnimals {
	allAnimals {
		id @apollo_client_ios_identity
		string
	}
}
```

It is allowed for a query and a type to both use the directive to describe the same field.

If the server defines a field as an identity, a query SHOULD NOT choose another field. A query MUST NOT use the directive on more than one field in the same selection (unless they are in differently nested objects).

## Generated code

If an operation contains a field marked with the `@apollo_client_ios_identity` directive (by either the schema or the operation itself), the generated SelectionSet will have a conformance to the Identifiable protocol.

```swift
// Inline selection
public struct Data: AnimalKingdomAPI.SelectionSet, Identifiable { /* ... */ }

// Fragment selection
public struct PetDetails: AnimalKingdomAPI.SelectionSet, Fragment, Identifiable { /* ... */ }
```

The protocol requires that the identity is accessible through a public field named exactly `id`. If the annotated field has a different name, an additional getter will be generated:

```swift
public var id: String { self.uuid }
```

## Naming conflicts

If the identity field is not called `id`, but another field called `id` is present in the selection, a custom getter cannot be added. Swift does not support using another field to handle the conformance.

In this case, a conformance to Identifiable SHOULD NOT be generated.

# Alternatives

## Automatic conformance to Identifiable

The code generator could be updated to always emit a conformance to Identifiable if a scalar `id` field is present in the selection set, removing the need for a custom directive. This was suggested in Pull Request [#548](https://github.com/apollographql/apollo-ios-dev/pull/548).

## Declaring identity scope

The directive could be expanded to declare the scope of an identity (e.g. unique across the entire API or only one specific Database table). This makes the directive beneficial outside of Swift code generation, but it doesn't change the behavior of the Identifiable protocol. The [Swift documentation](https://developer.apple.com/documentation/swift/identifiable) states that the scope and duration of an identity is unspecified, so modifying the scope would not lead to a difference in the generated code.
