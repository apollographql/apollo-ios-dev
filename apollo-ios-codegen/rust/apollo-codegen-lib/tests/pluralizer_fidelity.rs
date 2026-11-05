//! Fidelity tests for Pluralizer against InflectorKit output.
//!
//! Every test case validates that the Rust Pluralizer produces identical output
//! to Swift's InflectorKit for that input. These tests cover all 60 default rules
//! (21 plural, 22 singular, 6 irregular, 10 uncountable) plus case sensitivity,
//! GraphQL type names, custom rules, and edge cases.
//!
use apollo_codegen_lib::inflection_rule::InflectionRule;
use apollo_codegen_lib::pluralizer::Pluralizer;

// ---------------------------------------------------------------------------
// Helper: create a default Pluralizer (no custom rules)
// ---------------------------------------------------------------------------
fn default_pluralizer() -> Pluralizer {
    Pluralizer::new(vec![])
}

// ===========================================================================
// Module: pluralize_basic
// ===========================================================================
mod pluralize_basic {
    use super::*;

    #[test]
    fn cat() {
        assert_eq!(default_pluralizer().pluralize("cat"), "cats");
    }

    #[test]
    fn bus() {
        assert_eq!(default_pluralizer().pluralize("bus"), "buses");
    }

    #[test]
    fn octopus() {
        assert_eq!(default_pluralizer().pluralize("octopus"), "octopi");
    }

    #[test]
    fn alias() {
        assert_eq!(default_pluralizer().pluralize("alias"), "aliases");
    }

    #[test]
    fn status() {
        assert_eq!(default_pluralizer().pluralize("status"), "statuses");
    }

    #[test]
    fn quiz() {
        assert_eq!(default_pluralizer().pluralize("quiz"), "quizzes");
    }

    #[test]
    fn ox() {
        assert_eq!(default_pluralizer().pluralize("ox"), "oxen");
    }

    #[test]
    fn matrix() {
        assert_eq!(default_pluralizer().pluralize("matrix"), "matrices");
    }

    #[test]
    fn vertex() {
        assert_eq!(default_pluralizer().pluralize("vertex"), "vertices");
    }

    #[test]
    fn index() {
        assert_eq!(default_pluralizer().pluralize("index"), "indices");
    }

    #[test]
    fn hive() {
        assert_eq!(default_pluralizer().pluralize("hive"), "hives");
    }

    #[test]
    fn mouse() {
        assert_eq!(default_pluralizer().pluralize("mouse"), "mice");
    }

    #[test]
    fn louse() {
        assert_eq!(default_pluralizer().pluralize("louse"), "lice");
    }

    #[test]
    fn tomato() {
        assert_eq!(default_pluralizer().pluralize("tomato"), "tomatoes");
    }

    #[test]
    fn buffalo() {
        assert_eq!(default_pluralizer().pluralize("buffalo"), "buffaloes");
    }

    #[test]
    fn analysis() {
        assert_eq!(default_pluralizer().pluralize("analysis"), "analyses");
    }

    #[test]
    fn axis() {
        assert_eq!(default_pluralizer().pluralize("axis"), "axes");
    }

    #[test]
    fn testis() {
        assert_eq!(default_pluralizer().pluralize("testis"), "testes");
    }

    #[test]
    fn crisis() {
        assert_eq!(default_pluralizer().pluralize("crisis"), "crises");
    }

    #[test]
    fn knife() {
        assert_eq!(default_pluralizer().pluralize("knife"), "knives");
    }

    #[test]
    fn wolf() {
        assert_eq!(default_pluralizer().pluralize("wolf"), "wolves");
    }

    #[test]
    fn baby() {
        assert_eq!(default_pluralizer().pluralize("baby"), "babies");
    }

    #[test]
    fn city() {
        assert_eq!(default_pluralizer().pluralize("city"), "cities");
    }

    #[test]
    fn box_word() {
        assert_eq!(default_pluralizer().pluralize("box"), "boxes");
    }

    #[test]
    fn church() {
        assert_eq!(default_pluralizer().pluralize("church"), "churches");
    }

    #[test]
    fn dress() {
        assert_eq!(default_pluralizer().pluralize("dress"), "dresses");
    }

