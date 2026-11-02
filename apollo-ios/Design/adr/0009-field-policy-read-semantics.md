# ADR 0009 — Field policy read semantics

- **Status:** Accepted (implementation scheduled before the 3.0 final tag)
- **Date:** 2026-11-02
- **Engineering plan reference:** [cache-rewrite-phase1-execution.md](../cache-rewrite-phase1-execution.md) Pre-3.0 investigations, INV-008
- **Related ADRs:** [0007](./0007-selection-aware-cache-reads.md) (selection-aware cache reads), [0008](./0008-incomplete-cache-hits.md) (incomplete cache hits)
- **2.x counterparts:** apollographql/apollo-ios-dev#1091 (direct-reference resolution, shape rules, codegen list rules), #1097 (key paths through a list of input objects), #1098 (stored value first)

## Context

A field policy (`@fieldPolicy` or `FieldPolicy.Provider`) derives cache keys from a field's arguments, so a field can read objects that were cached by *other* queries, for argument values it has never fetched. Commit `4d72c4dd9` (PR-009d-iii) moved the 3.0 reader to resolve a policy key to a direct `CacheReference` (`CacheReadStrategy.policyReference` / `.policyReferenceList`), instead of looking the key up as a field on the parent record. It also stopped projecting and loading the parent record for policy fields.

The same direct-reference fix landed in 2.x through apollographql/apollo-ios-dev#1091. Review of that work found four problems, and every one of them is also present in the 3.0 read path:

1. **A policy key that doesn't match the stored record always misses.** The network write is policy-agnostic: it stores the field under its arguments on the parent record (`QUERY_ROOT["hero(name:\"Luke\")"] → Hero:1000`), and keys the object by its type policy. A policy read never consults that stored value. Whenever the policy-derived key differs from the stored record's key, every read misses, *including a read of the exact arguments just fetched*. That happens in four situations:
   - the type policy keys by `id` while the field policy keys by `name`;
   - the type has no type policy, so its records are keyed by path;
   - the field returns an interface or union (INV-005): the policy builds `Character:1000`, but the record is stored as `Human:1000`;
   - the server normalizes arguments: `name: "luke"` returns `Hero:Luke`.
2. **Policy results that don't fit the field's shape.** `cacheReadStrategy` emits `.policyReferenceList` for any `.list` result and `.policyReference` for any `.single` result, regardless of the field's type. Three things go wrong:
   - On a nested-list field (`[[Hero]]`), the flat reference list fails with `JSONDecodingError.wrongType`.
   - A key list on a single-object field (a key path reaching a list inside an input object) fails the same way.
   - The directive evaluator decides single vs list by how many values an argument has, so a list field whose only key is a scalar (`heroes(ids:, faction:)` with `keyArgs: "faction"`) can read back a fabricated one-element list.
3. **Parent existence is assumed, not checked.** When every field projected for a record is a policy field, `ApolloStore.ReadTransaction.loadObject` skips the cache and returns an empty placeholder `Record`, so the parent's existence is never checked. In generated code this is only reachable at the operation root, because codegen selects `__typename` on every non-root selection set. But a hand-written selection set can make a read report a non-root object as present when the cache has no record for it.
4. **Kotlin precedent.** `4d72c4dd9` justified skipping the parent record by citing Apollo Kotlin's `FieldPolicyCacheResolver`. That describes the cache built into apollo-kotlin v4. The current standalone cache (`apollo-kotlin-normalized-cache` v1.x) backs `FieldPolicyCacheResolver` with `KeyArgumentsCacheResolver`. That resolver returns `parent[fieldKey]` when it is present, including an explicit `null`, and only then derives keys from the arguments. Apollo Client web's documented cache-redirect pattern does the same: `read(existing, { toReference }) { return existing ?? toReference(...) }`.

## Decision

### 1. Read order: stored value first, field policy for unseen arguments

For a field that has a field policy:

1. If the parent record has a value stored under the field's normalized name for the current arguments (`info.normalizedFieldName()`), use it. That value can be a reference, a list, or an explicit `null`. The field policy is not evaluated, and `FieldPolicy.Provider` functions are not called.
2. Otherwise, resolve the field policy into a reference or references, subject to the shape rules in §3.
3. If there is no applicable policy result, the field is missing, as for any other field.

A same-argument read therefore returns exactly what the server returned for those arguments, including list order, list membership and `null` elements. The policy only serves its intended purpose: hits for argument values that were never fetched.

### 2. Projection and parent existence

- **Projection.** `ProjectionCollector` projects a policy field's stored field name on its parent, like any other field. The policy cases of `CacheReadStrategy` carry that name, for example `.policyReference(key, storedFieldName:)` and `.policyReferenceList(keys, storedFieldName:)`. The resolver and the collector still agree by construction.
- **Only operation roots are implicit.** `QUERY_ROOT`, `MUTATION_ROOT` and `SUBSCRIPTION_ROOT` may read as an empty record when absent from the cache. Any other record that a read reaches must exist, or the read misses. No read may report a non-root object that the cache has no record for. The rule applies two ways:
  - The empty-projection shortcut in `loadObject` applies only to root keys.
  - A non-root record whose projection is empty still needs an existence check. This covers a selection set where every field is skipped by `@skip`/`@include`. The check goes through `loadFields` with an empty field set, which must report an existing record as `Record(fields: [:])` and an absent one as `nil`, matching the existing existence-signal contract.
