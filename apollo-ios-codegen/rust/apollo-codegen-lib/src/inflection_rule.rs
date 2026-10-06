use serde::{Deserialize, Serialize};

/// Mirrors Swift's `InflectionRule` enum from `Sources/ApolloCodegenLib/Pluralizer.swift`.
///
/// The types of inflection rules that can be used to customize pluralization.
///
/// Swift's `InflectionRule` relies on the synthesized `Codable` conformance for an enum with
/// associated values, which is externally tagged by case name:
/// `{"pluralization": {"singularRegex": "...", "replacementRegex": "..."}}`,
/// `{"irregular": {"singular": "...", "plural": "..."}}`, `{"uncountable": {"word": "..."}}`.
/// serde's default enum representation produces exactly that shape.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum InflectionRule {
  /// A pluralization rule that allows taking a singular word and pluralizing it.
  /// - `singular_regex`: A regular expression representing the single version of the word
  /// - `replacement_regex`: A regular expression representing how to replace the singular version.
  #[serde(rename = "pluralization")]
  Pluralization {
    #[serde(rename = "singularRegex")]
    singular_regex: String,
    #[serde(rename = "replacementRegex")]
    replacement_regex: String,
  },

  /// A singularization rule that allows taking a plural word and singularizing it.
  /// - `plural_regex`: A regular expression representing the plural version of the word
  /// - `replacement_regex`: A regular expression representing how to replace the singular version.
  #[serde(rename = "singularization")]
  Singularization {
    #[serde(rename = "pluralRegex")]
    plural_regex: String,
    #[serde(rename = "replacementRegex")]
    replacement_regex: String,
  },

  /// A definition of an irregular pluralization rule not easily captured by regex -
  /// for example "person" and "people".
  /// - `singular`: The singular version of the word
  /// - `plural`: The plural version of the word.
  #[serde(rename = "irregular")]
  Irregular {
    singular: String,
    plural: String,
  },

  /// A definition of a word that should never be pluralized or de-pluralized because
  /// it's the same no matter what the count - for example, "fish".
  /// - `word`: The word that should never be adjusted.
  #[serde(rename = "uncountable")]
  Uncountable {
    word: String,
  },
}