    #[test]
    fn wish() {
        assert_eq!(default_pluralizer().pluralize("wish"), "wishes");
    }

    #[test]
    fn virus() {
        assert_eq!(default_pluralizer().pluralize("virus"), "viri");
    }

    #[test]
    fn datum() {
        assert_eq!(default_pluralizer().pluralize("datum"), "data");
    }

    #[test]
    fn medium() {
        assert_eq!(default_pluralizer().pluralize("medium"), "media");
    }

    #[test]
    fn wife() {
        assert_eq!(default_pluralizer().pluralize("wife"), "wives");
    }

    #[test]
    fn half() {
        assert_eq!(default_pluralizer().pluralize("half"), "halves");
    }
}

// ===========================================================================
// Module: singularize_basic
// ===========================================================================
mod singularize_basic {
    use super::*;

    #[test]
    fn cats() {
        assert_eq!(default_pluralizer().singularize("cats"), "cat");
    }

    #[test]
    fn buses() {
        assert_eq!(default_pluralizer().singularize("buses"), "bus");
    }

    #[test]
    fn octopi() {
        assert_eq!(default_pluralizer().singularize("octopi"), "octopus");
    }

    #[test]
    fn aliases() {
        assert_eq!(default_pluralizer().singularize("aliases"), "alias");
    }

    #[test]
    fn quizzes() {
        assert_eq!(default_pluralizer().singularize("quizzes"), "quiz");
    }

    #[test]
    fn oxen() {
        assert_eq!(default_pluralizer().singularize("oxen"), "ox");
    }

    #[test]
    fn matrices() {
        assert_eq!(default_pluralizer().singularize("matrices"), "matrix");
    }

    #[test]
    fn analyses() {
        assert_eq!(default_pluralizer().singularize("analyses"), "analysis");
    }

    #[test]
    fn databases() {
        assert_eq!(default_pluralizer().singularize("databases"), "database");
    }

    #[test]
    fn shoes() {
        assert_eq!(default_pluralizer().singularize("shoes"), "shoe");
    }

    #[test]
    fn movies() {
        assert_eq!(default_pluralizer().singularize("movies"), "movie");
    }

    #[test]
    fn series() {
        assert_eq!(default_pluralizer().singularize("series"), "series");
    }

    #[test]
    fn news() {
        assert_eq!(default_pluralizer().singularize("news"), "news");
    }

    #[test]
    fn vertices() {
        assert_eq!(default_pluralizer().singularize("vertices"), "vertex");
    }

    #[test]
    fn indices() {
        assert_eq!(default_pluralizer().singularize("indices"), "index");
    }

    #[test]
    fn knives() {
        assert_eq!(default_pluralizer().singularize("knives"), "knife");
    }

    #[test]
    fn wolves() {
        assert_eq!(default_pluralizer().singularize("wolves"), "wolf");
    }

    #[test]
    fn babies() {
        assert_eq!(default_pluralizer().singularize("babies"), "baby");
    }

    #[test]
    fn cities() {
        assert_eq!(default_pluralizer().singularize("cities"), "city");
    }

    #[test]
    fn boxes() {
        assert_eq!(default_pluralizer().singularize("boxes"), "box");
    }

    #[test]
    fn churches() {
        assert_eq!(default_pluralizer().singularize("churches"), "church");
    }

    #[test]
    fn dresses() {
        assert_eq!(default_pluralizer().singularize("dresses"), "dress");
    }

    #[test]
    fn wishes() {
        assert_eq!(default_pluralizer().singularize("wishes"), "wish");
    }

    #[test]
    fn viri() {
        assert_eq!(default_pluralizer().singularize("viri"), "virus");
    }

    #[test]
    fn data() {
        assert_eq!(default_pluralizer().singularize("data"), "datum");
    }

    #[test]
    fn media() {
        assert_eq!(default_pluralizer().singularize("media"), "medium");
    }

    #[test]
    fn wives() {
        assert_eq!(default_pluralizer().singularize("wives"), "wife");
    }

    #[test]
    fn halves() {
        assert_eq!(default_pluralizer().singularize("halves"), "half");
    }