- **Cost.** A record level made only of policy fields, typically the root, now loads its stored field names. That is one indexed lookup, batched with sibling projections by `ProjectionLoader`. 2.x pays nothing extra, because it already loads whole parent records.

### 3. Shape rules

A policy result is applied only when it matches the field's shape. The list depth is the number of `.list` wrappers in the output type, ignoring `.nonNull`:

| Field shape | Programmatic provider consulted | Directive result applied |
|---|---|---|
| object (depth 0) | `cacheKey(for:…)` | `.single` |
| flat list (depth 1) | `cacheKeyList(for:…)` | `.list` |
| nested list (depth ≥ 2) | neither | neither |

Any other combination has no policy value: the field is read only from its stored value (§1), or it is missing.

`FieldPolicyDirectiveEvaluator` reports `.list` whenever the key argument's *value* is a list, including a one-element list, and `.single` only for scalar values. It never decides by value count. It returns no result when two key arguments resolve to lists.

### 4. Codegen validation (shared with 2.x)

The `@fieldPolicy` validation in `fieldPolicyDirective.ts` is shared with 2.x and arrives on the plan branch through the regular merge from `main`:

- A field with a list return type needs exactly one key argument that resolves to a list. A field with such a key argument must return a list. Non-key list arguments don't count.
- A key path may pass through at most one list level, including a list of input objects (`inputs.id`, #1097), and must end at a scalar or enum.
- Nested-list return types, and nested lists in key arguments or along key paths, are rejected.

### 5. Freshness

The stored value read under §1 is a field like any other. A stale stored value (ADR 0003) does **not** fall through to the field policy: it is treated as stale, with the TTL enforcement and stale tolerance in effect (ADRs 0003 and 0005). Falling through could serve a policy-derived record that is no fresher, and would make freshness depend on whether the field has a policy.

## Alternatives considered

### A. Policy only (the current 3.0 behavior)

The policy is authoritative, and a missing target is a miss. This is the simplest, and it never hides a misconfigured policy. **Rejected** because a mismatch between policy keys and stored keys makes every read miss, even for arguments just fetched, and nothing reports it: the app just always goes to the network. It also diverges from current Apollo Kotlin and Apollo Client web.

### B. Policy first, stored value if the policy's targets are missing

Same-argument reads hit. **Rejected:**
- A missing target is only discovered while loading the referenced records, so falling back means catching and telling apart "record missing" failures in the deferred load chain, all-or-nothing for lists.
- It needs the parent projection anyway, so it costs as much as §1 with more complexity.
- When the policy and the stored value disagree, it prefers the derived answer over the one the server returned.

### C. Reuse items from other stored lists (Kotlin's `listItemsInParent`)

For a flat list field, take the elements for requested key values from other argument combinations already stored on the parent before deriving keys. **Deferred.** It is compatible with this decision as a later addition, and it overlaps ADR 0008's partial-list work (Symptom 2).

## Consequences

- **Same-argument reads.** Reads of fields with policies hit for arguments that were fetched before, regardless of how the type policy keys records. INV-005 (interface-typed policies) then only affects argument values that were never fetched.
- **ADR 0008, Symptom 2.** All-or-nothing policy lists now only apply to argument values that were never fetched. Same-argument list reads come from the stored list and are complete.
- **Projection.** Root levels made only of policy fields project their stored field names. `loadObject` loses the policy-only placeholder path, and gains an existence check for empty non-root projections.
- **Behavior changes from 2.x.** None. 2.x adopts §1 and §3 in #1091 and #1098, and already requires every parent record to exist (`ReadTransaction.loadObject(forKey:)` throws `missingValue` for an absent record), which is stricter than §2's root rule.
- **Merging from `main`.** The merge of these 2.x changes into the plan branch conflicts in `CacheDataExecutionSource.resolveCacheKey` and `FieldPolicyDirectiveEvaluator`. Resolve it by keeping 3.0's `CacheReadStrategy` structure and moving the 2.x semantics into `Selection.Field.cacheReadStrategy(…)`, not by restoring 2.x's inline resolution.

## Implementation (INV-008)

One PR on the Phase 1A stack, after the plan branch has merged the 2.x changes from `main`:

1. `CacheReadStrategy`: add the stored field name to both policy cases, and apply §3's depth and shape rules in `cacheReadStrategy(…)`. Select the provider function by list depth.
2. `CacheDataExecutionSource.resolveCacheKey`: read `object[storedFieldName]` first, and fall back to the policy reference(s).
3. `ProjectionCollector.collectField`: insert the stored field name for policy strategies.
4. `ApolloStore.ReadTransaction.loadObject`: limit the empty-projection shortcut to root keys, and probe existence for empty non-root projections.
5. Tests in `FieldPolicyTests`:
   - same-argument round trips where the type policy keys by `id`, for both a single object and a list;
   - a stored `null` taking precedence over a policy-targeted record;
   - a nested-list round trip, and shape mismatches resolving to a miss;
   - a root level made only of policy fields, with `QUERY_ROOT` absent: the read hits;
   - a hand-written non-root policy-only level whose record is absent: the read misses;
   - a stale stored value not falling through to the policy.
