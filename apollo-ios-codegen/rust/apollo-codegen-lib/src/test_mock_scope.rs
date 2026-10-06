//! Scoped test mocks (fork extension).
//!
//! Apollo generates one `<Object>+Mock.swift` per object type referenced by any
//! operation. This module computes the subset of those object types that a scoped
//! `output.testMocks` configuration (or the `--bazel-mocks-*` flags) asks for, so
//! that a shared base mock module and per-feature mock modules can be composed.
//!
//! The selection is a set computation only: the generated files are the same
//! templates Apollo renders, so the union of a partition's modules is file-for-file
//! identical to the unscoped output.

use graphql_compiler::compilation_result::{
    CompilationResult, FragmentDefinition, Selection, SelectionSet,
};
use graphql_compiler::schema::{GraphQLCompositeType, GraphQLNamedType};
use indexmap::{IndexMap, IndexSet};

use crate::codegen::{CodegenError, GenerationFilter};
use crate::config::test_mock_file_output::{TestMockScope, TestMockScoping};

/// Names of the object types referenced by the operations and fragments selected by
/// `filter` (every definition when `filter` is `None`), expanded exactly like
/// graphql-js's `addReferencedType` does for the whole configuration: an object adds
/// its interfaces, an interface adds its implementing objects, a union adds its
/// members and an input object adds its field types.
///
/// Only the object types already referenced by the whole configuration
/// (`compilation_result.referenced_types`) can appear, so the result is always a
/// subset of what an unscoped `testMocks` output generates.
pub fn referenced_object_types(
    compilation_result: &CompilationResult,
    filter: Option<&GenerationFilter>,
) -> IndexSet<String> {
    let mut walker = ReferencedObjectWalker::new(compilation_result);

    for operation in &compilation_result.operations {
        if !filter.is_none_or(|f| f.matches(&operation.file_path)) {
            continue;
        }
        for variable in &operation.variables {
            walker.add_name(variable.type_.named_type_name());
        }
        walker.add_composite(&operation.root_type);
        walker.walk_selection_set(&operation.selection_set);
    }
    for fragment in &compilation_result.fragments {
        if !filter.is_none_or(|f| f.matches(&fragment.file_path)) {
            continue;
        }
        walker.walk_fragment(fragment);
    }

    walker
        .names
        .into_iter()
        .filter(|name| walker.objects.contains(name.as_str()))
        .collect()
}

/// The object types a scoped test mock output generates:
/// `scope` ∪ `includeTypes` − `excludeTypes`, in the configuration's referenced-type
/// order (the order Apollo uses for the unscoped output).
///
/// `includeTypes` must name object types referenced by some operation of the
/// configuration (there is nothing to mock otherwise); unknown `excludeTypes` are
/// ignored so a base module's exclusion list can be shared by every feature.
pub fn select_mock_object_types(
    compilation_result: &CompilationResult,
    scoping: &TestMockScoping,
    filter: Option<&GenerationFilter>,
) -> Result<IndexSet<String>, CodegenError> {
    let all_objects: IndexSet<&str> = compilation_result
        .referenced_types
        .iter()
        .filter_map(|t| match t {
            GraphQLNamedType::Object(o) => Some(o.name.schema_name.as_str()),
            _ => None,
        })
        .collect();

    let scoped: IndexSet<String> = match scoping.scope {
        TestMockScope::All => all_objects.iter().map(|s| s.to_string()).collect(),
        TestMockScope::ReferencedByOperations => {
            referenced_object_types(compilation_result, filter)
        }
    };

    for name in &scoping.include_types {
        if !all_objects.contains(name.as_str()) {
            return Err(CodegenError::TestMocksUnknownIncludeType { name: name.clone() });
        }
    }

    let excluded: IndexSet<&str> = scoping.exclude_types.iter().map(String::as_str).collect();
    Ok(all_objects
        .iter()
        .filter(|name| {
            (scoped.contains(**name) || scoping.include_types.iter().any(|i| i == *name))
                && !excluded.contains(*name)
        })
        .map(|s| s.to_string())
        .collect())
}

