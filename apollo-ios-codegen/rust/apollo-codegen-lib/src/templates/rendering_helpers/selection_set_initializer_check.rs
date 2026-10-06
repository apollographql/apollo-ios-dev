//! Helper for checking whether selection set initializers should be generated.
//!
//! Mirrors Swift's `ApolloCodegen.ConfigurationContext.shouldGenerateSelectionSetInitializers(for:)`.

use crate::config::ApolloCodegenConfiguration;
use ir::definition::Definition;

/// Returns true if selection set initializers should be generated for the given definition.
///
/// Mirrors Swift's `ConfigurationContext.shouldGenerateSelectionSetInitializers(for:)`.
pub fn should_generate_selection_set_initializers(
    full_config: &ApolloCodegenConfiguration,
    definition: &dyn Definition,
    is_fragment: bool,
) -> bool {
    // `guard experimentalFeatures.fieldMerging == .all else { return false }`
    if full_config.experimental_features.field_merging != crate::config::FieldMerging::ALL {
        return false;
    }
    let config = &full_config.options.selection_set_initializers;

    // Local cache mutations always generate initializers
    if definition.is_local_cache_mutation() {
        return true;
    }

    // Check if the specific definition name is in the named set
    if config.definitions.contains(definition.name()) {
        return true;
    }

    // Check blanket flags
    if is_fragment {
        config.named_fragments
    } else {
        config.operations
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    use ir::definition_entity_storage::DefinitionEntityStorage;
    use ir::fields::EntityField;
    use crate::config::selection_set_initializers::SelectionSetInitializers;

    /// Wraps the initializer options in a full configuration (fieldMerging defaults to all).
    fn with(init: SelectionSetInitializers) -> ApolloCodegenConfiguration {
        let mut config: ApolloCodegenConfiguration = serde_json::from_str(r#"{
          "schemaNamespace": "mySchema",
          "input": {},
          "output": {
            "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
            "operations": {"inSchemaModule": {}},
            "testMocks": {"none": {}}
          }
        }"#).unwrap();
        config.options.selection_set_initializers = init;
        config
    }

    /// A minimal mock implementing the Definition trait for testing.
    /// Avoids constructing full Entity/EntityField/DefinitionEntityStorage which
    /// have pub(crate) constructors in the ir crate.
    struct MockDefinition {
        name: String,
        is_lcm: bool,
    }

    impl MockDefinition {
        fn new(name: &str, is_lcm: bool) -> Self {
            MockDefinition {
                name: name.to_string(),
                is_lcm,
            }
        }
    }

    impl Definition for MockDefinition {
        fn name(&self) -> &str {
            &self.name
        }

        fn root_field(&self) -> &EntityField {
            unimplemented!("not needed for selection set initializer check tests")
        }

        fn entity_storage(&self) -> &DefinitionEntityStorage {
            unimplemented!("not needed for selection set initializer check tests")
        }

        fn is_local_cache_mutation(&self) -> bool {
            self.is_lcm
        }
    }

    #[test]
    fn local_cache_mutation_always_returns_true() {
        let config = SelectionSetInitializers::empty();
        let def = MockDefinition::new("MyMutation", true);
        assert!(should_generate_selection_set_initializers(&with(config.clone()), &def, false));
    }

    #[test]
    fn local_cache_mutation_true_even_as_fragment() {
        let config = SelectionSetInitializers::empty();
        let def = MockDefinition::new("MyFragment", true);
        assert!(should_generate_selection_set_initializers(&with(config.clone()), &def, true));
    }

    #[test]
    fn operations_flag_true_returns_true_for_non_fragment() {
        let config = SelectionSetInitializers {
            operations: true,
            named_fragments: false,
            definitions: BTreeSet::new(),
        };
        let def = MockDefinition::new("MyQuery", false);
        assert!(should_generate_selection_set_initializers(&with(config.clone()), &def, false));
    }

    #[test]
    fn operations_flag_false_returns_false_for_non_fragment() {
        let config = SelectionSetInitializers {
            operations: false,
            named_fragments: false,
            definitions: BTreeSet::new(),
        };
        let def = MockDefinition::new("MyQuery", false);
        assert!(!should_generate_selection_set_initializers(&with(config.clone()), &def, false));
    }

    #[test]
    fn named_fragments_flag_true_returns_true_for_fragment() {
        let config = SelectionSetInitializers {
            operations: false,
            named_fragments: true,
            definitions: BTreeSet::new(),
        };
        let def = MockDefinition::new("MyFragment", false);
        assert!(should_generate_selection_set_initializers(&with(config.clone()), &def, true));
    }

    #[test]
    fn named_fragments_flag_false_returns_false_for_fragment() {
        let config = SelectionSetInitializers {
            operations: false,
            named_fragments: false,
            definitions: BTreeSet::new(),
        };
        let def = MockDefinition::new("MyFragment", false);
        assert!(!should_generate_selection_set_initializers(&with(config.clone()), &def, true));
    }

    #[test]
    fn definition_name_in_set_returns_true() {
        let mut defs = BTreeSet::new();
        defs.insert("MyQuery".to_string());
        let config = SelectionSetInitializers {
            operations: false,
            named_fragments: false,
            definitions: defs,
        };
        let def = MockDefinition::new("MyQuery", false);
        assert!(should_generate_selection_set_initializers(&with(config.clone()), &def, false));
    }

    #[test]
    fn definition_name_not_in_set_returns_false() {
        let mut defs = BTreeSet::new();
        defs.insert("OtherQuery".to_string());
        let config = SelectionSetInitializers {
            operations: false,
            named_fragments: false,
            definitions: defs,
        };
        let def = MockDefinition::new("MyQuery", false);
        assert!(!should_generate_selection_set_initializers(&with(config.clone()), &def, false));
    }

    #[test]
    fn empty_config_returns_false_for_non_lcm() {
        let config = SelectionSetInitializers::empty();
        let def = MockDefinition::new("MyQuery", false);
        assert!(!should_generate_selection_set_initializers(&with(config.clone()), &def, false));
        assert!(!should_generate_selection_set_initializers(&with(config.clone()), &def, true));
    }
}
