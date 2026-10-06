use indexmap::{IndexMap, IndexSet};
use regex::Regex;

use crate::inflection_rule::InflectionRule;

/// A compiled regex rule with its replacement pattern.
#[derive(Clone)]
struct CompiledRule {
    regex: Regex,
    replacement: String,
}

/// Converts NSRegularExpression-style replacement strings to Rust regex replacement strings.
///
/// NSRegularExpression uses `$N` where N is a single digit to refer to capture groups.
/// Rust's `regex` crate is greedy: `$1ses` is interpreted as group `1s` (or `1se`, etc.)
/// which doesn't exist. We need to convert `$N` to `${N}` when followed by alphanumeric chars.
///
/// Examples:
/// - `"$1ses"` -> `"${1}ses"`
/// - `"$1$2ves"` -> `"${1}${2}ves"`
/// - `"$1"` -> `"${1}"` (safe, though `$1` at end also works)
/// - `"s"` -> `"s"` (no groups)
/// - `""` -> `""` (empty)
fn normalize_replacement(replacement: &str) -> String {
    let mut result = String::with_capacity(replacement.len() + 4);
    let chars: Vec<char> = replacement.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if chars[i] == '$' && i + 1 < chars.len() && chars[i + 1].is_ascii_digit() {
            // Found $N -- wrap in ${N}
            result.push('$');
            result.push('{');
            i += 1;
            // Consume the single digit (NSRegularExpression group refs are single-digit)
            result.push(chars[i]);
            result.push('}');
            i += 1;
        } else {
            result.push(chars[i]);
            i += 1;
        }
    }

    result
}

/// A string inflector that applies regex-based pluralization and singularization rules.
///
/// Mirrors InflectorKit's `TTTStringInflector` behavior:
/// - Rules added later take precedence (inserted at front of the rules list)
/// - All regex matching is case-insensitive with `^`/`$` matching at line boundaries (`(?mi)`)
/// - Irregulars are stored as given plus their `NSString.capitalizedString` variants
/// - Uncountable and irregular lookups are exact, case-sensitive matches (InflectorKit)
/// - Application order: check uncountable -> check irregular -> iterate rules (first match wins)
#[derive(Clone)]
pub struct Inflector {
    plural_rules: Vec<CompiledRule>,
    singular_rules: Vec<CompiledRule>,
    /// singular -> plural, in insertion order (`mutableIrregularPluralsBySingular`).
    irregulars: IndexMap<String, String>,
    uncountables: IndexSet<String>,
}

impl Default for Inflector {
    fn default() -> Self {
        Self::new()
    }
}

impl Inflector {
    /// Creates a new inflector with empty rule sets.
    pub fn new() -> Self {
        Self {
            plural_rules: Vec::new(),
            singular_rules: Vec::new(),
            irregulars: IndexMap::new(),
            uncountables: IndexSet::new(),
        }
    }

    /// Adds a rule from an `InflectionRule` enum value.
    pub fn add_rule(&mut self, rule: &InflectionRule) {
        match rule {
            InflectionRule::Pluralization {
                singular_regex,
                replacement_regex,
            } => {
                self.add_plural_rule(singular_regex, replacement_regex);
            }
            InflectionRule::Singularization {
                plural_regex,
                replacement_regex,
            } => {
                self.add_singular_rule(plural_regex, replacement_regex);
            }
            InflectionRule::Irregular { singular, plural } => {
                self.add_irregular(singular, plural);
            }
            InflectionRule::Uncountable { word } => {
                self.add_uncountable(word);
            }
        }
    }

    /// Adds a pluralization rule. The rule is inserted at the front of the rules list
    /// so that later-added rules take precedence over earlier ones.
    ///
    /// Mirrors `TTTStringInflector addPluralRule:withReplacement:`: the pattern and the
    /// replacement are removed from the uncountables (exact string match) and the regex is
    /// compiled with `NSRegularExpressionAnchorsMatchLines | CaseInsensitive`.
    pub fn add_plural_rule(&mut self, pattern: &str, replacement: &str) {
        self.uncountables.shift_remove(pattern);
        self.uncountables.shift_remove(replacement);

        let regex = Regex::new(&format!("(?mi){}", pattern))
            .unwrap_or_else(|e| panic!("Invalid plural regex pattern '{}': {}", pattern, e));

        self.plural_rules.insert(
            0,
            CompiledRule {
                regex,
                replacement: normalize_replacement(replacement),
            },
        );
    }

