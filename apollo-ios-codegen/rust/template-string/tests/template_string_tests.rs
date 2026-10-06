/// Comprehensive integration tests for the TemplateString DSL.
///
/// Tests the proc macro (`template_string!`) and runtime types
/// (`TemplateString`, `TemplateStringBuilder`) together from
/// the consumer's perspective.
///
/// Organized into modules matching the behavior groups from the plan:
/// - literal_tests: basic string literals
/// - string_interpolation_tests: expression interpolation with indentation
/// - if_tests: conditional rendering
/// - if_let_tests: optional unwrapping
/// - for_each_in_tests: iteration
/// - list_tests: list rendering with wrapping
/// - comment_tests: // prefix
/// - documentation_tests: /// prefix
/// - section_tests: section rendering
/// - empty_line_removal_tests: line removal and lastLineWasRemoved behavior
/// - indentation_tests: multi-level indentation tracking
/// - combined_tests: real-world template patterns

use template_string::{template_string, TemplateString, TemplateStringBuilder};

mod literal_tests {
    use super::*;

    #[test]
    fn simple_string_literal() {
        let result = template_string!("hello");
        assert_eq!(result.description(), "hello");
    }

    #[test]
    fn multi_line_literal_preserves_newlines() {
        let result = template_string!("line1\nline2\nline3");
        assert_eq!(result.description(), "line1\nline2\nline3");
    }

    #[test]
    fn empty_template() {
        let result = template_string!("");
        assert_eq!(result.description(), "");
    }

    #[test]
    fn literal_with_whitespace() {
        let result = template_string!("  hello  ");
        assert_eq!(result.description(), "  hello  ");
    }

    #[test]
    fn literal_with_tabs() {
        let result = template_string!("\thello\t");
        assert_eq!(result.description(), "\thello\t");
    }

    #[test]
    fn multiple_literals_concatenated() {
        let result = template_string!("hello" " " "world");
        assert_eq!(result.description(), "hello world");
    }
}

mod string_interpolation_tests {
    use super::*;

    #[test]
    fn single_expression() {
        let name = "world";
        let result = template_string!("hello " {name});
        assert_eq!(result.description(), "hello world");
    }

    #[test]
    fn expression_with_to_string() {
        let count = 42;
        let result = template_string!("count: " {count});
        assert_eq!(result.description(), "count: 42");
    }

    #[test]
    fn multi_line_expression_with_indentation() {
        // When buffer has "  " before interpolation, multi-line values
        // get "  " prepended on each line after the first
        let value = "line1\nline2\nline3";
        let result = template_string!("  " {value});
        assert_eq!(result.description(), "  line1\n  line2\n  line3");
    }

    #[test]
    fn expression_between_literals() {
        let name = "Rust";
        let result = template_string!("Hello, " {name} "!");
        assert_eq!(result.description(), "Hello, Rust!");
    }

    #[test]
    fn multiple_expressions() {
        let first = "hello";
        let second = "world";
        let result = template_string!({first} " " {second});
        assert_eq!(result.description(), "hello world");
    }
}

mod if_tests {
    use super::*;

    #[test]
    fn true_condition_includes_template() {
        let result = template_string!("start " {if: true, "included"} " end");
        assert_eq!(result.description(), "start included end");
    }

    #[test]
    fn false_condition_removes_line_whitespace_only() {
        let result = template_string!("line1\n  " {if: false, "skipped"} "\nline3");
        // The "  " line was whitespace-only, so it's removed
        // Then the leading \n of "\nline3" is skipped (lastLineWasRemoved)
        assert_eq!(result.description(), "line1\nline3");
    }

    #[test]
    fn false_condition_with_else() {
        let result = template_string!({if: false, "skipped", else: "fallback"});
        assert_eq!(result.description(), "fallback");
    }

    #[test]
    fn true_condition_ignores_else() {
        let result = template_string!({if: true, "included", else: "fallback"});
        assert_eq!(result.description(), "included");
    }

    #[test]
    fn if_with_variable_condition() {
        let show = true;
        let result = template_string!({if: show, "visible"});
        assert_eq!(result.description(), "visible");
    }

    #[test]
    fn if_false_with_no_preceding_whitespace() {
        // If the line has non-whitespace content before the if:false,
        // remove_line_if_empty should NOT remove it
        let result = template_string!("content" {if: false, "skipped"});
        assert_eq!(result.description(), "content");
    }
}

mod if_let_tests {
    use super::*;

    #[test]
    fn some_value_includes_template() {
        let opt: Option<&str> = Some("value");
        let result = template_string!({ifLet: opt, |v| format!("got {}", v)});
        assert_eq!(result.description(), "got value");
    }

