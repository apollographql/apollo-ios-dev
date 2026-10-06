//! Template for generating a Swift Package Manager `Package.swift` module file.
//!
//! Mirrors Swift's `SwiftPackageManagerModuleTemplate` from
//! `Sources/ApolloCodegenLib/Templates/SwiftPackageManagerModuleTemplate.swift`.

use crate::config::module_type::ApolloSDKDependency;
use crate::config::test_mock_file_output::TestMockFileOutput;
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::{
    ConfigurationContext, NonFatalErrorRecorder, TemplateRenderer, TemplateTarget,
};

/// The codegen version used for the default SDK dependency.
///
/// Mirrors Swift's `Constants.CodegenVersion`.
pub const CODEGEN_VERSION: &str = "2.4.0";

/// Provides the format to define a Swift Package Manager module.
///
/// The output conforms to the Swift package configuration definition.
///
/// Mirrors Swift's `SwiftPackageManagerModuleTemplate` struct.
pub struct SwiftPackageManagerModuleTemplate {
    pub test_mock_config: TestMockFileOutput,
    pub config: ConfigurationContext,
    pub apollo_sdk_dependency: ApolloSDKDependency,
}

impl SwiftPackageManagerModuleTemplate {
    /// Creates a new template, extracting the SDK dependency from the module type config.
    pub fn new(test_mock_config: TestMockFileOutput, config: ConfigurationContext) -> Self {
        let apollo_sdk_dependency = config
            .output()
            .schema_types
            .module_type
            .apollo_sdk_dependency()
            .unwrap_or_default();

        Self {
            test_mock_config,
            config,
            apollo_sdk_dependency,
        }
    }

    /// Returns the test mock target info (targetName, path) if applicable.
    ///
    /// Returns `None` for `.none` and `.absolute` test mock configs.
    /// For `.swiftPackage`, returns the target name and path.
    fn test_mock_target(&self) -> Option<(String, String)> {
        match &self.test_mock_config {
            TestMockFileOutput::None | TestMockFileOutput::Absolute { .. } => None,
            TestMockFileOutput::SwiftPackage { target_name, .. } => {
                if let Some(name) = target_name {
                    let cased = first_uppercased(name);
                    Some((cased.clone(), format!("./{}", cased)))
                } else {
                    let namespace = first_uppercased(self.config.schema_namespace());
                    Some((format!("{}TestMocks", namespace), "./TestMocks".to_string()))
                }
            }
        }
    }
}

impl TemplateRenderer for SwiftPackageManagerModuleTemplate {
    fn config(&self) -> &ConfigurationContext {
        &self.config
    }

    fn target(&self) -> TemplateTarget {
        TemplateTarget::ModuleFile
    }

