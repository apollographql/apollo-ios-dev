use serde::{Deserialize, Serialize};

/// Configures rules for how to convert the names of values from the schema in generated code.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.ConversionStrategies` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversionStrategies {
    /// Determines how the names of enum cases in the GraphQL schema will be converted into
    /// cases on the generated Swift enums.
    /// Defaults to `CamelCase`.
    #[serde(default = "default_enum_cases")]
    pub enum_cases: EnumCases,

    /// Determines how the names of fields in the GraphQL schema will be converted into
    /// properties in the generated Swift code.
    /// Defaults to `Idiomatic`.
    #[serde(default = "default_field_accessors")]
    pub field_accessors: FieldAccessors,

    /// Determines how the names of input objects in the GraphQL schema will be converted into
    /// the generated Swift code.
    /// Defaults to `CamelCase`.
    #[serde(default = "default_input_objects")]
    pub input_objects: InputObjects,
}

impl Default for ConversionStrategies {
    fn default() -> Self {
        Self {
            enum_cases: EnumCases::CamelCase,
            field_accessors: FieldAccessors::Idiomatic,
            input_objects: InputObjects::CamelCase,
        }
    }
}

fn default_enum_cases() -> EnumCases {
    EnumCases::CamelCase
}

fn default_field_accessors() -> FieldAccessors {
    FieldAccessors::Idiomatic
}

fn default_input_objects() -> InputObjects {
    InputObjects::CamelCase
}

/// Strategy used to convert the casing of enum cases in a GraphQL schema
/// into generated Swift code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EnumCases {
    /// Generates Swift code using the exact name provided in the GraphQL schema
    /// performing no conversion.
    None,
    /// Convert to lower camel case from `snake_case`, `UpperCamelCase`, or `UPPERCASE`.
    CamelCase,
}

/// Strategy used to convert the casing of fields on GraphQL selection sets into field accessors
/// on the response models in generated Swift code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FieldAccessors {
    /// Lowercase the first letter of all fields. Convert all-UPPERCASE to all-lowercase.
    Idiomatic,
    /// Convert to `lowerCamelCase` from `snake_case`, or `UpperCamelCase`.
    CamelCase,
}

/// Strategy used to convert the casing of input objects in a GraphQL schema
/// into generated Swift code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputObjects {
    /// Generates Swift code using the exact name provided in the GraphQL schema
    /// performing no conversion.
    None,
    /// Convert to lower camel case from `snake_case`, `UpperCamelCase`, or `UPPERCASE`.
    CamelCase,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_conversion_strategies_default() {
        let cs = ConversionStrategies::default();
        assert_eq!(cs.enum_cases, EnumCases::CamelCase);
        assert_eq!(cs.field_accessors, FieldAccessors::Idiomatic);
        assert_eq!(cs.input_objects, InputObjects::CamelCase);
    }

    #[test]
    fn test_conversion_strategies_roundtrip() {
        let cs = ConversionStrategies {
            enum_cases: EnumCases::None,
            field_accessors: FieldAccessors::CamelCase,
            input_objects: InputObjects::None,
        };
        let json = serde_json::to_string(&cs).unwrap();
        let parsed: ConversionStrategies = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, cs);
    }

    #[test]
    fn test_conversion_strategies_partial_defaults() {
        let json = r#"{"enumCases": "none"}"#;
        let parsed: ConversionStrategies = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.enum_cases, EnumCases::None);
        assert_eq!(parsed.field_accessors, FieldAccessors::Idiomatic);
        assert_eq!(parsed.input_objects, InputObjects::CamelCase);
    }

    #[test]
    fn test_enum_cases_roundtrip() {
        assert_eq!(
            serde_json::to_string(&EnumCases::CamelCase).unwrap(),
            r#""camelCase""#
        );
        assert_eq!(
            serde_json::to_string(&EnumCases::None).unwrap(),
            r#""none""#
        );
    }
}
