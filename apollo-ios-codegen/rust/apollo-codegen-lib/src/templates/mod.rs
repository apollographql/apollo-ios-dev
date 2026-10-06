//! Template rendering infrastructure for Apollo iOS code generation.
//!
//! This module provides the core rendering types and traits that all schema
//! and operation templates depend on. It mirrors the Swift template infrastructure
//! from `Sources/ApolloCodegenLib/Templates/`.

pub mod access_control_renderer;
pub mod deferred_fragments_metadata_template;
pub mod fragment_template;
pub mod local_cache_mutation_definition_template;
pub mod mock_interfaces_template;
pub mod mock_object_template;
pub mod mock_unions_template;
pub mod operation_definition_template;
pub mod rendering_helpers;
pub mod schema;
pub mod selection_set_template;
pub mod swift_package_manager_module_template;

use std::path::{Path, PathBuf};

use crate::config::module_type::ModuleType;
use crate::config::output_options::OutputOptions;
use crate::config::file_output::FileOutput;
use crate::config::ApolloCodegenConfiguration;
use crate::capitalizer::Capitalizer;
use crate::pluralizer::Pluralizer;
use rendering_helpers::string_casing::first_uppercased;

pub use access_control_renderer::{AccessControlRenderer, Scope, SPI};

// MARK: - ConfigurationContext

/// Wraps `ApolloCodegenConfiguration` with a `Pluralizer` and a `Capitalizer` for template
/// rendering.
///
/// Mirrors Swift's `ApolloCodegen.ConfigurationContext` struct.
#[derive(Clone)]
pub struct ConfigurationContext {
  pub config: ApolloCodegenConfiguration,
  pub pluralizer: Pluralizer,
  pub capitalizer: Capitalizer,
  pub root_url: Option<PathBuf>,
  /// When set, all file generation output is redirected under this directory.
  /// Used in Bazel mode to write directly to a declared tree artifact,
  /// avoiding intermediate writes to the source tree.
  pub output_root: Option<PathBuf>,
}

impl ConfigurationContext {
  /// Creates a new `ConfigurationContext` from the given configuration.
  pub fn new(config: ApolloCodegenConfiguration, root_url: Option<PathBuf>) -> Self {
    let pluralizer = Pluralizer::new(config.options.additional_inflection_rules.clone());
    let capitalizer = Capitalizer::new(config.options.additional_capitalization_rules.clone());
    Self { config, pluralizer, capitalizer, root_url, output_root: None }
  }

  /// Returns the root URL for path resolution, if set.
  pub fn root_url(&self) -> Option<&Path> {
    self.root_url.as_deref()
  }

  /// Returns the output root for direct-write mode, if set.
  pub fn output_root(&self) -> Option<&Path> {
    self.output_root.as_deref()
  }

  /// Sets the output root for direct-write mode (Bazel tree artifacts).
  pub fn set_output_root(&mut self, output_root: Option<PathBuf>) {
    self.output_root = output_root;
  }

  /// Returns the schema namespace.
  /// Mirrors Swift's `ConfigurationContext.ApolloAPITargetName`: `"Apollo"` when
  /// `cocoapodsCompatibleImportStatements` is enabled, otherwise `"ApolloAPI"`.
  pub fn apollo_api_target_name(&self) -> &'static str {
    if self.config.options.cocoapods_compatible_import_statements {
      "Apollo"
    } else {
      "ApolloAPI"
    }
  }

  pub fn schema_namespace(&self) -> &str {
    &self.config.schema_namespace
  }

  /// Returns the output options.
  pub fn options(&self) -> &OutputOptions {
    &self.config.options
  }

  /// Returns the file output configuration.
  pub fn output(&self) -> &FileOutput {
    &self.config.output
  }

  /// Returns `"nonisolated "` when `markTypesNonisolated` is enabled, empty string otherwise.
  ///
  /// Mirrors Swift's `ConfigurationContext.nonisolatedModifier` (2.1.0+).
  pub fn nonisolated_modifier(&self) -> &'static str {
    if self.config.options.mark_types_nonisolated {
      "nonisolated "
    } else {
      ""
    }
  }

  /// Returns the schema module name, computing it from the module type.
  ///
  /// Mirrors Swift's `ConfigurationContext.schemaModuleName` computed property.
  pub fn schema_module_name(&self) -> String {
    match &self.config.output.schema_types.module_type {
      ModuleType::EmbeddedInTarget { name, .. } => name.clone(),
      ModuleType::SwiftPackage { .. } | ModuleType::Other => {
        first_uppercased(&self.config.schema_namespace)
      }
    }
  }
}

