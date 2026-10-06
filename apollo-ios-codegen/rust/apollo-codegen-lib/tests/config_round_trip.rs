//! Comprehensive round-trip integration tests for the configuration system.
//!
//! Verifies JSON compatibility with Swift codegen by testing serialization/deserialization
//! fidelity, legacy key migration, default value accuracy, and unknown key rejection.

use apollo_codegen_lib::config::{
  AccessModifier, ApolloCodegenConfiguration, ApolloSchemaDownloadConfiguration, Composition,
  ConversionStrategies, CustomSchemaTypeName, DownloadMethod, EnumCases, ExperimentalFeatures,
  FieldAccessors, FieldMerging, FileInput, HTTPMethod, InputObjects, ModuleType,
  OperationDocumentFormat, OperationManifestConfiguration, OperationsFileOutput, OutputFormat,
  OutputOptions, SchemaCustomization, SelectionSetInitializers, TestMockFileOutput, Version,
};

// ============================================================================
// 1. Full Config Round-Trip (TEST-07 core)
// ============================================================================

#[test]
fn full_config_round_trip() {
  // Build a complete ApolloCodegenConfiguration with every field populated (no defaults).
  // Mirrors Swift's MockApolloCodegenConfiguration.decodedStruct
  let json = r#"{
    "schemaNamespace": "SerializedSchema",
    "input": {
      "schemaSearchPaths": ["/path/to/schema.graphqls"],
      "operationSearchPaths": ["/search/path/**/*.graphql"]
    },
    "output": {
      "schemaTypes": {
        "path": "/output/path",
        "moduleType": {"embeddedInTarget": {"name": "SomeTarget", "accessModifier": "public"}}
      },
      "operations": {"absolute": {"path": "/absolute/path", "accessModifier": "internal"}},
      "testMocks": {"swiftPackage": {"targetName": "SchemaTestMocks"}}
    },
    "options": {
      "additionalInflectionRules": [
        {"pluralization": {"singularRegex": "animal", "replacementRegex": "animals"}}
      ],
      "deprecatedEnumCases": "exclude",
      "schemaDocumentation": "exclude",
      "selectionSetInitializers": {},
      "operationDocumentFormat": ["definition"],
      "schemaCustomization": {
        "customTypeNames": {
          "MyEnum": {"enum": {"name": "CustomEnum", "cases": {"CaseOne": "CustomCaseOne"}}},
          "MyInterface": "CustomInterface",
          "MyObject": "CustomObject"
        }
      },
      "cocoapodsCompatibleImportStatements": true,
      "warningsOnDeprecatedUsage": "exclude",
      "conversionStrategies": {"enumCases": "none", "fieldAccessors": "camelCase", "inputObjects": "none"},
      "pruneGeneratedFiles": false,
      "markOperationDefinitionsAsFinal": true
    },
    "experimentalFeatures": {
      "fieldMerging": ["all"],
      "legacySafelistingCompatibleOperations": true
    },
    "operationManifest": {
      "path": "/operation/identifiers/path",
      "version": "persistedQueries",
      "generateManifestOnCodeGeneration": false
    }
  }"#;

  // Deserialize
  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
  assert_eq!(config.schema_namespace, "SerializedSchema");

  // Serialize back
  let serialized = serde_json::to_string(&config).unwrap();

  // Deserialize again
  let config2: ApolloCodegenConfiguration = serde_json::from_str(&serialized).unwrap();

  // Round-trip equality
  assert_eq!(config, config2);

  // Verify key fields survived
  assert_eq!(config2.schema_namespace, "SerializedSchema");
  assert!(config2.operation_manifest.is_some());
  assert_eq!(
    config2.experimental_features.field_merging,
    FieldMerging::ALL
  );
  assert!(config2.experimental_features.legacy_safelisting_compatible_operations);
}

