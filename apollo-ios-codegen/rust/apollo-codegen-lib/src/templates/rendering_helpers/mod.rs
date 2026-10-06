//! Rendering helper modules for code generation templates.
//!
//! These modules provide the string manipulation, type rendering,
//! and utility functions used across all template implementations.

pub mod composite_type_namespace;
pub mod computed_selection_set_iterators;
pub mod field_argument_rendering;
pub mod for_each_in;
pub mod graphql_input_field_rendered;
pub mod graphql_name_rendering;
pub mod graphql_type_rendered;
pub mod input_variable_renderable;
pub mod ir_definition_rendering;
pub mod operation_template_renderer;
pub mod selection_set_initializer_check;
pub mod selection_set_name_generator;
pub mod string_casing;
pub mod string_single_line;
pub mod string_swift_name_escaping;
pub mod template_constants;
pub mod template_string_deprecation;
pub mod template_string_documentation;

// Re-exports for convenience
pub use composite_type_namespace::schema_types_namespace;
pub use computed_selection_set_iterators::SelectionsIterator;
pub use field_argument_rendering::render_input_value_literal;
pub use graphql_input_field_rendered::render_input_value_type;
pub use graphql_name_rendering::{
    is_swift_type, render_enum_value, render_input_field, render_named_type,
};
pub use graphql_type_rendered::rendered as render_graphql_type;
pub use input_variable_renderable::render_variable_default_value;
pub use ir_definition_rendering::{
    generated_definition_name, generated_definition_name_capitalized,
    generated_fragment_definition_name, generated_fragment_definition_name_capitalized,
    generated_fragment_file_name, rendered_selection_set_type,
};
pub use operation_template_renderer::{
    render_initializer, render_variable_accessors, render_variable_properties,
};
pub use selection_set_initializer_check::should_generate_selection_set_initializers;
pub use string_casing::{first_lowercased, first_uppercased, is_all_uppercased};
pub use string_single_line::converted_to_single_line;
pub use string_swift_name_escaping::{
    as_enum_case_name, as_fragment_name, as_normalized_fragment_name, as_selection_set_name,
    as_test_mock_field_property_name, as_test_mock_initializer_parameter_name,
    convert_to_camel_case, escape_if, escaped_swift_string_special_characters,
    is_conflicting_test_mock_field_name, render_as_field_property_name,
    render_as_initializer_parameter_accessor_name, render_as_initializer_parameter_name,
    render_as_test_mock_field_property_name,
};
pub use template_constants::APOLLO_API_TARGET_NAME;
pub use template_string_deprecation::{render_deprecation_reason, render_field_argument_warning};
pub use template_string_documentation::render_documentation;