    #[test]
    fn none_removes_line() {
        let opt: Option<String> = None;
        let result = template_string!("line1\n  " {ifLet: opt, |_v| "content".to_string()} "\nline3");
        assert_eq!(result.description(), "line1\nline3");
    }

    #[test]
    fn none_with_else() {
        let opt: Option<String> = None;
        let result = template_string!({ifLet: opt, |_v| "unreachable".to_string(), else: "fallback"});
        assert_eq!(result.description(), "fallback");
    }

    #[test]
    fn some_value_with_numeric_type() {
        let opt: Option<i32> = Some(42);
        let result = template_string!({ifLet: opt, |n| format!("number: {}", n)});
        assert_eq!(result.description(), "number: 42");
    }
}

mod for_each_in_tests {
    use super::*;

    #[test]
    fn iterates_elements_with_default_separator() {
        let items = vec!["a", "b", "c"];
        let result = template_string!({forEachIn: items.into_iter(), |s| s.to_string()});
        assert_eq!(result.description(), "a,\nb,\nc");
    }

    #[test]
    fn custom_separator() {
        let items = vec!["a", "b", "c"];
        let result = template_string!({forEachIn: items.into_iter(), |s| s.to_string(), separator: " | "});
        assert_eq!(result.description(), "a | b | c");
    }

    #[test]
    fn terminator_appended_after_last_item() {
        let items = vec!["a", "b"];
        let result = template_string!({forEachIn: items.into_iter(), |s| s.to_string(), separator: ", ", terminator: ";"});
        assert_eq!(result.description(), "a, b;");
    }

    #[test]
    fn empty_sequence_removes_line() {
        let items: Vec<&str> = vec![];
        let result = template_string!("line1\n  " {forEachIn: items.into_iter(), |s| s.to_string()} "\nline3");
        assert_eq!(result.description(), "line1\nline3");
    }

    #[test]
    fn single_item() {
        let items = vec!["only"];
        let result = template_string!({forEachIn: items.into_iter(), |s| s.to_string()});
        assert_eq!(result.description(), "only");
    }

    #[test]
    fn with_where_clause() {
        let items = vec![1, 2, 3, 4, 5];
        let result = template_string!({forEachIn: items.into_iter(), |n| n.to_string(), where: |n: &i32| *n > 2});
        assert_eq!(result.description(), "3,\n4,\n5");
    }
}

mod list_tests {
    use super::*;

    #[test]
    fn single_item_no_wrapping() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_list(&["item1"], ",\n", None);
        let result = builder.build();
        assert_eq!(result.description(), "item1");
    }

    #[test]
    fn multiple_items_wrapped_in_newlines() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_list(&["item1", "item2", "item3"], ",\n", None);
        let result = builder.build();
        assert_eq!(
            result.description(),
            "\n  item1,\n  item2,\n  item3\n"
        );
    }

    #[test]
    fn two_items_wrapping() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_list(&["a", "b"], ",\n", None);
        let result = builder.build();
        assert_eq!(result.description(), "\n  a,\n  b\n");
    }

    #[test]
    fn list_via_macro() {
        let items = vec!["x".to_string(), "y".to_string(), "z".to_string()];
        let result = template_string!({list: items});
        assert_eq!(result.description(), "\n  x,\n  y,\n  z\n");
    }

    #[test]
    fn list_single_via_macro() {
        let items = vec!["only".to_string()];
        let result = template_string!({list: items});
        assert_eq!(result.description(), "only");
    }
}

mod comment_tests {
    use super::*;

    #[test]
    fn single_line_comment() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_comment(Some("hello"));
        assert_eq!(builder.build().description(), "// hello");
    }

    #[test]
    fn multi_line_comment() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_comment(Some("line1\nline2\nline3"));
        assert_eq!(
            builder.build().description(),
            "// line1\n// line2\n// line3"
        );
    }

    #[test]
    fn nil_comment_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("prefix\n  ");
        builder.append_comment(None);
        assert_eq!(builder.build().description(), "prefix");
    }

    #[test]
    fn empty_string_comment_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("prefix\n  ");
        builder.append_comment(Some(""));
        assert_eq!(builder.build().description(), "prefix");
    }

    #[test]
    fn comment_via_macro() {
        let text: Option<String> = Some("a comment".to_string());
        let result = template_string!({comment: text});
        assert_eq!(result.description(), "// a comment");
    }

    #[test]
    fn comment_none_via_macro() {
        let text: Option<String> = None;
        let result = template_string!("line1\n  " {comment: text} "\nline3");
        assert_eq!(result.description(), "line1\nline3");
    }
}

