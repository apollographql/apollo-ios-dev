use indexmap::IndexSet;
use serde::Serialize;

/// Validation options for GraphQL code generation.
/// Mirrors `ValidationOptions` from `ValidationOptions.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct ValidationOptions {
    pub schema_namespace: String,
    pub disallowed_field_names: DisallowedFieldNames,
    pub disallowed_input_parameter_names: IndexSet<String>,
}

/// Field names that are disallowed in various contexts.
/// Mirrors `ValidationOptions.DisallowedFieldNames` from `ValidationOptions.swift`.
#[derive(Clone, Debug, Serialize)]
pub struct DisallowedFieldNames {
    pub all_fields: IndexSet<String>,
    pub entity: IndexSet<String>,
    pub entity_list: IndexSet<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validation_options_stores_schema_namespace() {
        let options = ValidationOptions {
            schema_namespace: "MySchema".to_string(),
            disallowed_field_names: DisallowedFieldNames {
                all_fields: IndexSet::new(),
                entity: IndexSet::new(),
                entity_list: IndexSet::new(),
            },
            disallowed_input_parameter_names: IndexSet::new(),
        };
        assert_eq!(options.schema_namespace, "MySchema");
    }

    #[test]
    fn test_disallowed_field_names_stores_all_sets() {
        let mut all_fields = IndexSet::new();
        all_fields.insert("__typename".to_string());

        let mut entity = IndexSet::new();
        entity.insert("fragments".to_string());

        let mut entity_list = IndexSet::new();
        entity_list.insert("items".to_string());

        let names = DisallowedFieldNames {
            all_fields,
            entity,
            entity_list,
        };

        assert!(names.all_fields.contains("__typename"));
        assert!(names.entity.contains("fragments"));
        assert!(names.entity_list.contains("items"));
    }

    #[test]
    fn test_validation_options_disallowed_input_parameter_names() {
        let mut params = IndexSet::new();
        params.insert("self".to_string());
        params.insert("Type".to_string());

        let options = ValidationOptions {
            schema_namespace: "Test".to_string(),
            disallowed_field_names: DisallowedFieldNames {
                all_fields: IndexSet::new(),
                entity: IndexSet::new(),
                entity_list: IndexSet::new(),
            },
            disallowed_input_parameter_names: params,
        };

        assert!(options.disallowed_input_parameter_names.contains("self"));
        assert!(options.disallowed_input_parameter_names.contains("Type"));
        assert_eq!(options.disallowed_input_parameter_names.len(), 2);
    }
}