// MARK: - NonFatalError

/// Non-fatal errors collected during template rendering.
///
/// Mirrors Swift's `ApolloCodegen.NonFatalError` from `ApolloCodegen+Errors.swift`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NonFatalError {
  TypeNameConflict {
    name: String,
    conflicting_name: String,
    containing_object: String,
  },
}

impl NonFatalError {
  /// Returns the error type name.
  ///
  /// Mirrors Swift's `NonFatalError.errorTypeName` computed property.
  pub fn error_type_name(&self) -> &'static str {
    match self {
      NonFatalError::TypeNameConflict { .. } => "TypeNameConflict",
    }
  }

  /// Returns the failure reason.
  ///
  /// Mirrors Swift's `NonFatalError.failureReason` computed property.
  pub fn failure_reason(&self) -> String {
    match self {
      NonFatalError::TypeNameConflict {
        name,
        conflicting_name,
        containing_object,
      } => {
        format!(
          "Field '{}' conflicts with field '{}' in GraphQL definition `{}`.",
          conflicting_name, name, containing_object
        )
      }
    }
  }

  /// Returns the recovery suggestion.
  ///
  /// Mirrors Swift's `NonFatalError.recoverySuggestion` computed property.
  pub fn recovery_suggestion(&self) -> &'static str {
    match self {
      NonFatalError::TypeNameConflict { .. } => {
        "It is recommended to use a field alias for one of these fields to resolve this conflict.\nFor more info see: https://www.apollographql.com/docs/ios/troubleshooting/codegen-troubleshooting#typenameconflict"
      }
    }
  }

  /// Returns the error description.
  ///
  /// Mirrors Swift's `NonFatalError.errorDescription` computed property.
  pub fn error_description(&self) -> String {
    format!("{}: {}", self.error_type_name(), self.failure_reason())
  }
}

/// Collects non-fatal errors during rendering.
///
/// Mirrors Swift's `NonFatalError.Recorder` class.
#[derive(Debug)]
pub struct NonFatalErrorRecorder {
  errors: Vec<NonFatalError>,
}

impl NonFatalErrorRecorder {
  pub fn new() -> Self {
    Self { errors: vec![] }
  }

  pub fn record(&mut self, error: NonFatalError) {
    self.errors.push(error);
  }

  pub fn take(self) -> Vec<NonFatalError> {
    self.errors
  }
}

impl Default for NonFatalErrorRecorder {
  fn default() -> Self {
    Self::new()
  }
}

// MARK: - RenderResult

/// The result of rendering a template.
pub struct RenderResult {
  pub body: String,
  pub errors: Vec<NonFatalError>,
}

// MARK: - TemplateTarget

/// The target context for template rendering, determining import statements
/// and access control.
///
/// Mirrors Swift's `TemplateTarget` enum from `TemplateRenderer.swift`.
#[derive(Debug, Clone)]
pub enum TemplateTarget {
  /// A schema type file (object, enum, input object, etc.).
  SchemaFile(SchemaFileType),
  /// An operation file (query, mutation, subscription, fragment).
  OperationFile {
    module_imports: Option<Vec<String>>,
  },
  /// A module file (Package.swift, etc.).
  ModuleFile,
  /// A test mock file.
  TestMockFile,
}

// MARK: - SchemaFileType

/// The specific type of schema file being rendered.
///
/// Mirrors Swift's `TemplateTarget.SchemaFileType` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SchemaFileType {
  SchemaMetadata,
  SchemaConfiguration,
  Object,
  Interface,
  Union,
  Enum,
  CustomScalar,
  InputObject,
}

impl SchemaFileType {
  /// Returns the namespace component for this schema file type, if any.
  ///
  /// Mirrors Swift's `SchemaFileType.namespaceComponent` computed property.
  pub fn namespace_component(&self) -> Option<&'static str> {
    match self {
      SchemaFileType::SchemaMetadata
      | SchemaFileType::SchemaConfiguration
      | SchemaFileType::Enum
      | SchemaFileType::CustomScalar
      | SchemaFileType::InputObject => None,
      SchemaFileType::Object => Some("Objects"),
      SchemaFileType::Interface => Some("Interfaces"),
      SchemaFileType::Union => Some("Unions"),
    }
  }
}

