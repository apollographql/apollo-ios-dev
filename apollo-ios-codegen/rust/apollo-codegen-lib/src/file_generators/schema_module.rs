//! File generator for schema module files (Package.swift or namespace file).
//!
//! Mirrors Swift's `SchemaModuleFileGenerator` from
//! `Sources/ApolloCodegenLib/FileGenerators/SchemaModuleFileGenerator.swift`.

use std::path::Path;

use crate::config::module_type::ModuleType;
use crate::templates::rendering_helpers::string_casing::first_uppercased;
use crate::templates::schema::schema_module_namespace_template::SchemaModuleNamespaceTemplate;
use crate::templates::swift_package_manager_module_template::SwiftPackageManagerModuleTemplate;
use crate::templates::{ConfigurationContext, NonFatalError, TemplateRenderer};

use super::file_manager::ApolloFileManager;

/// Resolves a path string against an optional root URL (duplicated from mod.rs for encapsulation).
fn resolve_url(path: &str, root_url: Option<&Path>) -> std::path::PathBuf {
    let p = std::path::PathBuf::from(path);
    if p.is_absolute() {
        p
    } else if let Some(root) = root_url {
        root.join(path)
    } else {
        p
    }
}

/// Generates a module file for the chosen dependency manager.
///
/// This is NOT a `FileGenerator` trait implementor -- it has its own `generate()` method
/// that handles the different module types directly.
///
/// Mirrors Swift's `SchemaModuleFileGenerator` struct.
pub struct SchemaModuleFileGenerator;

impl SchemaModuleFileGenerator {
    /// Generates the appropriate module file based on the configured module type.
    ///
    /// - `SwiftPackageManager`: Generates `Package.swift` using `SwiftPackageManagerModuleTemplate`
    /// - `EmbeddedInTarget`: Generates `{Namespace}.graphql.swift` using `SchemaModuleNamespaceTemplate`
    /// - `Other`: No-op (module is managed externally)
    pub fn generate(
        config: &ConfigurationContext,
        file_manager: &ApolloFileManager,
    ) -> Result<Vec<NonFatalError>, std::io::Error> {
        let path_base = resolve_url(&config.output().schema_types.path, config.root_url());

        match &config.output().schema_types.module_type {
            ModuleType::SwiftPackage { .. } => {
                let file_path = path_base.join("Package.swift");
                let result = SwiftPackageManagerModuleTemplate::new(
                    config.output().test_mocks.clone(),
                    config.clone(),
                )
                .render();
                file_manager.create_file(&file_path, result.body.as_bytes(), true)?;
                Ok(result.errors)
            }
            ModuleType::EmbeddedInTarget { .. } => {
                let filename = format!(
                    "{}.graphql.swift",
                    first_uppercased(config.schema_namespace())
                );
                let file_path = path_base.join(&filename);
                let result = SchemaModuleNamespaceTemplate {
                    config: config.clone(),
                }
                .render();
                file_manager.create_file(&file_path, result.body.as_bytes(), true)?;
                Ok(result.errors)
            }
            ModuleType::Other => {
                // No-op -- the implementation is import statements in the generated operation files.
                Ok(vec![])
            }
        }
    }
}
