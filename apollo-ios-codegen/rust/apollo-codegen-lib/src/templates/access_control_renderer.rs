//! Access control rendering for generated Swift code.
//!
//! Mirrors Swift's `AccessControlRenderer.swift` from
//! `Sources/ApolloCodegenLib/Templates/AccessControlRenderer.swift`.

use std::fmt;

use crate::config::access_modifier::AccessModifier;
use crate::config::module_type::ModuleType;
use crate::config::operations_file_output::OperationsFileOutput;
use crate::config::test_mock_file_output::TestMockFileOutput;
use crate::config::ApolloCodegenConfiguration;
use super::TemplateTarget;

/// The `@_spi` values used by Apollo iOS.
///
/// Mirrors Swift's `SPI` enum from `AccessControlRenderer.swift`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SPI {
  Unsafe,
  Internal,
  Execution,
}

impl fmt::Display for SPI {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      SPI::Unsafe => write!(f, "Unsafe"),
      SPI::Internal => write!(f, "Internal"),
      SPI::Execution => write!(f, "Execution"),
    }
  }
}

/// The scope of the access control modifier within the rendered template.
///
/// Mirrors Swift's `AccessControlRenderer.Scope` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
  /// The access modifier for the namespace (extension) declaration.
  Namespace,
  /// The access modifier for the parent type (struct, class, enum) declaration.
  Parent,
  /// The access modifier for a member (property, function) declaration.
  Member,
}

/// Renders Swift access control modifiers based on the template target,
/// configuration, and scope.
///
/// Mirrors Swift's `AccessControlRenderer` struct.
pub struct AccessControlRenderer {
  access_modifier: Option<AccessModifier>,
}

impl AccessControlRenderer {
  /// Creates a new `AccessControlRenderer` for the given target, config, and scope.
  pub fn new(
    target: &TemplateTarget,
    config: &ApolloCodegenConfiguration,
    scope: Scope,
  ) -> Self {
    Self {
      access_modifier: Self::access_control_modifier(target, config, scope),
    }
  }

  /// Renders the access control modifier string without any SPI annotations.
  pub fn render(&self) -> String {
    self.render_with_spis(&[])
  }

  /// Renders the access control modifier string, optionally prefixed with
  /// `@_spi(...)` annotations.
  ///
  /// SPI annotations are only included when the access modifier is `public`.
  pub fn render_with_spis(&self, spis: &[SPI]) -> String {
    let mut string = match self.access_modifier {
      Some(AccessModifier::Public) => "public ".to_string(),
      Some(AccessModifier::Internal) | None => String::new(),
    };

    if !self.should_include_spi() {
      return string;
    }

    for spi in spis.iter().rev() {
      string = format!("@_spi({}) {}", spi, string);
    }

    string
  }

  /// SPI should only be used on public declarations. Internal declarations must omit them.
  fn should_include_spi(&self) -> bool {
    self.access_modifier == Some(AccessModifier::Public)
  }

  /// Dispatches to the correct access control modifier computation based on the target.
  fn access_control_modifier(
    target: &TemplateTarget,
    config: &ApolloCodegenConfiguration,
    scope: Scope,
  ) -> Option<AccessModifier> {
    match target {
      TemplateTarget::ModuleFile | TemplateTarget::SchemaFile(_) => {
        Self::schema_access_control_modifier(scope, config)
      }
      TemplateTarget::OperationFile { .. } => {
        Self::operation_access_control_modifier(scope, config)
      }
      TemplateTarget::TestMockFile => {
        Self::test_mock_access_control_modifier(scope, config)
      }
    }
  }

  /// Computes the access modifier for schema file targets.
  ///
  /// Mirrors Swift's `schemaAccessControlModifier(_:_:)`.
  fn schema_access_control_modifier(
    scope: Scope,
    config: &ApolloCodegenConfiguration,
  ) -> Option<AccessModifier> {
    match (&config.output.schema_types.module_type, scope) {
      (ModuleType::EmbeddedInTarget { .. }, Scope::Parent) => None,
      (
        ModuleType::EmbeddedInTarget {
          access_modifier: AccessModifier::Public,
          ..
        },
        Scope::Namespace | Scope::Member,
      ) => Some(AccessModifier::Public),
      (
        ModuleType::EmbeddedInTarget {
          access_modifier: AccessModifier::Internal,
          ..
        },
        Scope::Namespace | Scope::Member,
      ) => Some(AccessModifier::Internal),
      (ModuleType::SwiftPackage { .. } | ModuleType::Other, _) => {
        Some(AccessModifier::Public)
      }
    }
  }

  /// Computes the access modifier for operation file targets.
  ///
  /// Mirrors Swift's `operationAccessControlModifier(_:_:)`.
  fn operation_access_control_modifier(
    scope: Scope,
    config: &ApolloCodegenConfiguration,
  ) -> Option<AccessModifier> {
    match (&config.output.operations, scope) {
      (OperationsFileOutput::InSchemaModule, _) => {
        Self::schema_access_control_modifier(scope, config)
      }
      (
        OperationsFileOutput::Absolute {
          access_modifier: AccessModifier::Public,
          ..
        }
        | OperationsFileOutput::Relative {
          access_modifier: AccessModifier::Public,
          ..
        },
        _,
      ) => Some(AccessModifier::Public),
      (
        OperationsFileOutput::Absolute {
          access_modifier: AccessModifier::Internal,
          ..
        }
        | OperationsFileOutput::Relative {
          access_modifier: AccessModifier::Internal,
          ..
        },
        _,
      ) => Some(AccessModifier::Internal),
    }
  }