    #[test]
    fn statuses() {
        assert_eq!(default_pluralizer().singularize("statuses"), "status");
    }

    #[test]
    fn crises() {
        assert_eq!(default_pluralizer().singularize("crises"), "crisis");
    }

    #[test]
    fn testes() {
        assert_eq!(default_pluralizer().singularize("testes"), "testis");
    }

    #[test]
    fn tomatoes() {
        assert_eq!(default_pluralizer().singularize("tomatoes"), "tomato");
    }

    #[test]
    fn buffaloes() {
        assert_eq!(default_pluralizer().singularize("buffaloes"), "buffalo");
    }

    #[test]
    fn hives() {
        assert_eq!(default_pluralizer().singularize("hives"), "hive");
    }

    #[test]
    fn axes() {
        assert_eq!(default_pluralizer().singularize("axes"), "axis");
    }
}

// ===========================================================================
// Module: irregular_words
// ===========================================================================
mod irregular_words {
    use super::*;

    #[test]
    fn person_to_people() {
        assert_eq!(default_pluralizer().pluralize("person"), "people");
    }

    #[test]
    fn people_to_person() {
        assert_eq!(default_pluralizer().singularize("people"), "person");
    }

    #[test]
    fn man_to_men() {
        assert_eq!(default_pluralizer().pluralize("man"), "men");
    }

    #[test]
    fn men_to_man() {
        assert_eq!(default_pluralizer().singularize("men"), "man");
    }

    #[test]
    fn child_to_children() {
        assert_eq!(default_pluralizer().pluralize("child"), "children");
    }

    #[test]
    fn children_to_child() {
        assert_eq!(default_pluralizer().singularize("children"), "child");
    }

    #[test]
    fn sex_to_sexes() {
        assert_eq!(default_pluralizer().pluralize("sex"), "sexes");
    }

    #[test]
    fn sexes_to_sex() {
        assert_eq!(default_pluralizer().singularize("sexes"), "sex");
    }

    #[test]
    fn move_to_moves() {
        assert_eq!(default_pluralizer().pluralize("move"), "moves");
    }

    #[test]
    fn moves_to_move() {
        assert_eq!(default_pluralizer().singularize("moves"), "move");
    }

    #[test]
    fn zombie_to_zombies() {
        assert_eq!(default_pluralizer().pluralize("zombie"), "zombies");
    }

    #[test]
    fn zombies_to_zombie() {
        assert_eq!(default_pluralizer().singularize("zombies"), "zombie");
    }
}

// ===========================================================================
// Module: uncountable_words
// ===========================================================================
mod uncountable_words {
    use super::*;

    #[test]
    fn equipment_plural() {
        assert_eq!(default_pluralizer().pluralize("equipment"), "equipment");
    }

    #[test]
    fn equipment_singular() {
        assert_eq!(default_pluralizer().singularize("equipment"), "equipment");
    }

    #[test]
    fn information_plural() {
        assert_eq!(default_pluralizer().pluralize("information"), "information");
    }

    #[test]
    fn information_singular() {
        assert_eq!(
            default_pluralizer().singularize("information"),
            "information"
        );
    }

    #[test]
    fn rice_plural() {
        assert_eq!(default_pluralizer().pluralize("rice"), "rice");
    }

    #[test]
    fn rice_singular() {
        assert_eq!(default_pluralizer().singularize("rice"), "rice");
    }

    #[test]
    fn money_plural() {
        assert_eq!(default_pluralizer().pluralize("money"), "money");
    }

    #[test]
    fn money_singular() {
        assert_eq!(default_pluralizer().singularize("money"), "money");
    }

    #[test]
    fn species_plural() {
        assert_eq!(default_pluralizer().pluralize("species"), "species");
    }

    #[test]
    fn species_singular() {
        assert_eq!(default_pluralizer().singularize("species"), "species");
    }

    #[test]
    fn series_plural() {
        assert_eq!(default_pluralizer().pluralize("series"), "series");
    }

    #[test]
    fn series_singular() {
        assert_eq!(default_pluralizer().singularize("series"), "series");
    }

    #[test]
    fn fish_plural() {
        assert_eq!(default_pluralizer().pluralize("fish"), "fish");
    }