// MARK: - HeaderCommentTemplate

/// Template for the header comment added to all generated files.
///
/// Mirrors Swift's `HeaderCommentTemplate` struct.
pub struct HeaderCommentTemplate;

impl HeaderCommentTemplate {
  /// Returns the standard generated file header comment.
  pub fn template() -> &'static str {
    "// @generated\n// This file was automatically generated and should not be edited."
  }

  /// Returns the header for editable generated files with a custom reason.
  ///
  /// Mirrors Swift's `HeaderCommentTemplate.editableFileHeader(fileCanBeEditedTo:)`.
  pub fn editable_file_header(reason: &str) -> String {
    // Format the reason as a comment (each line prefixed with "// ")
    let comment_reason: String = reason
      .lines()
      .map(|line| {
        if line.is_empty() {
          "//".to_string()
        } else {
          format!("// {}", line)
        }
      })
      .collect::<Vec<_>>()
      .join("\n");

    format!(
      "// @generated\n// This file was automatically generated and can be edited to\n{}\n//\n// Any changes to this file will not be overwritten by future\n// code generation execution.",
      comment_reason
    )
  }
}

// MARK: - ImportStatementTemplate

/// Templates for import statements in generated files.
///
/// Mirrors Swift's `ImportStatementTemplate` struct.
pub struct ImportStatementTemplate;

impl ImportStatementTemplate {
  /// Returns the import statement for a schema type file.
  ///
  /// Mirrors Swift's `ImportStatementTemplate.SchemaType.template(config:type:)`.
  /// Since 2.0.0, different schema types use different @_spi annotations.
  pub fn schema_type(
    config: &ConfigurationContext,
    file_type: &SchemaFileType,
  ) -> String {
    let _ = config; // config used for cocoapods check in Swift -- not yet needed
    match file_type {
      SchemaFileType::Enum => "@_spi(Internal) import ApolloAPI".to_string(),
      SchemaFileType::CustomScalar => "@_spi(Internal) @_spi(Execution) import ApolloAPI".to_string(),
      SchemaFileType::InputObject => "@_spi(Internal) @_spi(Unsafe) import ApolloAPI".to_string(),
      _ => "import ApolloAPI".to_string(),
    }
  }

  /// Returns the import statement for an operation file.
  ///
  /// Mirrors Swift's `ImportStatementTemplate.Operation.template(config:)`.
  /// Since 2.0.0, operation files add `@_spi(Execution) @_spi(Unsafe) import ApolloAPI`.
  pub fn operation(config: &ConfigurationContext) -> String {
    let schema_module = config.schema_module_name();
    let base_import = "@_exported import ApolloAPI\n@_spi(Execution) @_spi(Unsafe) import ApolloAPI";

    if !config.output().operations.is_in_module() {
      format!("{}\nimport {}", base_import, schema_module)
    } else {
      base_import.to_string()
    }
  }

  /// Returns the import statement for a test mock file.
  ///
  /// Mirrors Swift's `ImportStatementTemplate.TestMock.template(config:)`.
  /// Since 1.24.0, test mock files use `@testable import` for the schema module.
  ///
  /// Fork extension: when `output.testMocks` names a `baseModule` (the module that
  /// holds the shared mocks and the `MockObject` typealiases), it is imported too so
  /// that `@Field<OtherType>` references resolve across mock modules.
  pub fn test_mock(config: &ConfigurationContext) -> String {
    let schema_module = config.schema_module_name();
    let mut imports = format!("import ApolloTestSupport\n@testable import {}", schema_module);
    if let Some(base_module) = config
      .output()
      .test_mocks
      .scoping()
      .and_then(|s| s.base_module.as_deref())
    {
      imports.push_str(&format!("\nimport {}", base_module));
    }
    imports
  }
}

/// Template for module import statements within operation files.
///
/// Mirrors Swift's `ModuleImportStatementTemplate`.
pub struct ModuleImportStatementTemplate;

