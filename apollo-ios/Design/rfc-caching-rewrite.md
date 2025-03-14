###  **This RFC is a work in progress. Additions and changes will be made throughout the design process. Changes will be accompanied by a comment indicating what sections have changed.**

 # Background

 In order to provide a better caching experience and more functionality, the existing caching APIs need a significant overhaul. We believe everything from cache configuration and management, to the structure of the SQLite database can be improved to provide users with a better more powerful caching experience. This overhaul will involve breaking changes and will be released as a major version bump when complete.

 The features outlined in this RFC are considered core features for the initial release of the new caching system. While there are other features on the roadmap for caching they will come as future updates after the initial release of the core features. Some of those features include:

 - Object and Field watchers
 - Faceted searching support

 # Proposal

 While there are other features we want to eventually provide as well, the initial release of the new caching system will focus on the following features (described in more detail below). Restructuring the SQLite database will open up the ability to query and operate on individual fields. Configuring size limits on your caches to handle auto cache eviction, as well as configuring _what_ should/shouldn't be evicted. Along with being able to set Time to Live (TTL) on a per object or per field basis, enabled by the new SQLite structure.

 ## SQLite Structure

 The current SQLite structure stores your data as a cache key and a JSON blob of the response data from your query. This makes it difficult to operate on the data without having to pull the JSON out of the SQLite and then deserialize it. With the new caching system we will be storing data in the SQLite so that each row represents a single field of an object. This will allow us to be able to implement many features which currently either wouldn't be possible, or would be very complex to implement and have poor performance implications.

 ## Time to Live (TTL)

 To help control when data becomes "stale" we will introduce the ability to configure a TTL for an entire object or an individual field. This means that when accessing data from the cache, if any part of an object has surpassed its TTL it will cause a cache miss and the object will need to be re-fetched from the server. This will be configured through your schema and operations using a local directive, and allow the flexibility to set overall TTL's at the schema level but override them at an operation level if needed.

 ### Directive

 We will create a new local directive `@cacheControl(maxAge: Int)`, where the `maxAge` is measured in seconds, which can be applied to objects and fields in your schema or operations:

 ```graphql
 type Song @cacheControl(maxAge: 3600) {
  id: ID!
  name: String!
  description: String! @cacheControl(maxAge: 900)
  artist: Artist!
 }

 type Artist @cacheControl(maxAge: 3600) {
  id: ID!
  name: String!
  genre: String!
 }
 ```

 ```graphql
 query GetSong($id: ID!) {
  getSong(id: $id) {
    id
    name
    description @cacheControl(maxAge: 300)
    artist @cacheControl(maxAge: 900) {
      id
      name 
    }
  }
 }
 ```

 Using the above example schema/operation, you can see how you would apply TTL to objects and fields in the schema. However, you can also override TTL for objects/fields in individual operations if a particular operation has a different requirement for how fresh its data should be. When generating the code TTL will be tied to individual fields, so applying to an object applies to all of its fields. However, the most specific TTL will take precedence, with specificity in order of least to most being `Schema Type > Schema Field > Operation Type > Operation Field`, so in the example above for the song `description` field, it would get its TTL applied as follows:

- `Song` schema type TTL of 60 minutes applies
- `description` schema type field overrides the previous TTL of 60 and sets it to 15 minutes
- `description` query field overrides the schema field TTL and sets it to 5 minutes

