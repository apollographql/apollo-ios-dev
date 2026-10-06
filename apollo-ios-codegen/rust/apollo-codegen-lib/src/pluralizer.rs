use crate::inflection_rule::InflectionRule;
use crate::inflector::Inflector;

/// Mirrors Swift's `Pluralizer` struct from `Sources/ApolloCodegenLib/Pluralizer.swift`.
///
/// Wraps an `Inflector` with default English pluralization rules matching InflectorKit.
/// Custom rules can be provided at construction time; they take priority over defaults
/// because they are added after defaults (and thus inserted at the front of the rules list).
#[derive(Clone)]
pub struct Pluralizer {
  inflector: Inflector,
}

impl Pluralizer {
  /// Creates a new `Pluralizer` with default English rules and optional custom rules.
  ///
  /// Default rules are added first, then custom rules. Since rules are inserted at the
  /// front of the list, custom rules will take priority over defaults.
  pub fn new(rules: Vec<InflectionRule>) -> Self {
    let mut inflector = Inflector::new();

    // Add default rules first (so custom rules override them)
    for rule in Self::default_rules() {
      inflector.add_rule(&rule);
    }

    // Add custom rules (these go to front, so they have higher priority)
    for rule in &rules {
      inflector.add_rule(rule);
    }

    Self { inflector }
  }

  /// Singularizes a word using the configured rules.
  pub fn singularize(&self, string: &str) -> String {
    self.inflector.singularize(string)
  }

  /// Pluralizes a word using the configured rules.
  pub fn pluralize(&self, string: &str) -> String {
    self.inflector.pluralize(string)
  }

  /// Returns the complete set of default English inflection rules.
  ///
  /// These are ported exactly from `Sources/ApolloCodegenLib/Pluralizer.swift` lines 62-130.
  /// The order matters: rules are added in this order, and since each rule is inserted
  /// at the front of the list, the LAST rule in this list will be checked FIRST.
  ///
  /// Total: 21 pluralization + 22 singularization + 6 irregular + 10 uncountable = 59 rules
  /// (Note: Swift source has 21 unique plural rules listed as lines 63-83)
  fn default_rules() -> Vec<InflectionRule> {
    vec![
      // -- 21 pluralization rules (from Pluralizer.swift lines 63-83) --
      InflectionRule::Pluralization {
        singular_regex: "$".into(),
        replacement_regex: "s".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "s$".into(),
        replacement_regex: "s".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "^(ax|test)is$".into(),
        replacement_regex: "$1es".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(octop|vir)us$".into(),
        replacement_regex: "$1i".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(octop|vir)i$".into(),
        replacement_regex: "$1i".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(alias|status)$".into(),
        replacement_regex: "$1es".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(bu)s$".into(),
        replacement_regex: "$1ses".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(buffal|tomat)o$".into(),
        replacement_regex: "$1oes".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "([ti])um$".into(),
        replacement_regex: "$1a".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "([ti])a$".into(),
        replacement_regex: "$1a".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "sis$".into(),
        replacement_regex: "ses".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(?:([^f])fe|([lr])f)$".into(),
        replacement_regex: "$1$2ves".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(hive)$".into(),
        replacement_regex: "$1s".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "([^aeiouy]|qu)y$".into(),
        replacement_regex: "$1ies".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(x|ch|ss|sh)$".into(),
        replacement_regex: "$1es".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(matr|vert|ind)(?:ix|ex)$".into(),
        replacement_regex: "$1ices".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "^(m|l)ouse$".into(),
        replacement_regex: "$1ice".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "^(m|l)ice$".into(),
        replacement_regex: "$1ice".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "^(ox)$".into(),
        replacement_regex: "$1en".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "^(oxen)$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Pluralization {
        singular_regex: "(quiz)$".into(),
        replacement_regex: "$1zes".into(),
      },
      // -- 22 singularization rules (from Pluralizer.swift lines 85-111) --
      InflectionRule::Singularization {
        plural_regex: "s$".into(),
        replacement_regex: "".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(ss)$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(n)ews$".into(),
        replacement_regex: "$1ews".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "([ti])a$".into(),
        replacement_regex: "$1um".into(),
      },
      InflectionRule::Singularization {
        plural_regex:
          "((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)(sis|ses)$"
            .into(),
        replacement_regex: "$1sis".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(^analy)(sis|ses)$$".into(),
        replacement_regex: "$1sis".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "([^f])ves$".into(),
        replacement_regex: "$1fe".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(hive)s$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(tive)s$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "([lr])ves$".into(),
        replacement_regex: "$1f".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "([^aeiouy]|qu)ies$".into(),
        replacement_regex: "$1y".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(s)eries$".into(),
        replacement_regex: "$1eries".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(m)ovies$".into(),
        replacement_regex: "$1ovie".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(x|ch|ss|sh)es$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "^(m|l)ice$".into(),
        replacement_regex: "$1ouse".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(bus)(es)?$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(o)es$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(shoe)s$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(cris|test)(is|es)$".into(),
        replacement_regex: "$1is".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "^(a)x[ie]s$".into(),
        replacement_regex: "$1xis".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(octop|vir)(us|i)$".into(),
        replacement_regex: "$1us".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(alias|status)(es)?$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "^(ox)en".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(vert|ind)ices$".into(),
        replacement_regex: "$1ex".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(matr)ices$".into(),
        replacement_regex: "$1ix".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(quiz)zes$".into(),
        replacement_regex: "$1".into(),
      },
      InflectionRule::Singularization {
        plural_regex: "(database)s$".into(),
        replacement_regex: "$1".into(),
      },
      // -- 6 irregular words (from Pluralizer.swift lines 113-118) --
      InflectionRule::Irregular {
        singular: "person".into(),
        plural: "people".into(),
      },
      InflectionRule::Irregular {
        singular: "man".into(),
        plural: "men".into(),
      },
      InflectionRule::Irregular {
        singular: "child".into(),
        plural: "children".into(),
      },
      InflectionRule::Irregular {
        singular: "sex".into(),
        plural: "sexes".into(),
      },
      InflectionRule::Irregular {
        singular: "move".into(),
        plural: "moves".into(),
      },
      InflectionRule::Irregular {
        singular: "zombie".into(),
        plural: "zombies".into(),
      },
      // -- 10 uncountable words (from Pluralizer.swift lines 120-129) --
      InflectionRule::Uncountable {
        word: "equipment".into(),
      },
      InflectionRule::Uncountable {
        word: "information".into(),
      },
      InflectionRule::Uncountable {
        word: "rice".into(),
      },
      InflectionRule::Uncountable {
        word: "money".into(),
      },
      InflectionRule::Uncountable {
        word: "species".into(),
      },
      InflectionRule::Uncountable {
        word: "series".into(),
      },
      InflectionRule::Uncountable {
        word: "fish".into(),
      },
      InflectionRule::Uncountable {
        word: "sheep".into(),
      },
      InflectionRule::Uncountable {
        word: "jeans".into(),
      },
      InflectionRule::Uncountable {
        word: "police".into(),
      },
    ]
  }
}
