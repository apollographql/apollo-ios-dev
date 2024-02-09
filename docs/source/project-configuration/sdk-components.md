# Apollo iOS SDK components

> **For Cocoapods users:**
>
> Cocoapods combines subspecs into a single target. This means that:
> - The [`ApolloAPI`](#apolloapi) is merged into the [`Apollo`](#apollo) target.
> - If you use the [`ApolloSQLite`](#apollosqlite) and [`ApolloWebSocket`](#apollowebsocket) subspecs, they are also merged into the `Apollo` target.

Libraries that compose the Apollo iOS package:

<table class="api-ref">
  <thead>
    <tr>
      <th>Description</th>
      <th>Usage</th>
    </tr>
  </thead>

<tbody>
<tr>
<td colspan="2">

#### `Apollo`

</td>
</tr>

<tr>
<td>

The core Apollo client library.

Includes the networking and caching APIs, including `ApolloClient` and `ApolloStore`.

</td>
<td>

Any targets that need to access these core components directly should be linked against `Apollo`.

</td>
</tr>
<tr>
<td colspan="2">

#### `ApolloAPI`

</td>
</tr>

<tr>
<td>

Includes the common components that generated models use for your project.

</td>
<td>

Any targets that include your generated models should be linked to `ApolloAPI`.

The `Apollo` library has a dependency on this target, so any target that links to `Apollo` doesn't need to link to  `ApolloAPI` directly.

Because generated models export the `ApolloAPI` library's interface, targets that consume generated models but don't _contain_ them don't need to link to `ApolloAPI` directly.

</td>
</tr>

<tr>
<td colspan="2">

#### `ApolloSQLite`

</td>
</tr>

<tr>
<td>

Provides a `NormalizedCache` implementation backed by a `SQLite` database.

</td>
<td>

Use this library if you'd like to persist cache data across application lifecycles. This library only needs to be linked to your targets that configure the `SQLiteNormalizedCache` and pass it to the `ApolloStore`.

For more information on setting up a persistent SQLite cache, see[`SQLiteNormalizedCache`](./caching/cache-setup#sqlitenormalizedcache).

</td>
</tr>

<tr>
<td colspan="2">

#### `ApolloWebSocket`

</td>
</tr>

<tr>
<td>

Provides a web socket transport implementation that supports `GraphQLSubscription` operations.

</td>
<td>

If your project uses GraphQL subscriptions, you **must** include this library. This library only needs to be linked to your targets that configure the `WebSocketTransport` and pass it to the `ApolloClient`.

For more information, see [Enabling GraphQL subscription support](./fetching/subscriptions#enabling-graphql-subscription-support).

</td>
</tr>

<tr>
<td colspan="2">

#### `ApolloTestSupport`

</td>
</tr>

<tr>
<td>

Includes the APIs for creating test mocks for your generated models

</td>
<td>

Link this library to *unit test targets* that need to create mocks of generated models.

</td>
</tr>

<tr>
<td colspan="2">

#### `ApolloCodegenLib`

</td>
</tr>

<tr>
<td>

Includes the code generation engine for generating GraphQL models.

For most projects, **we strongly recommend using the Codegen CLI** instead of using `ApolloCodegenLib` directly.

</td>
<td>

Use this library if you want to run the code generation engine from your own Swift executable targets.

Link this library to development tools that want to use the Apollo code generation engine. This library only supports macOS.

**`ApolloCodegenLib` shouldn't be linked to your application targets.**

</td>
</tr>

</tbody>
</table>