    fn render_header_template(
        &self,
        _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> Option<String> {
        // No header comment for Package.swift files
        None
    }

    fn render_body_template(&self, _non_fatal_error_recorder: &NonFatalErrorRecorder) -> String {
        let cased_schema_namespace = first_uppercased(self.config.schema_namespace());
        let dependency_string = self
            .apollo_sdk_dependency
            .dependency_string(CODEGEN_VERSION);

        let test_mock_product = if let Some((ref target_name, _)) = self.test_mock_target() {
            format!(
                "\n    .library(name: \"{tn}\", targets: [\"{tn}\"]),",
                tn = target_name
            )
        } else {
            String::new()
        };

        let test_mock_target = if let Some((ref target_name, ref path)) = self.test_mock_target() {
            format!(
                "\n    .target(\n      name: \"{tn}\",\n      dependencies: [\n        .product(name: \"ApolloTestSupport\", package: \"apollo-ios\"),\n        .target(name: \"{ns}\"),\n      ],\n      path: \"{path}\"\n    ),",
                tn = target_name,
                ns = cased_schema_namespace,
                path = path
            )
        } else {
            String::new()
        };

        format!(
            "\
// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: \"{ns}\",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: \"{ns}\", targets: [\"{ns}\"]),{test_mock_product}
  ],
  dependencies: [
    {dependency_string},
  ],
  targets: [
    .target(
      name: \"{ns}\",
      dependencies: [
        .product(name: \"ApolloAPI\", package: \"apollo-ios\"),
      ],
      path: \"./Sources\"
    ),{test_mock_target}
  ],
  swiftLanguageModes: [.v6, .v5]
)
",
            ns = cased_schema_namespace,
            test_mock_product = test_mock_product,
            dependency_string = dependency_string,
            test_mock_target = test_mock_target,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ApolloCodegenConfiguration;

    fn make_config(json: &str) -> ConfigurationContext {
        let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
        ConfigurationContext::new(config, None)
    }

    #[test]
    fn test_renders_basic_package_swift() {
        let config = make_config(
            r#"{
            "schemaNamespace": "mySchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );
        let template = SwiftPackageManagerModuleTemplate::new(TestMockFileOutput::None, config);
        let result = template.render();
        let body = result.body;

        assert!(
            body.contains("// swift-tools-version:6.1"),
            "body:\n{}",
            body
        );
        assert!(body.contains("name: \"MySchema\""));
        assert!(body.contains(".library(name: \"MySchema\", targets: [\"MySchema\"])"));
        assert!(body.contains(".product(name: \"ApolloAPI\", package: \"apollo-ios\")"));
        assert!(body.contains("path: \"./Sources\""));
        // 1.16.0+: the default `apolloSDKDependency` pins the CLI's own version
        assert!(
            body.contains(&format!(
                ".package(url: \"https://github.com/apollographql/apollo-ios\", exact: \"{}\")",
                CODEGEN_VERSION
            )),
            "body:\n{}",
            body
        );
        // 2.0.0+: Swift 6 package with both language modes
        assert!(
            body.contains("swiftLanguageModes: [.v6, .v5]"),
            "body:\n{}",
            body
        );
        // No test mock target
        assert!(!body.contains("ApolloTestSupport"));
    }

    #[test]
    fn test_renders_with_test_mock_default_name() {
        let config = make_config(
            r#"{
            "schemaNamespace": "mySchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"swiftPackage": {"targetName": null}}
            }
        }"#,
        );
        let test_mocks = TestMockFileOutput::SwiftPackage {
            target_name: None,
            scoping: Default::default(),
        };
        let template = SwiftPackageManagerModuleTemplate::new(test_mocks, config);
        let result = template.render();
        let body = result.body;

        assert!(body.contains("MySchemaTestMocks"));
        assert!(body.contains("path: \"./TestMocks\""));
        assert!(body.contains("ApolloTestSupport"));
    }

    #[test]
    fn test_renders_with_test_mock_custom_name() {
        let config = make_config(
            r#"{
            "schemaNamespace": "mySchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"swiftPackage": {"targetName": "customMocks"}}
            }
        }"#,
        );
        let test_mocks = TestMockFileOutput::SwiftPackage {
            target_name: Some("customMocks".to_string()),
            scoping: Default::default(),
        };
        let template = SwiftPackageManagerModuleTemplate::new(test_mocks, config);
        let result = template.render();
        let body = result.body;

        assert!(body.contains("CustomMocks"));
        assert!(body.contains("path: \"./CustomMocks\""));
        assert!(body.contains("ApolloTestSupport"));
    }

    #[test]
    fn test_no_header_comment() {
        let config = make_config(
            r#"{
            "schemaNamespace": "mySchema",
            "input": {},
            "output": {
                "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
                "operations": {"inSchemaModule": {}},
                "testMocks": {"none": {}}
            }
        }"#,
        );
        let template = SwiftPackageManagerModuleTemplate::new(TestMockFileOutput::None, config);
        let result = template.render();
        // Module files with no header should not contain @generated
        assert!(!result.body.contains("@generated"));
    }
}