    #[test]
    fn fish_singular() {
        assert_eq!(default_pluralizer().singularize("fish"), "fish");
    }

    #[test]
    fn sheep_plural() {
        assert_eq!(default_pluralizer().pluralize("sheep"), "sheep");
    }

    #[test]
    fn sheep_singular() {
        assert_eq!(default_pluralizer().singularize("sheep"), "sheep");
    }

    #[test]
    fn jeans_plural() {
        assert_eq!(default_pluralizer().pluralize("jeans"), "jeans");
    }

    #[test]
    fn jeans_singular() {
        assert_eq!(default_pluralizer().singularize("jeans"), "jeans");
    }

    #[test]
    fn police_plural() {
        assert_eq!(default_pluralizer().pluralize("police"), "police");
    }

    #[test]
    fn police_singular() {
        assert_eq!(default_pluralizer().singularize("police"), "police");
    }
}

// ===========================================================================
// Module: case_sensitivity (Pitfall 3 - CRITICAL)
// ===========================================================================
mod case_sensitivity {
    use super::*;

    #[test]
    fn pluralize_cat_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Cat"), "Cats");
    }

    #[test]
    fn pluralize_cat_uppercase() {
        assert_eq!(default_pluralizer().pluralize("CAT"), "CATs");
    }

    #[test]
    fn pluralize_person_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Person"), "People");
    }

    // InflectorKit stores irregulars under the given and `capitalizedString` keys only and looks
    // them up with an exact, case-sensitive match, so fully uppercased words fall through to the
    // (case-insensitive) regex rules.
    #[test]
    fn pluralize_person_uppercase() {
        assert_eq!(default_pluralizer().pluralize("PERSON"), "PERSONs");
    }

    #[test]
    fn singularize_cats_capitalized() {
        assert_eq!(default_pluralizer().singularize("Cats"), "Cat");
    }

    #[test]
    fn singularize_people_capitalized() {
        assert_eq!(default_pluralizer().singularize("People"), "Person");
    }

    #[test]
    fn singularize_people_uppercase() {
        assert_eq!(default_pluralizer().singularize("PEOPLE"), "PEOPLE");
    }

    #[test]
    fn pluralize_bus_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Bus"), "Buses");
    }

    #[test]
    fn pluralize_quiz_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Quiz"), "Quizzes");
    }

    // Uncountables are matched exactly (`containsObject:`), so only the lowercase spelling is
    // left alone.
    #[test]
    fn uncountable_sheep_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Sheep"), "Sheeps");
    }

    #[test]
    fn uncountable_sheep_uppercase() {
        assert_eq!(default_pluralizer().pluralize("SHEEP"), "SHEEPs");
    }

    #[test]
    fn pluralize_child_capitalized() {
        assert_eq!(default_pluralizer().pluralize("Child"), "Children");
    }

    #[test]
    fn pluralize_man_uppercase() {
        assert_eq!(default_pluralizer().pluralize("MAN"), "MANs");
    }

    #[test]
    fn singularize_men_uppercase() {
        assert_eq!(default_pluralizer().singularize("MEN"), "MEN");
    }
}

// ===========================================================================
// Module: graphql_type_names (realistic usage context)
// ===========================================================================
mod graphql_type_names {
    use super::*;

    #[test]
    fn user() {
        assert_eq!(default_pluralizer().pluralize("User"), "Users");
    }

    #[test]
    fn query() {
        assert_eq!(default_pluralizer().pluralize("Query"), "Queries");
    }

    #[test]
    fn address() {
        assert_eq!(default_pluralizer().pluralize("Address"), "Addresses");
    }

    #[test]
    fn animal() {
        assert_eq!(default_pluralizer().pluralize("Animal"), "Animals");
    }

    #[test]
    fn species_type() {
        // Uncountable - returned unchanged
        assert_eq!(default_pluralizer().pluralize("Species"), "Species");
    }

    #[test]
    fn hero() {
        // "hero" does not match (buffal|tomat)o$ rule, so the generic "$" -> "s" applies
        assert_eq!(default_pluralizer().pluralize("Hero"), "Heros");
    }