#[test]
fn full_config_round_trip_json_byte_level() {
  // Build config, serialize, deserialize, re-serialize, compare JSON strings
  let config = make_full_config();
  let json1 = serde_json::to_string_pretty(&config).unwrap();
  let config2: ApolloCodegenConfiguration = serde_json::from_str(&json1).unwrap();
  let json2 = serde_json::to_string_pretty(&config2).unwrap();
  assert_eq!(json1, json2, "Byte-level JSON comparison failed");
}

// ============================================================================
// 2. Minimal Config with Defaults (D-17)
// ============================================================================

#[test]
fn minimal_config_defaults() {
  // JSON with only required fields
  let json = r#"{
    "schemaNamespace": "MinimalSchema",
    "input": {},
    "output": {
      "schemaTypes": {
        "path": "./generated",
        "moduleType": {"swiftPackageManager": {}}
      },
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    }
  }"#;

  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();

  // Verify all defaults match Swift's defaults
  assert_eq!(config.schema_namespace, "MinimalSchema");

  // FileInput defaults
  assert_eq!(config.input.schema_search_paths, vec!["**/*.graphqls"]);
  assert_eq!(config.input.operation_search_paths, vec!["**/*.graphql"]);

  // OutputOptions defaults
  assert_eq!(config.options.deprecated_enum_cases, Composition::Include);
  assert_eq!(config.options.schema_documentation, Composition::Include);
  assert_eq!(
    config.options.selection_set_initializers,
    SelectionSetInitializers::empty()
  );
  assert_eq!(
    config.options.operation_document_format,
    OperationDocumentFormat::DEFINITION
  );
  assert!(!config.options.cocoapods_compatible_import_statements);
  assert_eq!(
    config.options.warnings_on_deprecated_usage,
    Composition::Include
  );
  assert_eq!(
    config.options.conversion_strategies,
    ConversionStrategies::default()
  );
  assert!(config.options.prune_generated_files);
  assert!(!config.options.mark_operation_definitions_as_final);
  assert!(config.options.additional_inflection_rules.is_empty());

  // ExperimentalFeatures defaults
  assert_eq!(
    config.experimental_features.field_merging,
    FieldMerging::ALL
  );
  assert!(!config.experimental_features.legacy_safelisting_compatible_operations);

  // Optional fields
  assert!(config.schema_download.is_none());
  assert!(config.operation_manifest.is_none());
}

#[test]
fn minimal_config_serialize_then_deserialize() {
  let json = r#"{
    "schemaNamespace": "MinimalSchema",
    "input": {},
    "output": {
      "schemaTypes": {
        "path": "./generated",
        "moduleType": {"swiftPackageManager": {}}
      }
    }
  }"#;

  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
  let serialized = serde_json::to_string(&config).unwrap();
  let config2: ApolloCodegenConfiguration = serde_json::from_str(&serialized).unwrap();
  assert_eq!(config, config2);
}

// ============================================================================
// 3. Legacy Key Migration Tests (D-10, D-16)
// ============================================================================

#[test]
fn legacy_schema_name_key_migrates() {
  let json = r#"{
    "schemaName": "LegacySchema",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    }
  }"#;
  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
  assert_eq!(config.schema_namespace, "LegacySchema");

  // Verify serialization uses current key name
  let serialized = serde_json::to_string(&config).unwrap();
  assert!(serialized.contains("schemaNamespace"));
  assert!(!serialized.contains("\"schemaName\""));
}

#[test]
fn legacy_schema_download_configuration_key_migrates() {
  let json = r#"{
    "schemaNamespace": "Test",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    },
    "schemaDownloadConfiguration": {
      "downloadMethod": {"introspection": {"endpointURL": "http://example.com"}},
      "outputPath": "schema.graphqls"
    }
  }"#;
  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
  assert!(config.schema_download.is_some());

  // Verify serialization uses current key name
  let serialized = serde_json::to_string(&config).unwrap();
  assert!(serialized.contains("schemaDownload"));
  assert!(!serialized.contains("schemaDownloadConfiguration"));
}