  /// Computes the access modifier for test mock file targets.
  ///
  /// Mirrors Swift's `testMockAccessControlModifier(_:_:)`.
  fn test_mock_access_control_modifier(
    _scope: Scope,
    config: &ApolloCodegenConfiguration,
  ) -> Option<AccessModifier> {
    match &config.output.test_mocks {
      TestMockFileOutput::None => None,
      TestMockFileOutput::Absolute {
        access_modifier: AccessModifier::Internal,
        ..
      } => Some(AccessModifier::Internal),
      TestMockFileOutput::SwiftPackage { .. }
      | TestMockFileOutput::Absolute {
        access_modifier: AccessModifier::Public,
        ..
      } => Some(AccessModifier::Public),
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ApolloCodegenConfiguration;
  use crate::templates::SchemaFileType;

  fn make_config(json: &str) -> ApolloCodegenConfiguration {
    serde_json::from_str(json).unwrap()
  }

  fn spm_config() -> ApolloCodegenConfiguration {
    make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#)
  }

  fn embedded_public_config() -> ApolloCodegenConfiguration {
    make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "MyApp", "accessModifier": "public"}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#)
  }

  fn embedded_internal_config() -> ApolloCodegenConfiguration {
    make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"embeddedInTarget": {"name": "MyApp"}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"none": {}}
      }
    }"#)
  }

  // Schema file tests

  #[test]
  fn test_schema_spm_namespace_is_public() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Namespace,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_schema_spm_member_is_public() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_schema_spm_parent_is_public() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Parent,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_schema_embedded_public_namespace() {
    let config = embedded_public_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Namespace,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_schema_embedded_public_parent_is_empty() {
    let config = embedded_public_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Parent,
    );
    assert_eq!(renderer.render(), "");
  }

  #[test]
  fn test_schema_embedded_public_member() {
    let config = embedded_public_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_schema_embedded_internal_namespace() {
    let config = embedded_internal_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Namespace,
    );
    assert_eq!(renderer.render(), "");
  }

  #[test]
  fn test_schema_embedded_internal_parent_is_empty() {
    let config = embedded_internal_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Parent,
    );
    assert_eq!(renderer.render(), "");
  }

  #[test]
  fn test_schema_embedded_internal_member() {
    let config = embedded_internal_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "");
  }

  // SPI tests

  #[test]
  fn test_spi_included_with_public() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    let result = renderer.render_with_spis(&[SPI::Internal, SPI::Unsafe]);
    assert!(result.contains("@_spi(Unsafe)"));
    assert!(result.contains("@_spi(Internal)"));
    assert!(result.contains("public "));
  }

  #[test]
  fn test_spi_omitted_with_internal() {
    let config = embedded_internal_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    let result = renderer.render_with_spis(&[SPI::Internal]);
    assert!(!result.contains("@_spi"));
    assert_eq!(result, "");
  }

  #[test]
  fn test_spi_reversed_order() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::SchemaFile(SchemaFileType::Object),
      &config,
      Scope::Member,
    );
    let result = renderer.render_with_spis(&[SPI::Internal, SPI::Unsafe]);
    // SPIs are applied in reverse order, so Unsafe wraps first, then Internal
    assert_eq!(result, "@_spi(Internal) @_spi(Unsafe) public ");
  }

  // Operation file tests

  #[test]
  fn test_operation_in_schema_module_delegates_to_schema() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::OperationFile { module_imports: None },
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_operation_relative_public() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"relative": {"accessModifier": "public"}},
        "testMocks": {"none": {}}
      }
    }"#);
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::OperationFile { module_imports: None },
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_operation_relative_internal() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"relative": {"accessModifier": "internal"}},
        "testMocks": {"none": {}}
      }
    }"#);
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::OperationFile { module_imports: None },
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "");
  }

  // Test mock file tests

  #[test]
  fn test_test_mock_none_returns_empty() {
    let config = spm_config(); // testMocks: none
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::TestMockFile,
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "");
  }

  #[test]
  fn test_test_mock_swift_package_is_public() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"swiftPackage": {"targetName": "Mocks"}}
      }
    }"#);
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::TestMockFile,
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }

  #[test]
  fn test_test_mock_absolute_internal() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"absolute": {"path": "./mocks", "accessModifier": "internal"}}
      }
    }"#);
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::TestMockFile,
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "");
  }

  // SPI Display tests

  #[test]
  fn test_spi_display() {
    assert_eq!(format!("{}", SPI::Unsafe), "Unsafe");
    assert_eq!(format!("{}", SPI::Internal), "Internal");
    assert_eq!(format!("{}", SPI::Execution), "Execution");
  }

  // Module file tests

  #[test]
  fn test_module_file_delegates_to_schema() {
    let config = spm_config();
    let renderer = AccessControlRenderer::new(
      &TemplateTarget::ModuleFile,
      &config,
      Scope::Member,
    );
    assert_eq!(renderer.render(), "public ");
  }
}
