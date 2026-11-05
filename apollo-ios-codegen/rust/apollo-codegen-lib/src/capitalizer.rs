use regex::Regex;

use crate::capitalization_rule::{CapitalizationRule, CaseStrategy, Term};

/// Mirrors Swift's `Capitalizer` struct from `Sources/ApolloCodegenLib/Capitalizer.swift`.
///
/// Applies `CapitalizationRule`s to generated Swift names. The capitalizer splits camelCase
/// strings into word segments, matches each segment against the configured rules, applies the
/// appropriate capitalization strategy, and recombines the segments.
#[derive(Clone, Debug, Default)]
pub struct Capitalizer {
    rules: Vec<CapitalizationRule>,
    /// Compiled regexes, parallel to `rules`. `None` for string terms and for patterns that do
    /// not compile (Swift's `try? NSRegularExpression(...)` yields no match in that case).
    regexes: Vec<Option<Regex>>,
}

impl Capitalizer {
    /// Creates a new `Capitalizer` with the given rules.
    pub fn new(rules: Vec<CapitalizationRule>) -> Self {
        let regexes = rules
            .iter()
            .map(|rule| match &rule.term {
                Term::Regex(pattern) => Regex::new(pattern).ok(),
                Term::String(_) => None,
            })
            .collect();
        Self { rules, regexes }
    }

    /// Applies all capitalization rules to the given string.
    ///
    /// The string is split into camelCase word segments. Each segment is checked against the
    /// rules in order. If a rule matches, the segment is replaced according to the rule's strategy.
    pub fn apply(&self, string: &str) -> String {
        if self.rules.is_empty() || string.is_empty() {
            return string.to_string();
        }

        let mut segments = split_camel_case(string);

        for (rule, regex) in self.rules.iter().zip(self.regexes.iter()) {
            for segment in segments.iter_mut() {
                if matches(rule, regex.as_ref(), segment) {
                    *segment = apply_strategy(&rule.strategy, segment);
                }
            }
        }

        join_camel_case(&segments)
    }
}

/// Splits a camelCase string into word segments.
///
/// Examples:
/// - `"userId"` → `["user", "Id"]`
/// - `"imageURL"` → `["image", "URL"]`
/// - `"XMLParser"` → `["XML", "Parser"]`
/// - `"id"` → `["id"]`
fn split_camel_case(string: &str) -> Vec<String> {
    let chars: Vec<char> = string.chars().collect();
    let mut segments: Vec<String> = Vec::new();
    let mut current = String::new();

    for i in 0..chars.len() {
        let c = chars[i];

        if i == 0 {
            current.push(c);
            continue;
        }

        let prev = chars[i - 1];

        if c.is_uppercase() {
            if prev.is_lowercase() {
                // Transition: lower → UPPER (e.g., "user|I" in "userId")
                segments.push(std::mem::take(&mut current));
                current.push(c);
            } else if prev.is_uppercase() {
                // Check if next char is lowercase — if so, this starts a new word
                // e.g., "XM|L|P" in "XMLParser" → split before "P"
                if i + 1 < chars.len() && chars[i + 1].is_lowercase() {
                    segments.push(std::mem::take(&mut current));
                    current.push(c);
                } else {
                    current.push(c);
                }
            } else {
                current.push(c);
            }
        } else {
            current.push(c);
        }
    }

    if !current.is_empty() {
        segments.push(current);
    }

    segments
}

/// Checks whether a rule matches a given word segment.
fn matches(rule: &CapitalizationRule, regex: Option<&Regex>, segment: &str) -> bool {
    match &rule.term {
        // Swift: `segment.caseInsensitiveCompare(term) == .orderedSame`
        Term::String(term) => segment.to_lowercase() == term.to_lowercase(),
        // Swift: unanchored `NSRegularExpression.firstMatch`; invalid pattern → no match.
        Term::Regex(_) => regex.map(|r| r.is_match(segment)).unwrap_or(false),
    }
}