#[test]
fn legacy_apqs_key_migrates_to_operation_document_format() {
  let json = r#"{"apqs": "automaticallyPersist"}"#;
  let options: OutputOptions = serde_json::from_str(json).unwrap();
  assert_eq!(
    options.operation_document_format,
    OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
  );

  // Verify serialization uses current key name
  let serialized = serde_json::to_string(&options).unwrap();
  assert!(serialized.contains("operationDocumentFormat"));
  assert!(!serialized.contains("apqs"));
}

#[test]
fn legacy_apqs_disabled_migrates_to_definition() {
  let json = r#"{"apqs": "disabled"}"#;
  let options: OutputOptions = serde_json::from_str(json).unwrap();
  assert_eq!(
    options.operation_document_format,
    OperationDocumentFormat::DEFINITION
  );
}

#[test]
fn legacy_apqs_persisted_only_migrates_to_operation_id() {
  let json = r#"{"apqs": "persistedOperationsOnly"}"#;
  let options: OutputOptions = serde_json::from_str(json).unwrap();
  assert_eq!(
    options.operation_document_format,
    OperationDocumentFormat::OPERATION_ID
  );
}

#[test]
fn legacy_operation_identifiers_path_migrates() {
  let json = r#"{
    "schemaNamespace": "Test",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}},
      "operationIdentifiersPath": "/some/path/ids.json"
    }
  }"#;
  let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
  assert!(config.operation_manifest.is_some());
  let manifest = config.operation_manifest.unwrap();
  assert_eq!(manifest.path, "/some/path/ids.json");
  assert_eq!(manifest.version, Version::Legacy);
  assert!(!manifest.generate_manifest_on_code_generation);
}

#[test]
fn legacy_query_string_literal_format_accepted_and_ignored() {
  let json = r#"{"queryStringLiteralFormat": "multiline"}"#;
  let options: OutputOptions = serde_json::from_str(json).unwrap();
  assert_eq!(options, OutputOptions::default());
}

#[test]
fn legacy_local_cache_mutations_accepted_and_ignored() {
  let json = r#"{"localCacheMutations": true}"#;
  let ssi: SelectionSetInitializers = serde_json::from_str(json).unwrap();
  assert_eq!(ssi, SelectionSetInitializers::empty());
}

// ============================================================================
// 4. Unknown Key Rejection Tests (Pattern 4)
// ============================================================================

#[test]
fn unknown_top_level_key_rejected() {
  let json = r#"{
    "schemaNamespace": "Test",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    },
    "unknownField": true
  }"#;
  let result = serde_json::from_str::<ApolloCodegenConfiguration>(json);
  assert!(result.is_err());
  let err_msg = result.unwrap_err().to_string();
  assert!(
    err_msg.contains("unknownField") || err_msg.contains("Unrecognized"),
    "Error should mention the unknown key: {}",
    err_msg
  );
}

#[test]
fn unknown_output_options_key_rejected() {
  let json = r#"{
    "schemaNamespace": "Test",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}}
    },
    "options": {
      "secret_feature": "flappy_bird"
    }
  }"#;
  let result = serde_json::from_str::<ApolloCodegenConfiguration>(json);
  assert!(result.is_err());
  let err_msg = result.unwrap_err().to_string();
  assert!(
    err_msg.contains("secret_feature") || err_msg.contains("Unrecognized"),
    "Error should mention the unknown key: {}",
    err_msg
  );
}

#[test]
fn unknown_file_output_key_rejected() {
  let json = r#"{
    "schemaNamespace": "Test",
    "input": {},
    "output": {
      "schemaTypes": {"path": "./gen", "moduleType": {"other": {}}},
      "operations": {"inSchemaModule": {}},
      "testMocks": {"none": {}},
      "options": {"selectionSetInitializers": {}}
    }
  }"#;
  let result = serde_json::from_str::<ApolloCodegenConfiguration>(json);
  assert!(result.is_err());
  let err_msg = result.unwrap_err().to_string();
  assert!(
    err_msg.contains("options") || err_msg.contains("Unrecognized"),
    "Error should mention the unknown key in output: {}",
    err_msg
  );
}

