//! Schema type templates for Apollo iOS code generation.
//!
//! Each module contains a template struct implementing `TemplateRenderer`
//! that produces Swift code for a specific schema type.

pub mod object_template;
pub mod interface_template;
pub mod union_template;
pub mod enum_template;
pub mod custom_scalar_template;
pub mod schema_module_namespace_template;
pub mod input_object_template;
pub mod one_of_input_object_template;
pub mod schema_metadata_template;
pub mod schema_configuration_template;
