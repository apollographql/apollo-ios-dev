use serde::Deserialize;

use super::conversion_strategies::EnumCases;
use super::operation_document_format::OperationDocumentFormat;

/// Legacy APQ configuration enum.
///
/// Used during deserialization to migrate from legacy `apqs` key to `operationDocumentFormat`.
/// Mirrors Swift's `ApolloCodegenConfiguration.APQConfig` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum APQConfig {
  /// The default value. Disables APQs.
  Disabled,
  /// Automatically persists operations using Apollo Server/Router's APQs.
  AutomaticallyPersist,
  /// Provides only the operationIdentifier for previously persisted operations.
  PersistedOperationsOnly,
}

impl From<APQConfig> for OperationDocumentFormat {
  fn from(apq: APQConfig) -> Self {
    match apq {
      APQConfig::Disabled => OperationDocumentFormat::DEFINITION,
      APQConfig::AutomaticallyPersist => {
        OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
      }
      APQConfig::PersistedOperationsOnly => OperationDocumentFormat::OPERATION_ID,
    }
  }
}

/// Legacy case conversion strategy enum.
///
/// Used during deserialization to migrate from legacy `CaseConversionStrategy` to `EnumCases`.
/// Mirrors Swift's `ApolloCodegenConfiguration.ConversionStrategies.CaseConversionStrategy`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CaseConversionStrategy {
  None,
  CamelCase,
}

impl From<CaseConversionStrategy> for EnumCases {
  fn from(strategy: CaseConversionStrategy) -> Self {
    match strategy {
      CaseConversionStrategy::None => EnumCases::None,
      CaseConversionStrategy::CamelCase => EnumCases::CamelCase,
    }
  }
}

/// Legacy query string literal format enum.
///
/// Accepted during deserialization but unused. Query strings are now always in single line format.
/// Mirrors Swift's `ApolloCodegenConfiguration.OutputOptions.QueryStringLiteralFormat`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum QueryStringLiteralFormat {
  SingleLine,
  Multiline,
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::operation_document_format::OperationDocumentFormat;

  #[test]
  fn test_apq_disabled_maps_to_definition() {
    let format: OperationDocumentFormat = APQConfig::Disabled.into();
    assert_eq!(format, OperationDocumentFormat::DEFINITION);
  }

  #[test]
  fn test_apq_automatically_persist_maps_to_both() {
    let format: OperationDocumentFormat = APQConfig::AutomaticallyPersist.into();
    assert_eq!(
      format,
      OperationDocumentFormat::DEFINITION | OperationDocumentFormat::OPERATION_ID
    );
  }

  #[test]
  fn test_apq_persisted_only_maps_to_operation_id() {
    let format: OperationDocumentFormat = APQConfig::PersistedOperationsOnly.into();
    assert_eq!(format, OperationDocumentFormat::OPERATION_ID);
  }

  #[test]
  fn test_apq_config_deserialize() {
    let json = r#""disabled""#;
    let parsed: APQConfig = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, APQConfig::Disabled);

    let json = r#""automaticallyPersist""#;
    let parsed: APQConfig = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, APQConfig::AutomaticallyPersist);

    let json = r#""persistedOperationsOnly""#;
    let parsed: APQConfig = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, APQConfig::PersistedOperationsOnly);
  }

  #[test]
  fn test_case_conversion_strategy_deserialize() {
    let json = r#""none""#;
    let parsed: CaseConversionStrategy = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, CaseConversionStrategy::None);

    let json = r#""camelCase""#;
    let parsed: CaseConversionStrategy = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, CaseConversionStrategy::CamelCase);
  }
}
