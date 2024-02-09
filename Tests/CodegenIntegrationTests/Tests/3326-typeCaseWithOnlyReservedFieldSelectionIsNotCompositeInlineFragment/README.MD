# Overview

When a type case selection consisted of only GraphQL reserved fields, such as `__typename` the selection was not being recognized and a composite inline fragment was generated. This resulted in empty `__selections` and `__mergedSources` lists. This is turn caused the `_asInlineFragment` accessor to behave incorrectly because it checks whether the definitions contained within `__mergedSources` are a match for the returned type. The empty list always matches and `_asInlineFragment` incorrectly matches the returned type.

We should not be generating the inline fragment with `CompositeInlineFragment` conformance, which will then not generate the empty `__mergedSources` list. Codegen will also no longer generate empty `__selections` lists and this integration test was created to ensure that the generated model still conforms to `SelectionSet` through the extensions default implementation of `__selections`.

## Reference Issue: https://github.com/apollographql/apollo-ios/issues/3326

## Solution

The `TypeInfo` for a selection now has a property indicating whether it was defined by the user or formed through a combination of external selections, i.e.: composite. This allows the root field builder to definitively specify under which conditions a composite inline fragment should be generated.