/// Applies the capitalization strategy to a segment.
fn apply_strategy(strategy: &CaseStrategy, segment: &str) -> String {
    match strategy {
        CaseStrategy::Upper => {
            // Mirror SwiftFormat's `acronyms` rule: only capitalize when the first character is
            // already uppercase so leading lowercase words (`api` in `apiKey`) are preserved.
            match segment.chars().next() {
                Some(first) if first.is_uppercase() => segment.to_uppercase(),
                _ => segment.to_string(),
            }
        }
        CaseStrategy::Lower => segment.to_lowercase(),
        CaseStrategy::Replace(replacement) => replacement.clone(),
    }
}

/// Rejoins word segments into a camelCase string.
///
/// The first segment preserves its original casing. Subsequent segments are capitalized
/// (first character uppercased) unless they are fully uppercased (acronyms).
fn join_camel_case(segments: &[String]) -> String {
    let Some((first, rest)) = segments.split_first() else {
        return String::new();
    };

    let mut result = first.clone();
    for segment in rest {
        if segment.is_empty() {
            continue;
        }

        if *segment == segment.to_uppercase() {
            result.push_str(segment);
        } else {
            let mut chars = segment.chars();
            if let Some(c) = chars.next() {
                result.extend(c.to_uppercase());
            }
            result.push_str(chars.as_str());
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(term: Term, strategy: CaseStrategy) -> CapitalizationRule {
        CapitalizationRule { term, strategy }
    }

    #[test]
    fn test_split_camel_case() {
        assert_eq!(split_camel_case("userId"), vec!["user", "Id"]);
        assert_eq!(split_camel_case("imageURL"), vec!["image", "URL"]);
        assert_eq!(split_camel_case("userID"), vec!["user", "ID"]);
        assert_eq!(split_camel_case("XMLParser"), vec!["XML", "Parser"]);
        assert_eq!(split_camel_case("id"), vec!["id"]);
        // A digit is neither upper- nor lowercase, so Swift never splits after it.
        assert_eq!(split_camel_case("item_2Id"), vec!["item_2Id"]);
    }

    #[test]
    fn test_no_rules_or_empty_string_is_identity() {
        let cap = Capitalizer::new(vec![]);
        assert_eq!(cap.apply("userId"), "userId");
        let cap = Capitalizer::new(vec![rule(Term::String("id".into()), CaseStrategy::Upper)]);
        assert_eq!(cap.apply(""), "");
    }

    #[test]
    fn test_upper_only_when_first_char_uppercase() {
        let cap = Capitalizer::new(vec![rule(Term::String("id".into()), CaseStrategy::Upper)]);
        assert_eq!(cap.apply("userId"), "userID");
        assert_eq!(cap.apply("idToken"), "idToken");
        assert_eq!(cap.apply("Id"), "ID");
    }

    #[test]
    fn test_lower() {
        let cap = Capitalizer::new(vec![rule(Term::String("id".into()), CaseStrategy::Lower)]);
        assert_eq!(cap.apply("userID"), "userId");
        assert_eq!(cap.apply("ID"), "id");
    }

    #[test]
    fn test_replace() {
        let cap = Capitalizer::new(vec![rule(
            Term::String("query".into()),
            CaseStrategy::Replace("Qry".into()),
        )]);
        assert_eq!(cap.apply("heroQuery"), "heroQry");
        assert_eq!(cap.apply("query"), "Qry");
    }

    #[test]
    fn test_regex_unanchored_and_invalid() {
        let cap = Capitalizer::new(vec![rule(
            Term::Regex("^Details$".into()),
            CaseStrategy::Upper,
        )]);
        assert_eq!(cap.apply("heroDetails"), "heroDETAILS");
        assert_eq!(cap.apply("heroDetailsList"), "heroDETAILSList");
        let cap = Capitalizer::new(vec![rule(Term::Regex("id".into()), CaseStrategy::Upper)]);
        assert_eq!(cap.apply("isHidden"), "isHIDDEN");
        let cap = Capitalizer::new(vec![rule(Term::Regex("(".into()), CaseStrategy::Upper)]);
        assert_eq!(cap.apply("userId"), "userId");
    }

    #[test]
    fn test_join_capitalizes_following_segments() {
        let cap = Capitalizer::new(vec![rule(
            Term::String("feathers".into()),
            CaseStrategy::Replace("plumage".into()),
        )]);
        assert_eq!(cap.apply("birdFeathers"), "birdPlumage");
        assert_eq!(cap.apply("Feathers"), "plumage");
    }
}