// ============================================================================
// 5. Individual Type Round-Trips
// ============================================================================

#[test]
fn module_type_embedded_in_target_round_trip() {
  let json = r#"{"embeddedInTarget":{"name":"SomeTarget","accessModifier":"public"}}"#;
  let parsed: ModuleType = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    ModuleType::EmbeddedInTarget {
      name: "SomeTarget".to_string(),
      access_modifier: AccessModifier::Public,
    }
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

/// Since 1.16.0 the deprecated `swiftPackageManager` key decodes to
/// `.swiftPackage(apolloSDKDependency: .default)` and is encoded in that form.
#[test]
fn module_type_spm_round_trip() {
  let json = r#"{"swiftPackageManager":{}}"#;
  let parsed: ModuleType = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, ModuleType::SwiftPackage { apollo_sdk_dependency: apollo_codegen_lib::config::module_type::ApolloSDKDependency::default() });
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(
    serialized,
    r#"{"swiftPackage":{"apolloSDKDependency":{"url":"https://github.com/apollographql/apollo-ios","sdkVersion":"default"}}}"#
  );
}

#[test]
fn module_type_other_round_trip() {
  let json = r#"{"other":{}}"#;
  let parsed: ModuleType = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, ModuleType::Other);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn module_type_embedded_default_access_modifier() {
  let json = r#"{"embeddedInTarget":{"name":"MyTarget"}}"#;
  let parsed: ModuleType = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    ModuleType::EmbeddedInTarget {
      name: "MyTarget".to_string(),
      access_modifier: AccessModifier::Internal,
    }
  );
}