mod documentation_tests {
    use super::*;

    #[test]
    fn single_line_doc() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_documentation(Some("hello"));
        assert_eq!(builder.build().description(), "/// hello");
    }

    #[test]
    fn multi_line_doc() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_documentation(Some("line1\nline2"));
        assert_eq!(
            builder.build().description(),
            "/// line1\n/// line2"
        );
    }

    #[test]
    fn documentation_with_empty_line_no_trailing_space() {
        // CRITICAL (Pitfall 6): Empty lines get "///" with NO trailing space
        let mut builder = TemplateStringBuilder::new();
        builder.append_documentation(Some("First line\n\nThird line"));
        assert_eq!(
            builder.build().description(),
            "/// First line\n///\n/// Third line"
        );
    }

    #[test]
    fn nil_documentation_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("prefix\n  ");
        builder.append_documentation(None);
        assert_eq!(builder.build().description(), "prefix");
    }

    #[test]
    fn documentation_via_macro() {
        let doc: Option<String> = Some("A doc comment".to_string());
        let result = template_string!({documentation: doc});
        assert_eq!(result.description(), "/// A doc comment");
    }

    #[test]
    fn documentation_none_via_macro() {
        let doc: Option<String> = None;
        let result = template_string!("line1\n  " {documentation: doc} "\nline3");
        assert_eq!(result.description(), "line1\nline3");
    }
}

mod section_tests {
    use super::*;

    #[test]
    fn non_empty_section_renders_normally() {
        let mut builder = TemplateStringBuilder::new();
        let section = TemplateString::new("content".to_string());
        builder.append_section(&section);
        assert_eq!(builder.build().description(), "content");
    }

    #[test]
    fn empty_section_removes_trailing_newline() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n");
        let section = TemplateString::new(String::new());
        builder.append_section(&section);
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn section_via_macro() {
        let section = TemplateString::new("section content".to_string());
        let result = template_string!("before\n" {section: section} "\nafter");
        assert_eq!(result.description(), "before\nsection content\nafter");
    }

    #[test]
    fn empty_section_via_macro() {
        let section = TemplateString::new(String::new());
        let result = template_string!("before\n" {section: section});
        // Empty section removes trailing \n from "before\n"
        assert_eq!(result.description(), "before");
    }
}

mod empty_line_removal_tests {
    use super::*;

    #[test]
    fn if_false_on_whitespace_only_line_removes_line() {
        let result = template_string!("line1\n  " {if: false, "skipped"} "\nline3");
        assert_eq!(result.description(), "line1\nline3");
    }

    #[test]
    fn after_line_removal_next_literal_leading_newline_skipped() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.remove_line_if_empty();
        // Next literal starts with \n, which should be skipped
        builder.append_literal("\nline3");
        assert_eq!(builder.build().description(), "line1\nline3");
    }

    #[test]
    fn after_line_removal_buffer_trailing_newline_dropped_in_build() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.remove_line_if_empty();
        // Buffer is now "line1\n" with last_line_was_removed=true
        // build() drops the trailing \n
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn multiple_consecutive_removals() {
        let result = template_string!(
            "line1\n  " {if: false, "skip1"}
            "\n  " {if: false, "skip2"}
            "\nline4"
        );
        assert_eq!(result.description(), "line1\nline4");
    }

    #[test]
    fn removal_does_not_affect_non_whitespace_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("  content");
        builder.remove_line_if_empty();
        // "  content" is not whitespace-only, so nothing removed
        assert_eq!(builder.build().description(), "  content");
    }

    #[test]
    fn if_false_removes_and_skips_newline() {
        // This mirrors the key test from the plan
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_if(
            false,
            || TemplateString::new("skipped".into()),
            None::<fn() -> TemplateString>,
        );
        builder.append_literal("\nline3");
        let result = builder.build();
        assert_eq!(result.description(), "line1\nline3");
    }
}

mod indentation_tests {
    use super::*;

    #[test]
    fn flat_template_no_extra_indentation() {
        let value = "hello";
        let result = template_string!({value});
        assert_eq!(result.description(), "hello");
    }

    #[test]
    fn two_space_indent_multiline() {
        let value = "line1\nline2";
        let result = template_string!("  " {value});
        assert_eq!(result.description(), "  line1\n  line2");
    }

    #[test]
    fn tab_indent_multiline() {
        let value = "line1\nline2";
        let result = template_string!("\t" {value});
        assert_eq!(result.description(), "\tline1\n\tline2");
    }