    /// Adds a singularization rule. The rule is inserted at the front of the rules list
    /// so that later-added rules take precedence over earlier ones.
    ///
    /// Mirrors `TTTStringInflector addSingularRule:withReplacement:`: only the pattern is
    /// removed from the uncountables (exact string match).
    pub fn add_singular_rule(&mut self, pattern: &str, replacement: &str) {
        self.uncountables.shift_remove(pattern);

        let regex = Regex::new(&format!("(?mi){}", pattern))
            .unwrap_or_else(|e| panic!("Invalid singular regex pattern '{}': {}", pattern, e));

        self.singular_rules.insert(
            0,
            CompiledRule {
                regex,
                replacement: normalize_replacement(replacement),
            },
        );
    }

    /// Adds an irregular word pair.
    ///
    /// Mirrors `TTTStringInflector addIrregularWithSingular:plural:`: the pair is stored as
    /// given and once more with both words run through `NSString.capitalizedString` (first
    /// character uppercased, the rest lowercased). Lookups are exact, case-sensitive matches
    /// against those stored forms.
    pub fn add_irregular(&mut self, singular: &str, plural: &str) {
        self.irregulars
            .insert(singular.to_string(), plural.to_string());
        self.irregulars
            .insert(ns_capitalized(singular), ns_capitalized(plural));
    }

    /// Adds an uncountable word. Stored verbatim; the comparison is an exact, case-sensitive
    /// match (`NSMutableSet containsObject:`).
    pub fn add_uncountable(&mut self, word: &str) {
        self.uncountables.insert(word.to_string());
    }

    /// Pluralizes a word using the configured rules (`TTTStringInflector pluralize:`).
    ///
    /// Application order:
    /// 1. Uncountable (exact match) -> unchanged
    /// 2. Irregular singular (exact key match) -> stored plural
    /// 3. Plural rules in order; the first rule that replaces anything wins
    /// 4. Otherwise unchanged
    pub fn pluralize(&self, word: &str) -> String {
        if self.uncountables.contains(word) {
            return word.to_string();
        }

        if let Some(plural) = self.irregulars.get(word) {
            return plural.clone();
        }

        apply_rules(&self.plural_rules, word)
    }

    /// Singularizes a word using the configured rules (`TTTStringInflector singularize:`).
    ///
    /// Application order:
    /// 1. Uncountable (exact match) -> unchanged
    /// 2. Irregular plural (`allKeysForObject:` -> last stored singular whose plural equals
    ///    the word exactly)
    /// 3. Singular rules in order; the first rule that replaces anything wins
    /// 4. Otherwise unchanged
    pub fn singularize(&self, word: &str) -> String {
        if self.uncountables.contains(word) {
            return word.to_string();
        }

        if let Some((singular, _)) = self
            .irregulars
            .iter()
            .rfind(|(_, plural)| plural.as_str() == word)
        {
            return singular.clone();
        }

        apply_rules(&self.singular_rules, word)
    }
}

/// `TTTStringInflectionRule evaluateString:` applied in order: every match of the rule is
/// replaced (`replaceMatchesInString:`) and iteration stops at the first rule that matched.
fn apply_rules(rules: &[CompiledRule], word: &str) -> String {
    for rule in rules {
        if rule.regex.is_match(word) {
            return rule
                .regex
                .replace_all(word, rule.replacement.as_str())
                .to_string();
        }
    }
    word.to_string()
}

/// `NSString.capitalizedString`: the first character of every word is uppercased and the
/// remaining characters are lowercased; words are delimited by whitespace.
fn ns_capitalized(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut at_word_start = true;
    for c in s.chars() {
        if c.is_whitespace() {
            out.push(c);
            at_word_start = true;
        } else if at_word_start {
            out.extend(c.to_uppercase());
            at_word_start = false;
        } else {
            out.extend(c.to_lowercase());
        }
    }
    out
}

/// Capitalizes the first character of a string.
#[allow(dead_code)]
fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(c) => {
            let upper: String = c.to_uppercase().collect();
            format!("{}{}", upper, chars.as_str())
        }
    }
}