struct ReferencedObjectWalker<'a> {
    /// Every named type the configuration references, in Apollo's order.
    types: &'a [GraphQLNamedType],
    /// The same types by schema name.
    by_name: IndexMap<&'a str, &'a GraphQLNamedType>,
    /// Schema names of the referenced object types.
    objects: IndexSet<&'a str>,
    names: IndexSet<String>,
    walked_fragments: IndexSet<&'a str>,
}

impl<'a> ReferencedObjectWalker<'a> {
    fn new(compilation_result: &'a CompilationResult) -> Self {
        let by_name: IndexMap<&str, &GraphQLNamedType> = compilation_result
            .referenced_types
            .iter()
            .map(|t| (t.name().schema_name.as_str(), t))
            .collect();
        let objects = compilation_result
            .referenced_types
            .iter()
            .filter_map(|t| match t {
                GraphQLNamedType::Object(o) => Some(o.name.schema_name.as_str()),
                _ => None,
            })
            .collect();
        Self {
            types: &compilation_result.referenced_types,
            by_name,
            objects,
            names: IndexSet::new(),
            walked_fragments: IndexSet::new(),
        }
    }

    fn add_composite(&mut self, composite: &GraphQLCompositeType) {
        let name = composite.name().schema_name.clone();
        self.add_name(&name);
    }

    /// Mirrors graphql-js `addReferencedType` (see `collect_referenced_types` in the
    /// compiler adapter), restricted to the types the configuration references.
    fn add_name(&mut self, name: &str) {
        if self.names.contains(name) {
            return;
        }
        self.names.insert(name.to_string());

        let Some(named_type) = self.by_name.get(name).copied() else {
            return;
        };
        match named_type {
            GraphQLNamedType::Interface(_) => {
                let implementors: Vec<&str> = self
                    .types
                    .iter()
                    .filter_map(|t| match t {
                        GraphQLNamedType::Object(o)
                            if o.interfaces.iter().any(|i| i.name.schema_name == name) =>
                        {
                            Some(o.name.schema_name.as_str())
                        }
                        _ => None,
                    })
                    .collect();
                for implementor in implementors {
                    self.add_name(implementor);
                }
            }
            GraphQLNamedType::Union(u) => {
                let members: Vec<String> =
                    u.types.iter().map(|m| m.name.schema_name.clone()).collect();
                for member in members {
                    self.add_name(&member);
                }
            }
            GraphQLNamedType::InputObject(io) => {
                let field_types: Vec<String> = io
                    .fields
                    .values()
                    .map(|f| f.type_.named_type_name().to_string())
                    .collect();
                for field_type in field_types {
                    self.add_name(&field_type);
                }
            }
            GraphQLNamedType::Object(o) => {
                let interfaces: Vec<String> = o
                    .interfaces
                    .iter()
                    .map(|i| i.name.schema_name.clone())
                    .collect();
                for interface in interfaces {
                    self.add_name(&interface);
                }
            }
            _ => {}
        }
    }

    fn walk_selection_set(&mut self, selection_set: &'a SelectionSet) {
        for selection in &selection_set.selections {
            match selection {
                Selection::Field(field) => {
                    self.add_name(field.type_.named_type_name());
                    if let Some(ref sub) = field.selection_set {
                        self.walk_selection_set(sub);
                    }
                }
                Selection::InlineFragment(inline) => {
                    self.add_composite(&inline.selection_set.parent_type);
                    self.walk_selection_set(&inline.selection_set);
                }
                Selection::FragmentSpread(spread) => {
                    self.walk_fragment(&spread.fragment);
                }
            }
        }
    }

    fn walk_fragment(&mut self, fragment: &'a FragmentDefinition) {
        if !self.walked_fragments.insert(fragment.name.as_str()) {
            return;
        }
        self.add_composite(&fragment.type_);
        self.walk_selection_set(&fragment.selection_set);
    }
}