impl ModuleImportStatementTemplate {
  /// Returns import statements for the given module names.
  pub fn template(module_imports: &[String]) -> Option<String> {
    if module_imports.is_empty() {
      return None;
    }
    let imports: Vec<String> = module_imports
      .iter()
      .map(|m| format!("import {}", m))
      .collect();
    Some(imports.join("\n"))
  }
}

// MARK: - TemplateRenderer

/// A trait to handle the rendering of a file template based on the target file type
/// and codegen configuration.
///
/// All templates that output to a file should implement this trait. This does not include
/// templates that are used by others such as `HeaderCommentTemplate` or `ImportStatementTemplate`.
///
/// Mirrors Swift's `TemplateRenderer` protocol from `TemplateRenderer.swift`.
pub trait TemplateRenderer {
  /// Shared codegen configuration.
  fn config(&self) -> &ConfigurationContext;

  /// File target of the template.
  fn target(&self) -> TemplateTarget;

  /// Renders the body of the template. This body can be rendered within any namespace wrapping.
  fn render_body_template(
    &self,
    non_fatal_error_recorder: &NonFatalErrorRecorder,
  ) -> String;

  /// Renders the header of the template.
  /// Default implementation returns the standard header comment.
  fn render_header_template(
    &self,
    _non_fatal_error_recorder: &NonFatalErrorRecorder,
  ) -> Option<String> {
    Some(HeaderCommentTemplate::template().to_string())
  }

  /// Renders a template section that must be outside of any namespace wrapping.
  ///
  /// This section is rendered below the header and import statements and above the body
  /// and any namespace wrapper used in the template.
  fn render_detached_template(
    &self,
    _non_fatal_error_recorder: &NonFatalErrorRecorder,
  ) -> Option<String> {
    None
  }

  /// Renders the template converting all input values and generating a final String
  /// representation of the template.
  ///
  /// Returns a `RenderResult` with the body string and any non-fatal errors.
  fn render(&self) -> RenderResult {
    let error_recorder = NonFatalErrorRecorder::new();

    let body = match self.target() {
      TemplateTarget::SchemaFile(file_type) => {
        render_schema_file(self, &file_type, &error_recorder)
      }
      TemplateTarget::OperationFile { module_imports } => {
        render_operation_file(self, module_imports.as_deref(), &error_recorder)
      }
      TemplateTarget::ModuleFile => {
        render_module_file(self, &error_recorder)
      }
      TemplateTarget::TestMockFile => {
        render_test_mock_file(self, &error_recorder)
      }
    };

    RenderResult {
      body,
      errors: error_recorder.take(),
    }
  }

  /// Convenience method to create an `AccessControlRenderer` for the given scope.
  fn access_control_renderer(&self, scope: Scope) -> AccessControlRenderer {
    AccessControlRenderer::new(
      &self.target(),
      &self.config().config,
      scope,
    )
  }
}

// MARK: - Private render methods

/// Renders a schema file with namespace wrapping.
///
/// Mirrors Swift's `renderSchemaFile(_:_:)` private method.
fn render_schema_file<T: TemplateRenderer + ?Sized>(
  renderer: &T,
  file_type: &SchemaFileType,
  error_recorder: &NonFatalErrorRecorder,
) -> String {
  let namespace: Option<String> = {
    if matches!(file_type, SchemaFileType::SchemaConfiguration) {
      None
    } else {
      let use_schema_namespace = !renderer.config().output().schema_types.is_in_module();
      match (use_schema_namespace, file_type.namespace_component()) {
        (false, None) => None,
        (true, None) => Some(first_uppercased(renderer.config().schema_namespace())),
        (false, Some(schema_type_ns)) => Some(schema_type_ns.to_string()),
        (true, Some(schema_type_ns)) => {
          Some(format!(
            "{}.{}",
            first_uppercased(renderer.config().schema_namespace()),
            schema_type_ns
          ))
        }
      }
    }
  };

  let mut result = String::new();

  if let Some(header) = renderer.render_header_template(error_recorder) {
    result.push_str(&header);
    result.push('\n');
    result.push('\n');
  }

  result.push_str(&ImportStatementTemplate::schema_type(renderer.config(), file_type));
  result.push('\n');

  if let Some(detached) = renderer.render_detached_template(error_recorder) {
    result.push('\n');
    result.push_str(&detached);
    result.push('\n');
  }

  result.push('\n');

  let body = renderer.render_body_template(error_recorder);

  if let Some(ns) = namespace {
    let access_modifier = renderer.access_control_renderer(Scope::Namespace).render();
    result.push_str(&wrap_in_namespace(&body, &ns, &access_modifier));
  } else {
    result.push_str(&body);
  }

  result
}