/// Applies the capitalization pattern of `source` to `target`.
///
/// - If source is all uppercase: return target in all uppercase
/// - If source starts with uppercase: capitalize target
/// - Otherwise: return target as-is (lowercase)
#[allow(dead_code)]
fn match_case(source: &str, target: &str) -> String {
    if source
        .chars()
        .all(|c| !c.is_alphabetic() || c.is_uppercase())
    {
        target.to_uppercase()
    } else if source.starts_with(|c: char| c.is_uppercase()) {
        capitalize(target)
    } else {
        target.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capitalize() {
        assert_eq!(capitalize("hello"), "Hello");
        assert_eq!(capitalize(""), "");
        assert_eq!(capitalize("a"), "A");
        assert_eq!(capitalize("HELLO"), "HELLO");
    }

    #[test]
    fn test_match_case_all_upper() {
        assert_eq!(match_case("CAT", "dogs"), "DOGS");
        assert_eq!(match_case("PERSON", "people"), "PEOPLE");
    }

    #[test]
    fn test_match_case_initial_cap() {
        assert_eq!(match_case("Cat", "dogs"), "Dogs");
        assert_eq!(match_case("Person", "people"), "People");
    }

    #[test]
    fn test_match_case_lower() {
        assert_eq!(match_case("cat", "dogs"), "dogs");
        assert_eq!(match_case("person", "people"), "people");
    }

    #[test]
    fn test_rule_insertion_at_front() {
        let mut inflector = Inflector::new();
        inflector.add_plural_rule("$", "s");
        inflector.add_plural_rule("s$", "ses");
        // The second rule should be at index 0
        assert_eq!(inflector.plural_rules.len(), 2);
        // "s$" was added second, so it should be first (index 0)
        assert!(inflector.plural_rules[0].regex.is_match("cats"));
    }

    #[test]
    fn test_uncountable_exact_match() {
        let mut inflector = Inflector::new();
        inflector.add_plural_rule("$", "s");
        inflector.add_uncountable("sheep");
        assert_eq!(inflector.pluralize("sheep"), "sheep");
        // InflectorKit compares uncountables with `containsObject:` (case-sensitive).
        assert_eq!(inflector.pluralize("Sheep"), "Sheeps");
    }

    #[test]
    fn test_irregular_bidirectional() {
        let mut inflector = Inflector::new();
        inflector.add_irregular("person", "people");

        // Forward: singular -> plural (as given, plus `capitalizedString` variants)
        assert_eq!(inflector.pluralize("person"), "people");
        assert_eq!(inflector.pluralize("Person"), "People");
        assert_eq!(inflector.pluralize("PERSON"), "PERSON");

        // Reverse: plural -> singular
        assert_eq!(inflector.singularize("people"), "person");
        assert_eq!(inflector.singularize("People"), "Person");
        assert_eq!(inflector.singularize("PEOPLE"), "PEOPLE");
    }

    #[test]
    fn test_regex_case_insensitive() {
        let mut inflector = Inflector::new();
        inflector.add_plural_rule("$", "s");

        assert_eq!(inflector.pluralize("cat"), "cats");
        assert_eq!(inflector.pluralize("Cat"), "Cats");
        // Note: for regex rules, the replacement is literal so CAT -> CATs
        // because the regex matches "$" (end of string) and appends "s"
        assert_eq!(inflector.pluralize("CAT"), "CATs");
    }

    #[test]
    fn test_empty_string() {
        let inflector = Inflector::new();
        assert_eq!(inflector.pluralize(""), "");
        assert_eq!(inflector.singularize(""), "");
    }

    #[test]
    fn test_normalize_replacement() {
        assert_eq!(normalize_replacement("$1ses"), "${1}ses");
        assert_eq!(normalize_replacement("$1$2ves"), "${1}${2}ves");
        assert_eq!(normalize_replacement("$1"), "${1}");
        assert_eq!(normalize_replacement("s"), "s");
        assert_eq!(normalize_replacement(""), "");
        assert_eq!(normalize_replacement("$1es"), "${1}es");
        assert_eq!(normalize_replacement("$1zes"), "${1}zes");
        assert_eq!(normalize_replacement("$1ices"), "${1}ices");
    }
}
