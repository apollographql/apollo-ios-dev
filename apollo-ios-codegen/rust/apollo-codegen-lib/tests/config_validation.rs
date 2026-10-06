use std::collections::BTreeSet;

use apollo_codegen_lib::config::validation::{validate_config_values, ConfigError};
use apollo_codegen_lib::config::{
    AccessModifier, ApolloCodegenConfiguration, FieldMerging, ModuleType, SelectionSetInitializers,
    TestMockFileOutput,
};

/// Creates a minimal valid configuration that passes all validation checks.
/// Uses JSON deserialization to construct the config since some fields are pub(crate).
fn make_valid_config() -> ApolloCodegenConfiguration {
    let json = r#"{
    "schemaNamespace": "MySchema",
    "input": {
      "schemaSearchPaths": ["schema.graphqls"],
      "operationSearchPaths": ["**/*.graphql"]
    },
    "output": {
      "schemaTypes": {
        "path": "./generated",
        "moduleType": {"swiftPackageManager": {}}
      },
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    }
  }"#;
    serde_json::from_str(json).unwrap()
}

#[test]
fn rejects_empty_schema_namespace() {
    let mut config = make_valid_config();
    config.schema_namespace = "".to_string();
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::InvalidSchemaName { name, .. } => {
            assert_eq!(name, "");
        }
        other => panic!("Expected InvalidSchemaName, got {:?}", other),
    }
}

#[test]
fn rejects_schema_namespace_with_spaces() {
    let mut config = make_valid_config();
    config.schema_namespace = "My Schema".to_string();
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::InvalidSchemaName { name, .. } => {
            assert_eq!(name, "My Schema");
        }
        other => panic!("Expected InvalidSchemaName, got {:?}", other),
    }
}

#[test]
fn rejects_schema_namespace_schema_case_insensitive() {
    let mut config = make_valid_config();
    config.schema_namespace = "schema".to_string();
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::SchemaNameConflict { name } => {
            assert_eq!(name, "schema");
        }
        other => panic!("Expected SchemaNameConflict, got {:?}", other),
    }
}

#[test]
fn rejects_schema_namespace_schema_uppercase() {
    let mut config = make_valid_config();
    config.schema_namespace = "Schema".to_string();
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::SchemaNameConflict { name } => {
            assert_eq!(name, "Schema");
        }
        other => panic!("Expected SchemaNameConflict, got {:?}", other),
    }
}

#[test]
fn rejects_schema_namespace_apolloapi_case_insensitive() {
    let mut config = make_valid_config();
    config.schema_namespace = "ApolloAPI".to_string();
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::SchemaNameConflict { name } => {
            assert_eq!(name, "ApolloAPI");
        }
        other => panic!("Expected SchemaNameConflict, got {:?}", other),
    }
}

#[test]
fn rejects_field_merging_not_all_with_non_empty_selection_set_initializers() {
    let mut config = make_valid_config();
    config.experimental_features.field_merging = FieldMerging::ANCESTORS;
    config.options.selection_set_initializers = SelectionSetInitializers {
        operations: true,
        named_fragments: false,
        definitions: BTreeSet::new(),
    };
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::FieldMergingIncompatibility => {}
        other => panic!("Expected FieldMergingIncompatibility, got {:?}", other),
    }
}

#[test]
fn allows_field_merging_all_with_non_empty_selection_set_initializers() {
    let mut config = make_valid_config();
    config.experimental_features.field_merging = FieldMerging::ALL;
    config.options.selection_set_initializers = SelectionSetInitializers {
        operations: true,
        named_fragments: false,
        definitions: BTreeSet::new(),
    };
    let result = validate_config_values(&config);
    assert!(result.is_ok());
}

#[test]
fn rejects_test_mocks_swift_package_with_non_spm_module() {
    let mut config = make_valid_config();
    config.output.test_mocks = TestMockFileOutput::SwiftPackage {
        target_name: Some("TestMocks".to_string()),
        scoping: Default::default(),
    };
    config.output.schema_types.module_type = ModuleType::Other;
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::TestMocksInvalidSwiftPackageConfiguration => {}
        other => panic!(
            "Expected TestMocksInvalidSwiftPackageConfiguration, got {:?}",
            other
        ),
    }
}

#[test]
fn allows_test_mocks_swift_package_with_spm_module() {
    let mut config = make_valid_config();
    config.output.test_mocks = TestMockFileOutput::SwiftPackage {
        target_name: Some("TestMocks".to_string()),
        scoping: Default::default(),
    };
    config.output.schema_types.module_type = ModuleType::SwiftPackage {
        apollo_sdk_dependency:
            apollo_codegen_lib::config::module_type::ApolloSDKDependency::default(),
    };
    let result = validate_config_values(&config);
    assert!(result.is_ok());
}

#[test]
fn rejects_cocoapods_import_with_spm_module() {
    let mut config = make_valid_config();
    config.output.schema_types.module_type = ModuleType::SwiftPackage {
        apollo_sdk_dependency:
            apollo_codegen_lib::config::module_type::ApolloSDKDependency::default(),
    };
    config.options.cocoapods_compatible_import_statements = true;
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::InvalidConfiguration { message } => {
            assert!(
                message.contains("cocoapodsCompatibleImportStatements"),
                "Message should mention cocoapods: {}",
                message
            );
        }
        other => panic!("Expected InvalidConfiguration, got {:?}", other),
    }
}

#[test]
fn rejects_embedded_target_name_apollo_case_insensitive() {
    let mut config = make_valid_config();
    config.output.schema_types.module_type = ModuleType::EmbeddedInTarget {
        name: "Apollo".to_string(),
        access_modifier: AccessModifier::Internal,
    };
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::TargetNameConflict { name } => {
            assert_eq!(name, "Apollo");
        }
        other => panic!("Expected TargetNameConflict, got {:?}", other),
    }
}

#[test]
fn rejects_embedded_target_name_apolloapi_case_insensitive() {
    let mut config = make_valid_config();
    config.output.schema_types.module_type = ModuleType::EmbeddedInTarget {
        name: "apolloAPI".to_string(),
        access_modifier: AccessModifier::Internal,
    };
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::TargetNameConflict { name } => {
            assert_eq!(name, "apolloAPI");
        }
        other => panic!("Expected TargetNameConflict, got {:?}", other),
    }
}

#[test]
fn rejects_input_search_path_without_extension() {
    let mut config = make_valid_config();
    config.input.schema_search_paths = vec!["schema_without_ext".to_string()];
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::InputSearchPathInvalid { path } => {
            assert_eq!(path, "schema_without_ext");
        }
        other => panic!("Expected InputSearchPathInvalid, got {:?}", other),
    }
}

#[test]
fn rejects_input_search_path_ending_with_dot() {
    let mut config = make_valid_config();
    config.input.operation_search_paths = vec!["operations.".to_string()];
    let result = validate_config_values(&config);
    assert!(result.is_err());
    match result.unwrap_err() {
        ConfigError::InputSearchPathInvalid { path } => {
            assert_eq!(path, "operations.");
        }
        other => panic!("Expected InputSearchPathInvalid, got {:?}", other),
    }
}

#[test]
fn accepts_valid_config_all_checks_passing() {
    let config = make_valid_config();
    let result = validate_config_values(&config);
    assert!(result.is_ok(), "Valid config should pass: {:?}", result);
}