    #[test]
    fn category() {
        assert_eq!(default_pluralizer().pluralize("Category"), "Categories");
    }

    #[test]
    fn repository() {
        assert_eq!(default_pluralizer().pluralize("Repository"), "Repositories");
    }

    #[test]
    fn status_type() {
        assert_eq!(default_pluralizer().pluralize("Status"), "Statuses");
    }

    #[test]
    fn search_index() {
        assert_eq!(default_pluralizer().pluralize("Index"), "Indices");
    }

    #[test]
    fn mutation() {
        assert_eq!(default_pluralizer().pluralize("Mutation"), "Mutations");
    }

    #[test]
    fn subscription() {
        assert_eq!(
            default_pluralizer().pluralize("Subscription"),
            "Subscriptions"
        );
    }

    #[test]
    fn interface() {
        assert_eq!(default_pluralizer().pluralize("Interface"), "Interfaces");
    }

    #[test]
    fn schema() {
        assert_eq!(default_pluralizer().pluralize("Schema"), "Schemas");
    }

    #[test]
    fn field() {
        assert_eq!(default_pluralizer().pluralize("Field"), "Fields");
    }

    #[test]
    fn directive() {
        assert_eq!(default_pluralizer().pluralize("Directive"), "Directives");
    }

    #[test]
    fn fragment() {
        assert_eq!(default_pluralizer().pluralize("Fragment"), "Fragments");
    }

    #[test]
    fn type_name() {
        assert_eq!(default_pluralizer().pluralize("Type"), "Types");
    }

    // Singularize GraphQL type names
    #[test]
    fn users_singular() {
        assert_eq!(default_pluralizer().singularize("Users"), "User");
    }

    #[test]
    fn queries_singular() {
        assert_eq!(default_pluralizer().singularize("Queries"), "Query");
    }

    #[test]
    fn addresses_singular() {
        assert_eq!(default_pluralizer().singularize("Addresses"), "Address");
    }

    #[test]
    fn categories_singular() {
        assert_eq!(default_pluralizer().singularize("Categories"), "Category");
    }
}

// ===========================================================================
// Module: custom_rules
// ===========================================================================
mod custom_rules {
    use super::*;

    #[test]
    fn custom_plural_rule_overrides_default() {
        let pluralizer = Pluralizer::new(vec![InflectionRule::Pluralization {
            singular_regex: "cat$".to_string(),
            replacement_regex: "catz".to_string(),
        }]);
        assert_eq!(pluralizer.pluralize("cat"), "catz");
    }

    #[test]
    fn custom_singular_rule_overrides_default() {
        let pluralizer = Pluralizer::new(vec![InflectionRule::Singularization {
            plural_regex: "catz$".to_string(),
            replacement_regex: "cat".to_string(),
        }]);
        assert_eq!(pluralizer.singularize("catz"), "cat");
    }

    #[test]
    fn custom_irregular_word() {
        let pluralizer = Pluralizer::new(vec![InflectionRule::Irregular {
            singular: "goose".to_string(),
            plural: "geese".to_string(),
        }]);
        assert_eq!(pluralizer.pluralize("goose"), "geese");
        assert_eq!(pluralizer.singularize("geese"), "goose");
    }

    #[test]
    fn custom_uncountable_word() {
        let pluralizer = Pluralizer::new(vec![InflectionRule::Uncountable {
            word: "software".to_string(),
        }]);
        assert_eq!(pluralizer.pluralize("software"), "software");
        assert_eq!(pluralizer.singularize("software"), "software");
    }

    #[test]
    fn default_rules_still_work_with_custom() {
        // Even with custom rules, default rules should still work for non-matching words
        let pluralizer = Pluralizer::new(vec![InflectionRule::Pluralization {
            singular_regex: "zzz$".to_string(),
            replacement_regex: "zzzs".to_string(),
        }]);
        assert_eq!(pluralizer.pluralize("cat"), "cats");
        assert_eq!(pluralizer.pluralize("person"), "people");
    }
}

// ===========================================================================
// Module: edge_cases
// ===========================================================================
mod edge_cases {
    use super::*;