    #[test]
    fn nested_template_reuse_at_different_indent_levels() {
        // Same multi-line content used at two different indent levels
        let content = "x: Int\ny: Int";

        let mut builder1 = TemplateStringBuilder::new();
        builder1.append_literal("  ");
        builder1.append_string(content);
        let result1 = builder1.build();
        assert_eq!(result1.description(), "  x: Int\n  y: Int");

        let mut builder2 = TemplateStringBuilder::new();
        builder2.append_literal("    ");
        builder2.append_string(content);
        let result2 = builder2.build();
        assert_eq!(result2.description(), "    x: Int\n    y: Int");
    }

    #[test]
    fn indentation_after_newline_in_literal() {
        let value = "first\nsecond";
        let result = template_string!("struct Foo {\n  " {value} "\n}");
        assert_eq!(
            result.description(),
            "struct Foo {\n  first\n  second\n}"
        );
    }

    #[test]
    fn no_indentation_for_single_line() {
        let value = "single";
        let result = template_string!("  " {value});
        assert_eq!(result.description(), "  single");
    }

    #[test]
    fn empty_lines_in_multiline_not_indented() {
        // Swift behavior: empty lines in indented content don't get indent
        let value = "first\n\nthird";
        let result = template_string!("  " {value});
        assert_eq!(result.description(), "  first\n\n  third");
    }
}

mod combined_tests {
    use super::*;

    #[test]
    fn template_with_if_documentation_and_interpolation() {
        let doc: Option<String> = Some("A field description".to_string());
        let is_deprecated = false;
        let name = "myField";
        let type_name = "String";

        let result = template_string!(
            "  " {documentation: doc}
            "\n  " {if: is_deprecated, "@available(*, deprecated)"}
            "\n  public let " {name} ": " {type_name}
        );

        assert_eq!(
            result.description(),
            "  /// A field description\n  public let myField: String"
        );
    }

    #[test]
    fn template_with_for_each_in_indented() {
        // The buffer has "  " indent before the forEachIn, so the separator
        // only needs "\n" -- the indent is added automatically by append_string
        let fields = vec!["name: String", "age: Int"];
        let result = template_string!(
            "struct Person {\n  " {forEachIn: fields.into_iter(), |f| f.to_string(), separator: "\n"} "\n}"
        );
        assert_eq!(
            result.description(),
            "struct Person {\n  name: String\n  age: Int\n}"
        );
    }

    #[test]
    fn enum_case_rendering_pattern() {
        let cases = vec![("north", "\"NORTH\""), ("south", "\"SOUTH\""), ("east", "\"EAST\"")];

        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("enum Direction: String {\n");

        for (name, raw) in &cases {
            builder.append_literal("  case ");
            builder.append_string(name);
            builder.append_literal(" = ");
            builder.append_string(raw);
            builder.append_literal("\n");
        }

        builder.append_literal("}");
        let result = builder.build();

        assert_eq!(
            result.description(),
            "enum Direction: String {\n  case north = \"NORTH\"\n  case south = \"SOUTH\"\n  case east = \"EAST\"\n}"
        );
    }

    #[test]
    fn complex_template_with_multiple_features() {
        let class_name = "MyClass";
        let doc: Option<String> = Some("A generated class".to_string());
        let has_init = true;
        let properties = vec!["name", "age"];

        let result = template_string!(
            {documentation: doc}
            "\npublic class " {class_name} " {"
            "\n  " {forEachIn: properties.into_iter(), |p| format!("public var {}: String", p), separator: "\n"}
            "\n  " {if: has_init, "public init() {}"}
            "\n}"
        );

        assert_eq!(
            result.description(),
            "/// A generated class\npublic class MyClass {\n  public var name: String\n  public var age: String\n  public init() {}\n}"
        );
    }

    #[test]
    fn string_plus_template_string_operator() {
        let ts = TemplateString::new("world".to_string());
        let result = "hello ".to_string() + ts;
        assert_eq!(result.description(), "hello world");
    }

    #[test]
    fn empty_template_string_display() {
        let ts = TemplateString::new(String::new());
        assert_eq!(format!("{}", ts), "");
        assert!(ts.is_empty());
    }

    #[test]
    fn template_with_all_conditions_false() {
        let a: Option<String> = None;
        let b = false;
        let items: Vec<&str> = vec![];

        let result = template_string!(
            "header\n"
            "  " {ifLet: a, |_v| "unreachable".to_string()}
            "\n  " {if: b, "skipped"}
            "\n  " {forEachIn: items.into_iter(), |s| s.to_string()}
            "\nfooter"
        );

        assert_eq!(result.description(), "header\nfooter");
    }
}
