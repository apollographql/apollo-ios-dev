# `@cacheControl` Examples

## Scalar Samples

For scalar types, fields should always inherit from their parent type. However, you can override the parent value at the field level for individual fields. 

### Example 1

In this example, `@cacheControl` is applied to the `Author` type. All fields within the `Author` type are scalars, so they will automatically inherit the max age of 3600 from the `Author` type.

```graphql
type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}
```

### Example 2

In this example, `@cacheControl` is applied to the `Author` type. All fields within the `Author` type are scalars, so they will automatically inherit the max age of 3600 from the `Author` type. However, the `bookCount` field overrides this and gets a `maxAge` of 300.

```graphql
type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int! `@cacheControl`(maxAge: 300)
}
```

### Example 3

In this example only the `bookCount` field has a `maxAge` applied, the `Author` type and all other fields within the type will receive the default max age value.

```graphql
type Author {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int! `@cacheControl`(maxAge: 300)
}
```

## Composite Type Examples

### Example 1

In this example the `author` field on `Book` has a `maxAge` of 3600 which is set on the `Author` type.

```graphql
type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book {
  id: ID!
  title: String!
  author: Author! # This field uses the max age from the Author type above
}
```

### Example 2

In this example the `Author` type has a `maxAge` of 3600, however the `author` field on `Book` overrides this with a `maxAge` of 600.

```graphql
type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book {
  id: ID!
  title: String!
  author: Author! `@cacheControl`(maxAge: 600)
}
```

### Example 3

In this example no `maxAge` is set for the `Author` type, the `author` field on `Book` is setting its `maxAge` to 600.

```graphql
type Author {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book {
  id: ID!
  title: String!
  author: Author! `@cacheControl`(maxAge: 600)
}
```

### Example 4

In this example there is no `maxAge` set on the `Author` type so it would have a default `maxAge` of 0. It does not automatically inherit from the `Book` type.

```graphql
type Author {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book `@cacheControl`(maxAge: 3600) {
  id: ID!
  title: String!
  author: Author!
}
```

### Example 5

In this example the `inheritMaxAge` is used on the `author` field of the `Book` type so that it inherits the `maxAge` of `Book` instead of using the value set on the `Author` type.

```graphql
type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book `@cacheControl`(maxAge: 1800) {
  id: ID!
  title: String!
  author: Author! `@cacheControl`(inheritMaxAge: true) #uses 1800 instead of 3600
}
```

### Example 6

In this example `inheritMaxAge` is applied to the `Author` type, so by default it has a `maxAge` of 0, but since `Book` has a `maxAge` of 1800 that is inherited by the `Author` type.

```graphql
type Author `@cacheControl`(inheritMaxAge: true) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
}

type Book `@cacheControl`(maxAge: 1800) {
  id: ID!
  title: String!
  author: Author! # uses 1800 because of inheritMaxAge on Author
}
```

## Operation Override Examples

Example 1

This example shows how you can override `maxAge` values at the operation level.

```
# Schema

type Query {
  authors: [Author!]!
}

type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int!
  books: [Book!]!
}

type Book {
  id: ID!
}

# Operations

query GetAuthorsWithBooks {
  authors { # 3600 - Because it's of type Author which has maxAge 3600
    id # 3600 - Because it's a scalar so inherits its parent field's maxAge
    bookCount `@cacheControl`(maxAge: 60) # 60 - Because it's overridden here in the operationSample
    books { # 0 - Default value, because no maxAge specified on Book
            # and it's not scalar so doesn't inherit its parent's maxAge
      id # 0 - Because it's a scalar so inherits its parent field's maxAge
    }
  }
}
```

## Schema and Operation Examples

### Example 1

```graphql
# Schema

type Query {
  authors: [Author!]!
}

type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int! `@cacheControl`(maxAge: 60)
  books: [Book!]!
}

type Book {
  id: ID!
}

# Operations

query GetAuthorsWithBooks {
  authors { # 3600 - Because it's of type Author which has maxAge 3600
    id # 3600 - Because it's a scalar so inherits its parent field's maxAge
    bookCount # 60 - Because it's specified on Author.bookCount
    books { # 0 - Default value, because no maxAge specified on Book
            # and it's not scalar so doesn't inherit its parent's maxAge
      id # 0 - Because it's a scalar so inherits its parent field's maxAge
    }
  }
}
```

### Example 2

```graphql
# Schema

type Query {
  authors: [Author!]!
}

type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int! `@cacheControl`(maxAge: 60)
  books: [Book!]!
}

type Book `@cacheControl`(maxAge: 1800) {
  id: ID!
}

# Operations

query GetAuthorsWithBooks {
  authors { # 3600 - Because it's of type Author which has maxAge 3600
    id # 3600 - Because it's a scalar so inherits its parent field's maxAge
    bookCount # 60 - Because it's specified on Author.bookCount
    books { # 1800 - Because it is specified on the Book type
      id # 1800 - Because it's a scalar so inherits its parent field's maxAge
    }
  }
}
```

### Example 3

```graphql
# Schema

type Query {
  authors: [Author!]!
}

type Author `@cacheControl`(maxAge: 3600) {
  id: ID!
  firstName: String!
  lastName: String!
  bookCount: Int! `@cacheControl`(maxAge: 60)
  books: [Book!]! `@cacheControl`(maxAge: 900)
}

type Book `@cacheControl`(maxAge: 1800) {
  id: ID!
}

# Operations

query GetAuthorsWithBooks {
  authors { # 3600 - Because it's of type Author which has maxAge 3600
    id # 3600 - Because it's a scalar so inherits its parent field's maxAge
    bookCount # 60 - Because it's specified on Author.bookCount
    books { # 900 - Because Author.books is overriding the maxAge specified on the Book type
      id # 900 - Because it's a scalar so inherits its parent field's maxAge
    }
  }
}
```

### Example with an interface

```graphql
# Schema

type Query {
  auth: Auth
}

interface Sensitive `@cacheControl`(maxAge: 5) {
  id: ID!
}

type Auth implements Sensitive {
  id: ID!
  password: String
}

# Operations

query GetAuthorsWithBooks {
  auth { # 5 - Because it's of type Author which implements Sensitive which
         # has maxAge 5
    password # 5 - Because it's a scalar so inherits its parent field's maxAge
  }
}
```