/// Renders an operation file with optional namespace wrapping.
///
/// Mirrors Swift's `renderOperationFile(_:_:)` private method.
fn render_operation_file<T: TemplateRenderer + ?Sized>(
  renderer: &T,
  module_imports: Option<&[String]>,
  error_recorder: &NonFatalErrorRecorder,
) -> String {
  let mut result = String::new();

  if let Some(header) = renderer.render_header_template(error_recorder) {
    result.push_str(&header);
    result.push('\n');
    result.push('\n');
  }

  result.push_str(&ImportStatementTemplate::operation(renderer.config()));

  if let Some(imports) = module_imports {
    if let Some(module_import_str) = ModuleImportStatementTemplate::template(imports) {
      result.push('\n');
      result.push_str(&module_import_str);
    }
  }

  result.push('\n');
  result.push('\n');

  let body = renderer.render_body_template(error_recorder);

  let config = renderer.config();
  if config.output().operations.is_in_module() && !config.output().schema_types.is_in_module() {
    let ns = first_uppercased(config.schema_namespace());
    let access_modifier = renderer.access_control_renderer(Scope::Namespace).render();
    result.push_str(&wrap_in_namespace(&body, &ns, &access_modifier));
  } else {
    result.push_str(&body);
  }

  result
}

/// Renders a module file (header + body, no imports).
///
/// Mirrors Swift's `renderModuleFile(_:)` private method.
fn render_module_file<T: TemplateRenderer + ?Sized>(
  renderer: &T,
  error_recorder: &NonFatalErrorRecorder,
) -> String {
  let mut result = String::new();

  if let Some(header) = renderer.render_header_template(error_recorder) {
    result.push_str(&header);
    result.push('\n');
    result.push('\n');
  }

  result.push_str(&renderer.render_body_template(error_recorder));

  result
}

/// Renders a test mock file with test-specific imports.
///
/// Mirrors Swift's `renderTestMockFile(_:)` private method.
fn render_test_mock_file<T: TemplateRenderer + ?Sized>(
  renderer: &T,
  error_recorder: &NonFatalErrorRecorder,
) -> String {
  let mut result = String::new();

  if let Some(header) = renderer.render_header_template(error_recorder) {
    result.push_str(&header);
    result.push('\n');
    result.push('\n');
  }

  result.push_str(&ImportStatementTemplate::test_mock(renderer.config()));
  result.push('\n');
  result.push('\n');
  result.push_str(&renderer.render_body_template(error_recorder));

  result
}

// MARK: - Namespace wrapping

/// Wraps the body in a namespace extension.
///
/// Mirrors Swift's `TemplateString.wrappedInNamespace(_:accessModifier:)`.
pub fn wrap_in_namespace(body: &str, namespace: &str, access_modifier: &str) -> String {
  // Indent each non-empty line of the body by 2 spaces
  let mut indented: Vec<String> = body
    .lines()
    .map(|line| {
      // Like TemplateString.joinedAsLines: only strictly empty lines stay unindented.
      if line.is_empty() {
        String::new()
      } else {
        format!("  {}", line)
      }
    })
    .collect();

  // If the body ends with a newline, preserve it as a trailing blank line
  // (mirrors Swift's TemplateString behavior where a trailing newline in the
  // wrapped body becomes a blank line before the closing brace)
  if body.ends_with('\n') {
    indented.push(String::new());
  }

  format!(
    "{}extension {} {{\n{}\n}}",
    access_modifier,
    namespace,
    indented.join("\n")
  )
}

#[cfg(test)]
mod tests {
  use super::*;

  fn make_config(json: &str) -> ConfigurationContext {
    let config: ApolloCodegenConfiguration = serde_json::from_str(json).unwrap();
    ConfigurationContext::new(config, None)
  }