    // The catch-all `$` -> `s` plural rule matches the empty string too.
    #[test]
    fn empty_string_pluralize() {
        assert_eq!(default_pluralizer().pluralize(""), "s");
    }

    #[test]
    fn empty_string_singularize() {
        assert_eq!(default_pluralizer().singularize(""), "");
    }

    #[test]
    fn single_letter_s() {
        // "s" matches s$ rule -> "s" (replaces with "s")
        assert_eq!(default_pluralizer().pluralize("s"), "s");
    }

    #[test]
    fn oxen_stays_oxen() {
        // "oxen" matches ^(oxen)$ rule -> "$1" -> "oxen"
        assert_eq!(default_pluralizer().pluralize("oxen"), "oxen");
    }

    #[test]
    fn mice_stays_mice() {
        // "mice" matches ^(m|l)ice$ rule -> "$1ice" -> "mice"
        assert_eq!(default_pluralizer().pluralize("mice"), "mice");
    }

    #[test]
    fn lice_stays_lice() {
        assert_eq!(default_pluralizer().pluralize("lice"), "lice");
    }

    #[test]
    fn octopi_stays_octopi() {
        // "octopi" matches (octop|vir)i$ rule -> "$1i" -> "octopi"
        assert_eq!(default_pluralizer().pluralize("octopi"), "octopi");
    }

    #[test]
    fn viri_stays_viri() {
        assert_eq!(default_pluralizer().pluralize("viri"), "viri");
    }

    #[test]
    fn data_stays_data() {
        // "data" matches ([ti])a$ rule -> "$1a" -> "data" (already plural)
        assert_eq!(default_pluralizer().pluralize("data"), "data");
    }
}

// ===========================================================================
// Module: idempotent (plural of already-plural words)
// ===========================================================================
mod idempotent {
    use super::*;

    #[test]
    fn cats_stays_cats() {
        // "cats" matches s$ -> s rule, so stays "cats"
        assert_eq!(default_pluralizer().pluralize("cats"), "cats");
    }

    #[test]
    fn dogs_stays_dogs() {
        assert_eq!(default_pluralizer().pluralize("dogs"), "dogs");
    }

    #[test]
    fn buses_stays_buses() {
        assert_eq!(default_pluralizer().pluralize("buses"), "buses");
    }

    #[test]
    fn statuses_stays_statuses() {
        assert_eq!(default_pluralizer().pluralize("statuses"), "statuses");
    }

    #[test]
    fn quizzes_stays_quizzes() {
        assert_eq!(default_pluralizer().pluralize("quizzes"), "quizzes");
    }
}

// ===========================================================================
// Module: serde_roundtrip (validates InflectionRule serialization)
// ===========================================================================
mod serde_roundtrip {
    use super::*;

    #[test]
    fn pluralization_rule_roundtrip() {
        let rule = InflectionRule::Pluralization {
            singular_regex: "s$".to_string(),
            replacement_regex: "ses".to_string(),
        };
        let json = serde_json::to_string(&rule).unwrap();
        let deserialized: InflectionRule = serde_json::from_str(&json).unwrap();
        assert_eq!(rule, deserialized);
    }

    #[test]
    fn singularization_rule_roundtrip() {
        let rule = InflectionRule::Singularization {
            plural_regex: "ses$".to_string(),
            replacement_regex: "s".to_string(),
        };
        let json = serde_json::to_string(&rule).unwrap();
        let deserialized: InflectionRule = serde_json::from_str(&json).unwrap();
        assert_eq!(rule, deserialized);
    }

    #[test]
    fn irregular_rule_roundtrip() {
        let rule = InflectionRule::Irregular {
            singular: "person".to_string(),
            plural: "people".to_string(),
        };
        let json = serde_json::to_string(&rule).unwrap();
        let deserialized: InflectionRule = serde_json::from_str(&json).unwrap();
        assert_eq!(rule, deserialized);
    }

    #[test]
    fn uncountable_rule_roundtrip() {
        let rule = InflectionRule::Uncountable {
            word: "sheep".to_string(),
        };
        let json = serde_json::to_string(&rule).unwrap();
        let deserialized: InflectionRule = serde_json::from_str(&json).unwrap();
        assert_eq!(rule, deserialized);
    }
}
