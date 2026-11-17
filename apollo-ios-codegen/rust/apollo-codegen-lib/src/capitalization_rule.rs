use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Mirrors Swift's `CapitalizationRule` struct from `Sources/ApolloCodegenLib/Capitalizer.swift`.
///
/// A rule that defines how a specific term should be capitalized in generated Swift code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapitalizationRule {
    /// The term to search for within generated names.
    pub term: Term,
    /// The capitalization strategy to apply when the term is matched.
    pub strategy: CaseStrategy,
}

/// The term to match within generated names.
///
/// Mirrors Swift's `CapitalizationRule.Term`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Term {
    /// Match a whole camelCase word segment, compared case-insensitively.
    String(String),
    /// Match a regular expression against an individual camelCase word segment.
    /// The pattern is not anchored.
    Regex(String),
}

/// The capitalization strategy to apply when a term is matched.
///
/// Mirrors Swift's `CapitalizationRule.CaseStrategy`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CaseStrategy {
    /// Uppercase the matched segment (only when its first character is already uppercase).
    Upper,
    /// Lowercase the matched segment.
    Lower,
    /// Replace the matched segment with an exact literal string.
    Replace(String),
}

// MARK: - Serde: CapitalizationRule

impl Serialize for CapitalizationRule {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(2))?;
        map.serialize_entry("term", &self.term)?;
        map.serialize_entry("strategy", &self.strategy)?;
        map.end()
    }
}

impl<'de> Deserialize<'de> for CapitalizationRule {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        struct Raw {
            term: Term,
            strategy: CaseStrategy,
        }
        let raw = Raw::deserialize(deserializer)?;
        Ok(CapitalizationRule {
            term: raw.term,
            strategy: raw.strategy,
        })
    }
}

// MARK: - Serde: Term
//
// Swift decodes a keyed container: if a `string` key is present the term is `.string`,
// otherwise if a `regex` key is present it is `.regex`, otherwise decoding fails.

impl Serialize for Term {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(1))?;
        match self {
            Term::String(value) => map.serialize_entry("string", value)?,
            Term::Regex(value) => map.serialize_entry("regex", value)?,
        }
        map.end()
    }
}

impl<'de> Deserialize<'de> for Term {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct TermVisitor;

        impl<'de> Visitor<'de> for TermVisitor {
            type Value = Term;

            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("a CapitalizationRule.Term object with a 'string' or 'regex' key")
            }

            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut string: Option<String> = None;
                let mut regex: Option<String> = None;
                while let Some(key) = map.next_key::<String>()? {
                    match key.as_str() {
                        "string" => string = Some(map.next_value()?),
                        "regex" => regex = Some(map.next_value()?),
                        _ => {
                            let _: serde_json::Value = map.next_value()?;
                        }
                    }
                }
                if let Some(value) = string {
                    Ok(Term::String(value))
                } else if let Some(value) = regex {
                    Ok(Term::Regex(value))
                } else {
                    Err(de::Error::custom(
                        "CapitalizationRule.Term expects a 'string' or 'regex' key.",
                    ))
                }
            }
        }

        deserializer.deserialize_map(TermVisitor)
    }
}

// MARK: - Serde: CaseStrategy
//
// Swift accepts the single string form (`"upper"` / `"lower"`) or the keyed object form
// `{"replace": "<string>"}`.

impl Serialize for CaseStrategy {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            CaseStrategy::Upper => serializer.serialize_str("upper"),
            CaseStrategy::Lower => serializer.serialize_str("lower"),
            CaseStrategy::Replace(replacement) => {
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry("replace", replacement)?;
                map.end()
            }
        }
    }
}

impl<'de> Deserialize<'de> for CaseStrategy {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        const EXPECTED: &str =
            r#"CaseStrategy expects "upper", "lower", or {"replace": <string>}."#;

        let value = serde_json::Value::deserialize(deserializer)?;
        match &value {
            serde_json::Value::String(raw) => match raw.as_str() {
                "upper" => Ok(CaseStrategy::Upper),
                "lower" => Ok(CaseStrategy::Lower),
                _ => Err(de::Error::custom(EXPECTED)),
            },
            serde_json::Value::Object(map) => match map.get("replace") {
                Some(serde_json::Value::String(replacement)) => {
                    Ok(CaseStrategy::Replace(replacement.clone()))
                }
                _ => Err(de::Error::custom(EXPECTED)),
            },
            _ => Err(de::Error::custom(EXPECTED)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deserialize_rules() {
        let json = r#"[
      {"term":{"string":"id"},"strategy":"lower"},
      {"term":{"regex":"^Details$"},"strategy":"upper"},
      {"term":{"string":"query"},"strategy":{"replace":"Qry"}}
    ]"#;
        let rules: Vec<CapitalizationRule> = serde_json::from_str(json).unwrap();
        assert_eq!(
            rules,
            vec![
                CapitalizationRule {
                    term: Term::String("id".into()),
                    strategy: CaseStrategy::Lower
                },
                CapitalizationRule {
                    term: Term::Regex("^Details$".into()),
                    strategy: CaseStrategy::Upper
                },
                CapitalizationRule {
                    term: Term::String("query".into()),
                    strategy: CaseStrategy::Replace("Qry".into())
                },
            ]
        );
    }

    #[test]
    fn test_deserialize_invalid_term_and_strategy() {
        assert!(serde_json::from_str::<CapitalizationRule>(
            r#"{"term":{"other":"id"},"strategy":"lower"}"#
        )
        .is_err());
        assert!(serde_json::from_str::<CapitalizationRule>(
            r#"{"term":{"string":"id"},"strategy":"title"}"#
        )
        .is_err());
    }

    #[test]
    fn test_serialize_round_trip() {
        let rules = vec![
            CapitalizationRule {
                term: Term::String("id".into()),
                strategy: CaseStrategy::Upper,
            },
            CapitalizationRule {
                term: Term::Regex("^Details$".into()),
                strategy: CaseStrategy::Replace("DETAILS".into()),
            },
        ];
        let json = serde_json::to_string(&rules).unwrap();
        assert_eq!(
            json,
            r#"[{"term":{"string":"id"},"strategy":"upper"},{"term":{"regex":"^Details$"},"strategy":{"replace":"DETAILS"}}]"#
        );
        let back: Vec<CapitalizationRule> = serde_json::from_str(&json).unwrap();
        assert_eq!(back, rules);
    }
}