  fn spm_config() -> ConfigurationContext {
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

  fn embedded_config() -> ConfigurationContext {
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

  #[test]
  fn test_schema_module_name_spm() {
    let config = spm_config();
    assert_eq!(config.schema_module_name(), "MySchema");
  }

  #[test]
  fn test_schema_module_name_embedded() {
    let config = embedded_config();
    assert_eq!(config.schema_module_name(), "MyApp");
  }

  #[test]
  fn test_header_comment_template() {
    let header = HeaderCommentTemplate::template();
    assert!(header.contains("@generated"));
    assert!(header.contains("should not be edited"));
  }

  #[test]
  fn test_editable_file_header() {
    let header = HeaderCommentTemplate::editable_file_header("Custom reason");
    assert!(header.contains("@generated"));
    assert!(header.contains("can be edited"));
    assert!(header.contains("Custom reason"));
  }

  #[test]
  fn test_schema_file_type_namespace_component() {
    assert_eq!(SchemaFileType::Object.namespace_component(), Some("Objects"));
    assert_eq!(SchemaFileType::Interface.namespace_component(), Some("Interfaces"));
    assert_eq!(SchemaFileType::Union.namespace_component(), Some("Unions"));
    assert_eq!(SchemaFileType::Enum.namespace_component(), None);
    assert_eq!(SchemaFileType::CustomScalar.namespace_component(), None);
    assert_eq!(SchemaFileType::InputObject.namespace_component(), None);
    assert_eq!(SchemaFileType::SchemaMetadata.namespace_component(), None);
    assert_eq!(SchemaFileType::SchemaConfiguration.namespace_component(), None);
  }

  #[test]
  fn test_import_statement_schema_type_default() {
    let config = spm_config();
    let import = ImportStatementTemplate::schema_type(&config, &SchemaFileType::Object);
    assert_eq!(import, "import ApolloAPI");
  }

  #[test]
  fn test_import_statement_schema_type_input_object() {
    let config = spm_config();
    let import = ImportStatementTemplate::schema_type(&config, &SchemaFileType::InputObject);
    assert_eq!(import, "@_spi(Internal) @_spi(Unsafe) import ApolloAPI");
  }

  #[test]
  fn test_import_statement_schema_type_custom_scalar() {
    let config = spm_config();
    let import = ImportStatementTemplate::schema_type(&config, &SchemaFileType::CustomScalar);
    assert_eq!(import, "@_spi(Internal) @_spi(Execution) import ApolloAPI");
  }

  #[test]
  fn test_import_statement_schema_type_enum() {
    let config = spm_config();
    let import = ImportStatementTemplate::schema_type(&config, &SchemaFileType::Enum);
    assert_eq!(import, "@_spi(Internal) import ApolloAPI");
  }

  #[test]
  fn test_import_statement_operation_in_schema_module() {
    let config = spm_config();
    let import = ImportStatementTemplate::operation(&config);
    // operations are in schema module, so no separate import
    assert!(!import.contains("import MySchema"));
  }

  #[test]
  fn test_import_statement_operation_separate_module() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"relative": {}},
        "testMocks": {"none": {}}
      }
    }"#);
    let import = ImportStatementTemplate::operation(&config);
    assert!(import.contains("import MySchema"));
  }

  #[test]
  fn test_import_statement_test_mock() {
    let config = spm_config();
    let import = ImportStatementTemplate::test_mock(&config);
    assert!(import.contains("import ApolloTestSupport"));
    assert!(import.contains("@testable import MySchema"));
  }

  #[test]
  fn test_import_statement_test_mock_with_base_module() {
    let config = make_config(r#"{
      "schemaNamespace": "mySchema",
      "input": {},
      "output": {
        "schemaTypes": { "path": "./gen", "moduleType": {"swiftPackageManager": {}} },
        "operations": {"inSchemaModule": {}},
        "testMocks": {"swiftPackage": {"targetName": "AccountMocks", "baseModule": "BaseMocks"}}
      }
    }"#);
    assert_eq!(
      ImportStatementTemplate::test_mock(&config),
      "import ApolloTestSupport\n@testable import MySchema\nimport BaseMocks"
    );
  }

  #[test]
  fn test_module_import_statement_empty() {
    assert_eq!(ModuleImportStatementTemplate::template(&[]), None);
  }

  #[test]
  fn test_module_import_statement_single() {
    let result = ModuleImportStatementTemplate::template(&["Foundation".to_string()]);
    assert_eq!(result, Some("import Foundation".to_string()));
  }

  #[test]
  fn test_module_import_statement_multiple() {
    let result = ModuleImportStatementTemplate::template(&[
      "Foundation".to_string(),
      "UIKit".to_string(),
    ]);
    assert_eq!(result, Some("import Foundation\nimport UIKit".to_string()));
  }

  #[test]
  fn test_non_fatal_error_recorder() {
    let recorder = NonFatalErrorRecorder::new();
    let errors = recorder.take();
    assert!(errors.is_empty());
  }

  #[test]
  fn test_wrap_in_namespace_basic() {
    let result = wrap_in_namespace("struct Foo {}", "MyNamespace", "public ");
    assert!(result.contains("public extension MyNamespace {"));
    assert!(result.contains("  struct Foo {}"));
    assert!(result.ends_with("}"));
  }

  #[test]
  fn test_wrap_in_namespace_no_access_modifier() {
    let result = wrap_in_namespace("struct Foo {}", "MyNamespace", "");
    assert!(result.starts_with("extension MyNamespace {"));
  }

  #[test]
  fn test_wrap_in_namespace_multiline_body() {
    let body = "struct Foo {\n  let x: Int\n}";
    let result = wrap_in_namespace(body, "NS", "public ");
    assert!(result.contains("  struct Foo {"));
    assert!(result.contains("    let x: Int"));
    assert!(result.contains("  }"));
  }

  // TemplateRenderer trait tests using a mock implementation
  struct MockTemplate {
    config: ConfigurationContext,
    target: TemplateTarget,
    body: String,
  }

  impl TemplateRenderer for MockTemplate {
    fn config(&self) -> &ConfigurationContext {
      &self.config
    }

    fn target(&self) -> TemplateTarget {
      self.target.clone()
    }

    fn render_body_template(
      &self,
      _non_fatal_error_recorder: &NonFatalErrorRecorder,
    ) -> String {
      self.body.clone()
    }
  }

  #[test]
  fn test_template_renderer_module_file() {
    let config = spm_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::ModuleFile,
      body: "// module body".to_string(),
    };
    let result = template.render();
    assert!(result.body.contains("@generated"));
    assert!(result.body.contains("// module body"));
    assert!(result.errors.is_empty());
  }

  #[test]
  fn test_template_renderer_schema_file_spm_object() {
    let config = spm_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::SchemaFile(SchemaFileType::Object),
      body: "struct MyObject {}".to_string(),
    };
    let result = template.render();
    assert!(result.body.contains("@generated"));
    assert!(result.body.contains("import ApolloAPI"));
    // SPM schemas are in a module, so namespace component is used without schema namespace
    assert!(result.body.contains("extension Objects {"));
    assert!(result.body.contains("  struct MyObject {}"));
  }

  #[test]
  fn test_template_renderer_schema_file_embedded_object() {
    let config = embedded_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::SchemaFile(SchemaFileType::Object),
      body: "struct MyObject {}".to_string(),
    };
    let result = template.render();
    // Embedded target is not in a module, so schema namespace is used
    assert!(result.body.contains("MySchema.Objects"));
  }

  #[test]
  fn test_template_renderer_test_mock_file() {
    let config = spm_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::TestMockFile,
      body: "// mock body".to_string(),
    };
    let result = template.render();
    assert!(result.body.contains("@generated"));
    assert!(result.body.contains("import ApolloTestSupport"));
    assert!(result.body.contains("@testable import MySchema"));
    assert!(result.body.contains("// mock body"));
  }

  #[test]
  fn test_template_renderer_operation_file() {
    let config = spm_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::OperationFile { module_imports: None },
      body: "class MyQuery {}".to_string(),
    };
    let result = template.render();
    assert!(result.body.contains("@generated"));
    assert!(result.body.contains("@_exported import ApolloAPI"));
    assert!(result.body.contains("class MyQuery {}"));
  }

  #[test]
  fn test_template_renderer_schema_configuration_no_namespace() {
    let config = spm_config();
    let template = MockTemplate {
      config,
      target: TemplateTarget::SchemaFile(SchemaFileType::SchemaConfiguration),
      body: "enum SchemaConfig {}".to_string(),
    };
    let result = template.render();
    // SchemaConfiguration should NOT be wrapped in a namespace
    assert!(!result.body.contains("extension"));
    assert!(result.body.contains("enum SchemaConfig {}"));
  }
}