So for the `GetSong` query, the `description` field would have a TTL of 5 minutes, but any other query using the `description` field would have a TTL of 15 minutes (unless you override it there as well). The same logic would apply to nested objects/fields such as the artist in the `GetSong` query above. In the generated code, fields at the `SelectionSet` level would have a static metadata TTL property so that the final value is available for use when querying the cache for data.

 ## Cache Configuration

 We want to provide more control over the caches to allow for better cache management, this includes the ability to set size limits for both the in-memory and SQLite caches which can be used to trigger automatic cache eviction. As well as being able to configure what get evicted, and specifying whether object deletion should cascade to child objects. Providing configuration to a `NormalizedCache` will be done through providing it with a `NormalizedCacheConfiguration` struct that looks like this:

 ```swift
 public struct NormalizedCacheConfiguration {
  let sizeLimit: Int
  let autoEvictionSize: Int
  let evictionFieldsIgnoreList: [Field]
  let delegate: NormalizedCacheConfigurationDelegate 
 }
 ```

 These properties and how they function will be described in more detail below.

 ### Cache Size Limits

 Configuring cache size limits will be done using the `sizeLimit` property of the `NormalizedCacheConfiguration` and will represent the maximum size in kilobytes (KB) you wish the cache to be before evicting some data to free up space.

 For the Apollo provided `InMemoryNormalizedCache` the size will be actively monitored with every new write to the cache, and if the size limit has been exceeded an overflow will be triggered.

 For the Apollo provided `SQLiteNormalizedCache` the size will be monitored more passively at set time intervals, and the same as the in memory cache if the size limit is exceeded and overflow will be triggered.

 ### Eviction Configuration

 By default the automatic eviction done from the caches will be handled as a least recently used (LRU) style cache. However, by using the `evictionFieldsIgnoreList` property on the `NormalizedCacheConfiguration` you will be able to provide an array of `Field` objects representing fields from any of your types you wish to not have evicted for any reason, such as it being long lived data that is unlikely to change.

 ### Cache Overflow Handling

 When an overflow of a cache is detected because it has exceeded its size limit, before any eviction takes place a call will be made to the `delegate` of the `NormalizedCacheConfiguration` to provide an opportunity to do or complete any work you feel is necessary before cache eviction takes place. You can also choose to skip the eviction, until the next check when an overflow is detected and triggered again. The `NormalizedCacheConfigurationDelegate` will look something like:

 ```swift
 public protocol NormalizedCacheConfigurationDelegate {
  func willRunCacheEviction() -> Bool
 }
 ```

 When this delegate function returns `true` cache eviction will take place following any configuration provided until the cache has a set amount of KB available based on what you provide with the `autoEvictionSize` in your `NormalizedCacheConfiguration`.

 ### Cascading Deletions

 By default when an object is delete from a cache if there are any child objects within it they will not be deleted. Cascading deletions is the idea child objects would be deleted along with the object referencing them. In order to support this there will be a parameter available on the `@cacheControl(...)` directive referenced above in the TTL sections which allows you to mark child objects for deletions in your schema. As an example given the following schema types:

 ```graphql
 type Song {
  id: ID!
  name: String!
  description: String!
  artist: Artist!
 }

 type Artist {
  id: ID!
  name: String!
  genre: String!
 }
 ```

 When deleting a `Song` from the cache, the referenced `Artist` object would not be automatically deleted unless you mark it for deletion using the directive described below.

 ### Directive

 As part of the `@cacheControl(...)` directive you will be able to mark child objects for deletion by marking them with `@cacheControl(cascadeDeletion: true)`. The below example shows how this would look in your schema, along with an example of marking an object for deletion while also setting its TTL:

 ```graphql
 type Song @cacheControl(maxAge: 3600) {
  id: ID!
  name: String!
  description: String!
  artist: Artist! @cacheControl(maxAge: 900, cascadeDeletion: true)
 }

 type Artist {
  id: ID!
  name: String!
  genre: String!
 }
 ```

 ### Other options

 We have considered an implementation of cascading deletions where a heuristic is used to determine relationships between objects, which would detect parent/child object relationships and having the default behavior be to always delete child objects with parent objects. Currently we don't plan to move forward with this implementation.

 ## Cache Chaining

 Cache chaining will handle writing to an `InMemoryNormalizedCache` and then subequently writing to the `SQLiteNormalizedCache` automatically for you. In order to handle this there will be a new `NormalizedCache` implementation `ChainedNormalizedCache` which will use both the in memory and SQLite cache and handle chaining for you. By default all data will chain to both caches, however you will be able to exclude object types from either the in memory or SQLite cache so they are only stored in one or the other if desired. That configuration will look like this:

 ```swift
 public final class ChainedNormalizedCache: NormalizedCache {
  private let inMemoryCache: InMemoryNormalizedCache
  private let sqliteCache: SQLiteNormalizedCache

  private let inMemoryExcludeList: [Object]
  private let sqliteExcludeList: [Object]

  init(
    inMemoryCache: InMemoryNormalizedCache,
    sqliteCache: SQLiteNormalizedCache,
    inMemoryExcludeList: [Object] = [],
    sqliteExcludeList: [Object] = []
  ) {
    ...
  }

  ...
 }
 ```