#[test]
fn operations_file_output_in_schema_module_round_trip() {
  let json = r#"{"inSchemaModule":{}}"#;
  let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, OperationsFileOutput::InSchemaModule);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn operations_file_output_relative_round_trip() {
  let json = r#"{"relative":{"subpath":"Generated","accessModifier":"public"}}"#;
  let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    OperationsFileOutput::Relative {
      subpath: Some("Generated".to_string()),
      access_modifier: AccessModifier::Public,
    }
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn operations_file_output_absolute_round_trip() {
  let json = r#"{"absolute":{"path":"/absolute/path","accessModifier":"internal"}}"#;
  let parsed: OperationsFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    OperationsFileOutput::Absolute {
      path: "/absolute/path".to_string(),
      access_modifier: AccessModifier::Internal,
    }
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn test_mock_file_output_none_round_trip() {
  let json = r#"{"none":{}}"#;
  let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, TestMockFileOutput::None);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn test_mock_file_output_absolute_round_trip() {
  let json = r#"{"absolute":{"path":"x","accessModifier":"internal"}}"#;
  let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    TestMockFileOutput::Absolute {
      path: "x".to_string(),
      access_modifier: AccessModifier::Internal,
      scoping: Default::default(),
    }
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn test_mock_file_output_absolute_default_access_modifier() {
  let json = r#"{"absolute":{"path":"y"}}"#;
  let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    TestMockFileOutput::Absolute {
      path: "y".to_string(),
      access_modifier: AccessModifier::Public,
      scoping: Default::default(),
    }
  );
}

#[test]
fn test_mock_file_output_swift_package_round_trip() {
  let json = r#"{"swiftPackage":{"targetName":"SchemaTestMocks"}}"#;
  let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    TestMockFileOutput::SwiftPackage {
      target_name: Some("SchemaTestMocks".to_string()),
      scoping: Default::default(),
    }
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn access_modifier_round_trip() {
  let json = r#""public""#;
  let parsed: AccessModifier = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, AccessModifier::Public);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);

  let json = r#""internal""#;
  let parsed: AccessModifier = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, AccessModifier::Internal);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn schema_customization_all_formats_round_trip() {
  let json = r#"{"customTypeNames":{"MyEnum":{"enum":{"name":"CustomEnum","cases":{"CaseOne":"CustomCaseOne"}}},"MyInterface":"CustomInterface","MyObject":"CustomObject"}}"#;
  let parsed: SchemaCustomization = serde_json::from_str(json).unwrap();
  assert_eq!(parsed.custom_type_names.len(), 3);

  // Verify the three different CustomSchemaTypeName formats
  match &parsed.custom_type_names["MyInterface"] {
    CustomSchemaTypeName::Type { name } => assert_eq!(name, "CustomInterface"),
    other => panic!("Expected Type, got {:?}", other),
  }
  match &parsed.custom_type_names["MyObject"] {
    CustomSchemaTypeName::Type { name } => assert_eq!(name, "CustomObject"),
    other => panic!("Expected Type, got {:?}", other),
  }
  match &parsed.custom_type_names["MyEnum"] {
    CustomSchemaTypeName::Enum { name, cases } => {
      assert_eq!(name.as_deref(), Some("CustomEnum"));
      let cases_map = cases.as_ref().expect("cases should be Some");
      assert_eq!(cases_map.get("CaseOne").map(|s| s.as_str()), Some("CustomCaseOne"));
    }
    other => panic!("Expected Enum, got {:?}", other),
  }

  // Round-trip
  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: SchemaCustomization = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn selection_set_initializers_operations_round_trip() {
  let json = r#"{"operations":true}"#;
  let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
  assert!(parsed.operations);
  assert!(!parsed.named_fragments);
  assert!(parsed.definitions.is_empty());
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn selection_set_initializers_with_definitions_round_trip() {
  let json = r#"{"namedFragments":true,"definitionsNamed":["Operation1","Operation2"]}"#;
  let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
  assert!(parsed.named_fragments);
  assert!(parsed.definitions.contains("Operation1"));
  assert!(parsed.definitions.contains("Operation2"));
  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: SelectionSetInitializers = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn selection_set_initializers_only_definitions() {
  let json = r#"{"definitionsNamed":["Op1"]}"#;
  let parsed: SelectionSetInitializers = serde_json::from_str(json).unwrap();
  assert!(!parsed.operations);
  assert!(!parsed.named_fragments);
  assert!(parsed.definitions.contains("Op1"));
}

// ============================================================================
// 6. Schema Download Round-Trips
// ============================================================================

#[test]
fn schema_download_introspection_round_trip() {
  let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://server.com","httpMethod":{"POST":{}},"outputFormat":"SDL","includeDeprecatedInputValues":true}},"downloadTimeout":120.0,"headers":[{"key":"Accept-Encoding","value":"gzip"},{"key":"Authorization","value":"Bearer <token>"}],"outputPath":"ServerSchema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();

  assert!(matches!(
    parsed.download_method,
    DownloadMethod::Introspection { .. }
  ));
  assert!((parsed.download_timeout - 120.0).abs() < f64::EPSILON);
  assert_eq!(parsed.headers.len(), 2);
  assert_eq!(parsed.output_path, "ServerSchema.graphqls");

  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: ApolloSchemaDownloadConfiguration = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn schema_download_apollo_registry_round_trip() {
  let json = r#"{"downloadMethod":{"apolloRegistry":{"apiKey":"ABC123","graphID":"DEF456","variant":"final"}},"downloadTimeout":30.0,"headers":[],"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();

  if let DownloadMethod::ApolloRegistry {
    api_key,
    graph_id,
    variant,
  } = &parsed.download_method
  {
    assert_eq!(api_key, "ABC123");
    assert_eq!(graph_id, "DEF456");
    assert_eq!(variant, "final");
  } else {
    panic!("Expected ApolloRegistry download method");
  }

  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: ApolloSchemaDownloadConfiguration = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn schema_download_headers_array_of_structs_format() {
  let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"headers":[{"key":"Auth","value":"Bearer token"}],"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
  assert_eq!(parsed.headers.len(), 1);
  assert_eq!(parsed.headers[0].key, "Auth");
  assert_eq!(parsed.headers[0].value, "Bearer token");
}

#[test]
fn schema_download_headers_dictionary_format() {
  let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"headers":{"Authorization":"Bearer token","X-Custom":"value"},"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
  assert_eq!(parsed.headers.len(), 2);
  // Dictionary format is sorted by key
  assert_eq!(parsed.headers[0].key, "Authorization");
  assert_eq!(parsed.headers[1].key, "X-Custom");
}

#[test]
fn schema_download_default_timeout() {
  let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
  assert!((parsed.download_timeout - 30.0).abs() < f64::EPSILON);
  assert!(parsed.headers.is_empty());
}

#[test]
fn schema_download_get_method_round_trip() {
  let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com","httpMethod":{"GET":{"queryParameterName":"MyQuery"}},"outputFormat":"SDL","includeDeprecatedInputValues":false}},"downloadTimeout":30.0,"headers":[],"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();

  if let DownloadMethod::Introspection { http_method, .. } = &parsed.download_method {
    assert_eq!(
      *http_method,
      HTTPMethod::Get {
        query_parameter_name: "MyQuery".to_string()
      }
    );
  } else {
    panic!("Expected Introspection download method");
  }

  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: ApolloSchemaDownloadConfiguration = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn schema_download_apollo_registry_default_variant() {
  let json = r#"{"downloadMethod":{"apolloRegistry":{"apiKey":"key","graphID":"id"}},"outputPath":"schema.graphqls"}"#;
  let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();

  if let DownloadMethod::ApolloRegistry { variant, .. } = &parsed.download_method {
    assert_eq!(variant, "current");
  } else {
    panic!("Expected ApolloRegistry download method");
  }
}

// ============================================================================
// 7. Edge Cases
// ============================================================================

#[test]
fn field_merging_all_serializes_as_all() {
  let fm = FieldMerging::ALL;
  let json = serde_json::to_string(&fm).unwrap();
  assert_eq!(json, r#"["all"]"#);

  // Individual flags combined also serializes as ["all"]
  let fm2 = FieldMerging::ANCESTORS | FieldMerging::SIBLINGS | FieldMerging::NAMED_FRAGMENTS;
  let json2 = serde_json::to_string(&fm2).unwrap();
  assert_eq!(json2, r#"["all"]"#);
}

#[test]
fn field_merging_individual_flags_round_trip() {
  let json = r#"["ancestors","siblings"]"#;
  let parsed: FieldMerging = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, FieldMerging::ANCESTORS | FieldMerging::SIBLINGS);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn field_merging_empty() {
  let json = r#"[]"#;
  let parsed: FieldMerging = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, FieldMerging::empty());
}

#[test]
fn operation_document_format_empty_array_rejection() {
  let json = r#"[]"#;
  let result = serde_json::from_str::<OperationDocumentFormat>(json);
  assert!(result.is_err());
}

#[test]
fn operation_document_format_definition_round_trip() {
  let json = r#"["definition"]"#;
  let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, OperationDocumentFormat::DEFINITION);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn operation_document_format_operation_id_round_trip() {
  let json = r#"["operationId"]"#;
  let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, OperationDocumentFormat::OPERATION_ID);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn operation_document_format_both_round_trip() {
  let json = r#"["definition","operationId"]"#;
  let parsed: OperationDocumentFormat = serde_json::from_str(json).unwrap();
  assert_eq!(
    parsed,
    OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
  );
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn composition_round_trip() {
  let json = r#""include""#;
  let parsed: Composition = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, Composition::Include);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);

  let json = r#""exclude""#;
  let parsed: Composition = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, Composition::Exclude);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn conversion_strategies_round_trip() {
  let json = r#"{"enumCases":"camelCase","fieldAccessors":"camelCase","inputObjects":"none"}"#;
  let parsed: ConversionStrategies = serde_json::from_str(json).unwrap();
  assert_eq!(parsed.enum_cases, EnumCases::CamelCase);
  assert_eq!(parsed.field_accessors, FieldAccessors::CamelCase);
  assert_eq!(parsed.input_objects, InputObjects::None);
  let serialized = serde_json::to_string(&parsed).unwrap();
  let parsed2: ConversionStrategies = serde_json::from_str(&serialized).unwrap();
  assert_eq!(parsed, parsed2);
}

#[test]
fn operation_manifest_round_trip() {
  let json = r#"{"path":"/out/manifest.json","version":"persistedQueries","generateManifestOnCodeGeneration":false}"#;
  let parsed: OperationManifestConfiguration = serde_json::from_str(json).unwrap();
  assert_eq!(parsed.path, "/out/manifest.json");
  assert_eq!(parsed.version, Version::PersistedQueries);
  assert!(!parsed.generate_manifest_on_code_generation);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn output_format_round_trip() {
  let json = r#""SDL""#;
  let parsed: OutputFormat = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, OutputFormat::SDL);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);

  let json = r#""JSON""#;
  let parsed: OutputFormat = serde_json::from_str(json).unwrap();
  assert_eq!(parsed, OutputFormat::JSON);
  let serialized = serde_json::to_string(&parsed).unwrap();
  assert_eq!(serialized, json);
}

#[test]
fn file_input_defaults() {
  let fi = FileInput::default();
  assert_eq!(fi.schema_search_paths, vec!["**/*.graphqls"]);
  assert_eq!(fi.operation_search_paths, vec!["**/*.graphql"]);
}

#[test]
fn experimental_features_defaults() {
  let ef = ExperimentalFeatures::default();
  assert_eq!(ef.field_merging, FieldMerging::ALL);
  assert!(!ef.legacy_safelisting_compatible_operations);
}

// ============================================================================
// Helper
// ============================================================================

fn make_full_config() -> ApolloCodegenConfiguration {
  let json = r#"{
    "schemaNamespace": "FullConfig",
    "input": {
      "schemaSearchPaths": ["/path/to/schema.graphqls"],
      "operationSearchPaths": ["/search/**/*.graphql"]
    },
    "output": {
      "schemaTypes": {
        "path": "/output/path",
        "moduleType": {"embeddedInTarget": {"name": "SomeTarget", "accessModifier": "public"}}
      },
      "operations": {"absolute": {"path": "/absolute/path", "accessModifier": "internal"}},
      "testMocks": {"swiftPackage": {"targetName": "TestMocks"}}
    },
    "options": {
      "additionalInflectionRules": [],
      "deprecatedEnumCases": "include",
      "schemaDocumentation": "include",
      "selectionSetInitializers": {"operations": true},
      "operationDocumentFormat": ["definition", "operationId"],
      "schemaCustomization": {"customTypeNames": {}},
      "cocoapodsCompatibleImportStatements": false,
      "warningsOnDeprecatedUsage": "include",
      "conversionStrategies": {"enumCases": "camelCase", "fieldAccessors": "idiomatic", "inputObjects": "none"},
      "pruneGeneratedFiles": true,
      "markOperationDefinitionsAsFinal": false
    },
    "experimentalFeatures": {
      "fieldMerging": ["all"],
      "legacySafelistingCompatibleOperations": false
    },
    "schemaDownload": {
      "downloadMethod": {"introspection": {"endpointURL": "http://localhost:8080/graphql", "httpMethod": {"POST": {}}, "outputFormat": "SDL", "includeDeprecatedInputValues": false}},
      "downloadTimeout": 60.0,
      "headers": [{"key": "Authorization", "value": "Bearer token"}],
      "outputPath": "schema.graphqls"
    },
    "operationManifest": {
      "path": "/manifest.json",
      "version": "persistedQueries",
      "generateManifestOnCodeGeneration": true
    }
  }"#;
  serde_json::from_str(json).unwrap()
}
