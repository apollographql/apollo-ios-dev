//! Runtime TemplateString and TemplateStringBuilder types.
//! Ports Swift's `TemplateString` struct (407 lines) from
//! `Sources/TemplateString/TemplateString.swift`.
//!
//! The proc macro (`template_string!`) generates calls to
//! `TemplateStringBuilder` methods. All indentation tracking,
//! empty-line removal, and comment formatting happens at runtime
//! in these types.

/// Runtime value holding rendered template output.
/// Mirrors Swift's `TemplateString` struct.
#[derive(Debug, Clone)]
pub struct TemplateString {
    value: String,
    /// Preserved from builder for potential use by parent builders.
    /// Swift uses this when a TemplateString is interpolated into another.
    #[allow(dead_code)]
    last_line_was_removed: bool,
}

impl TemplateString {
    /// Create a new TemplateString from a plain string.
    /// Mirrors Swift's `init(_ string: String)`.
    pub fn new(s: String) -> Self {
        Self {
            value: s,
            last_line_was_removed: false,
        }
    }

    /// Create from builder output, preserving the lastLineWasRemoved flag.
    /// Mirrors Swift's `init(stringInterpolation:)`.
    pub fn from_builder(value: String, last_line_was_removed: bool) -> Self {
        Self {
            value,
            last_line_was_removed,
        }
    }

    /// Whether the template's rendered value is empty.
    /// Mirrors Swift's `isEmpty` property.
    pub fn is_empty(&self) -> bool {
        self.value.is_empty()
    }

    /// The rendered string value.
    /// Mirrors Swift's `description` property.
    pub fn description(&self) -> &str {
        &self.value
    }
}

impl std::fmt::Display for TemplateString {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.value)
    }
}

/// Can be used to concatenate a String and TemplateString directly.
/// This bypasses TemplateString interpolation logic such as indentation calculation.
/// Mirrors Swift's `+(lhs: String, rhs: TemplateString) -> TemplateString`.
impl std::ops::Add<TemplateString> for String {
    type Output = TemplateString;

    fn add(self, rhs: TemplateString) -> TemplateString {
        TemplateString::new(self + rhs.description())
    }
}

/// Builder that accumulates template output at runtime.
/// Mirrors Swift's `TemplateString.StringInterpolation`.
///
/// The proc macro generates code that creates a builder, calls
/// `append_*` methods, and finishes with `build()`.
pub struct TemplateStringBuilder {
    buffer: String,
    last_line_was_removed: bool,
}

impl TemplateStringBuilder {
    /// Create a new empty builder.
    /// Mirrors Swift's `init(literalCapacity:interpolationCount:)`.
    pub fn new() -> Self {
        Self {
            buffer: String::new(),
            last_line_was_removed: false,
        }
    }

    // MARK: - Append Methods

    /// Append a literal string to the buffer.
    /// Mirrors Swift's `appendLiteral(_:)`.
    ///
    /// CRITICAL: Swift uses `defer { lastLineWasRemoved = false }`.
    /// In Rust, we save the current value before setting it to false,
    /// then use the saved value for the conditional check.
    pub fn append_literal(&mut self, literal: &str) {
        if literal.is_empty() {
            return;
        }

        // Save the current flag before clearing it (mirrors Swift's defer)
        let was_removed = self.last_line_was_removed;
        self.last_line_was_removed = false;

        if was_removed && literal.starts_with('\n') {
            self.buffer.push_str(&literal[1..]);
        } else {
            self.buffer.push_str(literal);
        }
    }

    /// Append a string expression with indentation tracking.
    /// Mirrors Swift's `appendInterpolation(_ string: String)`.
    ///
    /// Gets the current indentation from the buffer, then indents
    /// multi-line strings to match.
    pub fn append_string(&mut self, string: &str) {
        let indent = self.get_current_indent();

        if indent.is_empty() {
            self.append_literal(string);
        } else {
            let parts: Vec<&str> = string.split('\n').collect();
            let indented = joined_as_lines(&parts, &indent);
            self.append_literal(&indented);
        }
    }

    /// Append an optional TemplateString.
    /// Mirrors Swift's `appendInterpolation(_ template: TemplateString?)`.
    ///
    /// If None or empty, removes the current line if it's only whitespace.
    pub fn append_template(&mut self, template: Option<&TemplateString>) {
        match template {
            Some(t) if !t.is_empty() => {
                self.append_string(t.description());
            }
            _ => {
                self.remove_line_if_empty();
            }
        }
    }

    /// Append a section template.
    /// Mirrors Swift's `appendInterpolation(section:)`.
    ///
    /// Like regular template interpolation, but additionally removes
    /// a trailing newline from the buffer if the section was empty.
    pub fn append_section(&mut self, section: &TemplateString) {
        self.append_template(Some(section));

        if section.is_empty() && self.buffer.ends_with('\n') {
            self.buffer.pop();
        }
    }

    /// Conditional rendering.
    /// Mirrors Swift's `appendInterpolation(if:_:else:)`.
    pub fn append_if<F, G>(&mut self, condition: bool, template: F, else_template: Option<G>)
    where
        F: FnOnce() -> TemplateString,
        G: FnOnce() -> TemplateString,
    {
        if condition {
            let t = template();
            self.append_template(Some(&t));
        } else if let Some(else_fn) = else_template {
            let t = else_fn();
            self.append_template(Some(&t));
        } else {
            self.remove_line_if_empty();
        }
    }

    /// Optional unwrapping with conditional rendering.
    /// Mirrors Swift's `appendInterpolation(ifLet:where:_:else:)`.
    pub fn append_if_let<T, F, W, G>(
        &mut self,
        optional: Option<T>,
        include_block: F,
        where_block: Option<W>,
        else_template: Option<G>,
    ) where
        F: FnOnce(T) -> TemplateString,
        W: Fn(&T) -> bool,
        G: FnOnce() -> TemplateString,
    {
        match optional {
            Some(val) => {
                let passes_where = where_block
                    .as_ref()
                    .map(|w| w(&val))
                    .unwrap_or(true);
                if passes_where {
                    let t = include_block(val);
                    self.append_template(Some(&t));
                } else if let Some(else_fn) = else_template {
                    let t = else_fn();
                    self.append_template(Some(&t));
                } else {
                    self.remove_line_if_empty();
                }
            }
            None => {
                if let Some(else_fn) = else_template {
                    let t = else_fn();
                    self.append_template(Some(&t));
                } else {
                    self.remove_line_if_empty();
                }
            }
        }
    }

    /// Iterate a sequence, rendering each element with a template.
    /// Mirrors Swift's `appendInterpolation(forEachIn:where:separator:terminator:_:)`.
    pub fn append_for_each_in<T, I, F, W>(
        &mut self,
        sequence: I,
        separator: &str,
        terminator: Option<&str>,
        where_block: Option<W>,
        template: F,
    ) where
        I: IntoIterator<Item = T>,
        F: Fn(T) -> Option<TemplateString>,
        W: Fn(&T) -> bool,
    {
        let mut result_string = String::new();

        for element in sequence {
            // Apply where filter
            let passes = where_block
                .as_ref()
                .map(|w| w(&element))
                .unwrap_or(true);
            if !passes {
                continue;
            }

            // Apply template
            let element_string = match template(element) {
                Some(t) if !t.is_empty() => t.description().to_string(),
                _ => continue,
            };

            if result_string.is_empty() {
                result_string.push_str(&element_string);
            } else {
                result_string.push_str(separator);
                result_string.push_str(&element_string);
            }
        }

        if result_string.is_empty() {
            self.remove_line_if_empty();
            return;
        }

        self.append_string(&result_string);
        if let Some(term) = terminator {
            self.append_string(term);
        }
    }

    /// List rendering with automatic newline wrapping for >1 items.
    /// Mirrors Swift's `appendInterpolation(list:separator:terminator:)`.
    ///
    /// If list has >1 items, wraps with "\n  " prefix and "\n" suffix.
    /// The items are joined with the separator (default ",\n").
    pub fn append_list<T: std::fmt::Display>(
        &mut self,
        list: &[T],
        separator: &str,
        terminator: Option<&str>,
    ) {
        let should_wrap = list.len() > 1;
        if should_wrap {
            self.append_string("\n  ");
        }

        // Build a Vec<TemplateString> from Display items and use sequence logic
        let descriptions: Vec<String> = list.iter().map(|item| item.to_string()).collect();
        self.append_for_each_in(
            descriptions,
            separator,
            terminator,
            None::<fn(&String) -> bool>,
            |s| Some(TemplateString::new(s)),
        );

        if should_wrap {
            self.append_string("\n");
        }
    }

    /// Comment rendering with "//" prefix.
    /// Mirrors Swift's `appendInterpolation(comment:)`.
    pub fn append_comment(&mut self, comment: Option<&str>) {
        self.append_comment_with_prefix(comment, "//");
    }

    /// Documentation rendering with "///" prefix.
    /// Mirrors Swift's `appendInterpolation(documentation:)`.
    pub fn append_documentation(&mut self, doc: Option<&str>) {
        self.append_comment_with_prefix(doc, "///");
    }

    // MARK: - Helpers

    /// Comment rendering with configurable prefix.
    /// Mirrors Swift's private `appendInterpolation(comment:withLinePrefix:)`.
    fn append_comment_with_prefix(&mut self, comment: Option<&str>, prefix: &str) {
        match comment {
            Some(c) if !c.is_empty() => {
                let parts: Vec<&str> = c.split('\n').collect();
                let result = joined_as_comment_lines(&parts, prefix);
                self.append_string(&result);
            }
            _ => {
                self.remove_line_if_empty();
            }
        }
    }

    /// Get the current indentation from the buffer.
    /// Mirrors Swift's `getCurrentIndent()`.
    ///
    /// Scans buffer backwards from end to find the last newline,
    /// then extracts leading whitespace (spaces and tabs only).
    pub fn get_current_indent(&self) -> String {
        let line_start = self
            .buffer
            .rfind('\n')
            .map(|pos| pos + 1)
            .unwrap_or(0);

        self.buffer[line_start..]
            .chars()
            .take_while(|c| *c == ' ' || *c == '\t')
            .collect()
    }

    /// Remove the current line if it contains only whitespace.
    /// Mirrors Swift's `removeLineIfEmpty()`.
    ///
    /// Scans backwards from the current buffer end to find the start
    /// of the current line. If everything from line start to end is
    /// whitespace, truncates the buffer and sets `last_line_was_removed`.
    pub fn remove_line_if_empty(&mut self) {
        let line_start = self
            .buffer
            .rfind('\n')
            .map(|pos| pos + 1)
            .unwrap_or(0);

        let current_line = &self.buffer[line_start..];
        if current_line.chars().all(|c| c.is_whitespace()) {
            let new_len = line_start;
            self.buffer.truncate(new_len);
            self.last_line_was_removed = true;
        }
    }

    /// Build the final TemplateString from the accumulated buffer.
    /// Mirrors Swift's `output` computed property.
    ///
    /// If `last_line_was_removed` and buffer ends with '\n',
    /// drops the trailing newline.
    pub fn build(self) -> TemplateString {
        let mut value = self.buffer;
        if self.last_line_was_removed && value.ends_with('\n') {
            value.pop();
        }
        TemplateString::from_builder(value, self.last_line_was_removed)
    }
}

impl Default for TemplateStringBuilder {
    fn default() -> Self {
        Self::new()
    }
}

// MARK: - Helper Functions

/// Join string parts with indentation.
/// Mirrors Swift's `Array<Substring>.joinedAsLines(withIndent:)`.
///
/// First part: no indent. Each subsequent part: `\n` + indent + content
/// (or just `\n` if the part is empty).
pub fn joined_as_lines(parts: &[&str], indent: &str) -> String {
    let mut result = String::new();
    let mut iter = parts.iter();

    if let Some(first) = iter.next() {
        result.push_str(first);
    }

    for part in iter {
        result.push('\n');
        if !part.is_empty() {
            result.push_str(indent);
            result.push_str(part);
        }
    }

    result
}

/// Join string parts as comment lines with a prefix.
/// Mirrors Swift's `Array<Substring>.joinedAsCommentLines(withLinePrefix:)`.
///
/// Each line: prefix + (space + content if non-empty, or just prefix for empty lines).
/// CRITICAL (Pitfall 6): Empty lines get ONLY the prefix, no trailing space.
pub fn joined_as_comment_lines(parts: &[&str], prefix: &str) -> String {
    let mut result = String::new();
    let mut iter = parts.iter();

    if let Some(first) = iter.next() {
        result.push_str(prefix);
        if !first.is_empty() {
            result.push(' ');
            result.push_str(first);
        }
    }

    for part in iter {
        result.push('\n');
        result.push_str(prefix);
        if !part.is_empty() {
            result.push(' ');
            result.push_str(part);
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    // MARK: - TemplateString tests

    #[test]
    fn template_string_new() {
        let ts = TemplateString::new("hello".to_string());
        assert_eq!(ts.description(), "hello");
        assert!(!ts.is_empty());
    }

    #[test]
    fn template_string_empty() {
        let ts = TemplateString::new(String::new());
        assert!(ts.is_empty());
        assert_eq!(ts.description(), "");
    }

    #[test]
    fn template_string_display() {
        let ts = TemplateString::new("world".to_string());
        assert_eq!(format!("{}", ts), "world");
    }

    #[test]
    fn template_string_add_operator() {
        let ts = TemplateString::new("world".to_string());
        let result = "hello ".to_string() + ts;
        assert_eq!(result.description(), "hello world");
    }

    // MARK: - TemplateStringBuilder: append_literal tests

    #[test]
    fn append_literal_basic() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("hello");
        assert_eq!(builder.build().description(), "hello");
    }

    #[test]
    fn append_literal_empty_is_noop() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("hello");
        builder.append_literal("");
        builder.append_literal(" world");
        assert_eq!(builder.build().description(), "hello world");
    }

    #[test]
    fn append_literal_skips_newline_after_line_removal() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        // Simulate a remove_line_if_empty (e.g., from if:false)
        builder.remove_line_if_empty();
        // The next literal starts with \n, which should be skipped
        builder.append_literal("\nline3");
        assert_eq!(builder.build().description(), "line1\nline3");
    }

    #[test]
    fn append_literal_does_not_skip_newline_when_no_removal() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1");
        builder.append_literal("\nline2");
        assert_eq!(builder.build().description(), "line1\nline2");
    }

    // MARK: - TemplateStringBuilder: get_current_indent tests

    #[test]
    fn get_current_indent_empty_buffer() {
        let builder = TemplateStringBuilder::new();
        assert_eq!(builder.get_current_indent(), "");
    }

    #[test]
    fn get_current_indent_spaces() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        assert_eq!(builder.get_current_indent(), "  ");
    }

    #[test]
    fn get_current_indent_tabs() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n\t\t");
        assert_eq!(builder.get_current_indent(), "\t\t");
    }

    #[test]
    fn get_current_indent_no_newline() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("  hello");
        assert_eq!(builder.get_current_indent(), "  ");
    }

    #[test]
    fn get_current_indent_mixed() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  \t");
        assert_eq!(builder.get_current_indent(), "  \t");
    }

    #[test]
    fn get_current_indent_with_content_after_whitespace() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  content");
        assert_eq!(builder.get_current_indent(), "  ");
    }

    // MARK: - TemplateStringBuilder: remove_line_if_empty tests

    #[test]
    fn remove_line_if_empty_whitespace_only_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.remove_line_if_empty();
        // The "  " line was removed, buffer should be "line1\n"
        // But build() will drop trailing \n because last_line_was_removed is true
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn remove_line_if_empty_does_nothing_for_nonempty() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  content");
        builder.remove_line_if_empty();
        assert_eq!(builder.build().description(), "line1\n  content");
    }

    #[test]
    fn remove_line_if_empty_at_buffer_start() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("  ");
        builder.remove_line_if_empty();
        assert_eq!(builder.build().description(), "");
    }

    // MARK: - TemplateStringBuilder: build tests

    #[test]
    fn build_drops_trailing_newline_after_removal() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.remove_line_if_empty();
        // Buffer is now "line1\n", last_line_was_removed=true
        // build() should drop the trailing \n
        let result = builder.build();
        assert_eq!(result.description(), "line1");
    }

    #[test]
    fn build_preserves_trailing_newline_without_removal() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n");
        let result = builder.build();
        assert_eq!(result.description(), "line1\n");
    }

    // MARK: - TemplateStringBuilder: append_string tests

    #[test]
    fn append_string_no_indent() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_string("hello");
        assert_eq!(builder.build().description(), "hello");
    }

    #[test]
    fn append_string_with_indent() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("struct Foo {\n  ");
        builder.append_string("var x: Int\nvar y: Int");
        builder.append_literal("\n}");
        let result = builder.build();
        assert_eq!(
            result.description(),
            "struct Foo {\n  var x: Int\n  var y: Int\n}"
        );
    }

    // MARK: - TemplateStringBuilder: append_template tests

    #[test]
    fn append_template_some() {
        let mut builder = TemplateStringBuilder::new();
        let ts = TemplateString::new("hello".to_string());
        builder.append_template(Some(&ts));
        assert_eq!(builder.build().description(), "hello");
    }

    #[test]
    fn append_template_none() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_template(None);
        // Line with only whitespace is removed
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn append_template_empty() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        let ts = TemplateString::new(String::new());
        builder.append_template(Some(&ts));
        // Empty template triggers remove_line_if_empty
        assert_eq!(builder.build().description(), "line1");
    }

    // MARK: - TemplateStringBuilder: append_if tests

    #[test]
    fn append_if_true() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_if(
            true,
            || TemplateString::new("yes".to_string()),
            None::<fn() -> TemplateString>,
        );
        assert_eq!(builder.build().description(), "yes");
    }

    #[test]
    fn append_if_false_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_if(
            false,
            || TemplateString::new("skipped".to_string()),
            None::<fn() -> TemplateString>,
        );
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn append_if_false_with_else() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_if(
            false,
            || TemplateString::new("skipped".to_string()),
            Some(|| TemplateString::new("fallback".to_string())),
        );
        assert_eq!(builder.build().description(), "fallback");
    }

    // MARK: - TemplateStringBuilder: append_if_let tests

    #[test]
    fn append_if_let_some() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_if_let(
            Some("value"),
            |v: &str| TemplateString::new(format!("got {}", v)),
            None::<fn(&&str) -> bool>,
            None::<fn() -> TemplateString>,
        );
        assert_eq!(builder.build().description(), "got value");
    }

    #[test]
    fn append_if_let_none_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_if_let(
            None::<String>,
            |_v: String| TemplateString::new("unreachable".to_string()),
            None::<fn(&String) -> bool>,
            None::<fn() -> TemplateString>,
        );
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn append_if_let_none_with_else() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_if_let(
            None::<String>,
            |_v: String| TemplateString::new("unreachable".to_string()),
            None::<fn(&String) -> bool>,
            Some(|| TemplateString::new("fallback".to_string())),
        );
        assert_eq!(builder.build().description(), "fallback");
    }

    // MARK: - TemplateStringBuilder: append_for_each_in tests

    #[test]
    fn append_for_each_in_basic() {
        let mut builder = TemplateStringBuilder::new();
        let items = vec!["a", "b", "c"];
        builder.append_for_each_in(
            items.into_iter(),
            ",\n",
            None,
            None::<fn(&&str) -> bool>,
            |s| Some(TemplateString::new(s.to_string())),
        );
        assert_eq!(builder.build().description(), "a,\nb,\nc");
    }

    #[test]
    fn append_for_each_in_empty_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        let items: Vec<&str> = vec![];
        builder.append_for_each_in(
            items.into_iter(),
            ",\n",
            None,
            None::<fn(&&str) -> bool>,
            |s| Some(TemplateString::new(s.to_string())),
        );
        assert_eq!(builder.build().description(), "line1");
    }

    #[test]
    fn append_for_each_in_with_terminator() {
        let mut builder = TemplateStringBuilder::new();
        let items = vec!["a", "b"];
        builder.append_for_each_in(
            items.into_iter(),
            ", ",
            Some(";"),
            None::<fn(&&str) -> bool>,
            |s| Some(TemplateString::new(s.to_string())),
        );
        assert_eq!(builder.build().description(), "a, b;");
    }

    // MARK: - TemplateStringBuilder: append_list tests

    #[test]
    fn append_list_single_item() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_list(&["item1"], ",\n", None);
        assert_eq!(builder.build().description(), "item1");
    }

    #[test]
    fn append_list_multiple_items() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_list(&["item1", "item2", "item3"], ",\n", None);
        assert_eq!(
            builder.build().description(),
            "\n  item1,\n  item2,\n  item3\n"
        );
    }

    // MARK: - TemplateStringBuilder: append_comment tests

    #[test]
    fn append_comment_single_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_comment(Some("hello"));
        assert_eq!(builder.build().description(), "// hello");
    }

    #[test]
    fn append_comment_multi_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_comment(Some("line1\nline2"));
        assert_eq!(builder.build().description(), "// line1\n// line2");
    }

    #[test]
    fn append_comment_none_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_comment(None);
        assert_eq!(builder.build().description(), "line1");
    }

    // MARK: - TemplateStringBuilder: append_documentation tests

    #[test]
    fn append_documentation_single_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_documentation(Some("hello"));
        assert_eq!(builder.build().description(), "/// hello");
    }

    #[test]
    fn append_documentation_with_empty_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_documentation(Some("First line\n\nThird line"));
        // CRITICAL (Pitfall 6): Empty line gets "///" with NO trailing space
        assert_eq!(
            builder.build().description(),
            "/// First line\n///\n/// Third line"
        );
    }

    #[test]
    fn append_documentation_none_removes_line() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n  ");
        builder.append_documentation(None);
        assert_eq!(builder.build().description(), "line1");
    }

    // MARK: - TemplateStringBuilder: append_section tests

    #[test]
    fn append_section_nonempty() {
        let mut builder = TemplateStringBuilder::new();
        let section = TemplateString::new("content".to_string());
        builder.append_section(&section);
        assert_eq!(builder.build().description(), "content");
    }

    #[test]
    fn append_section_empty_removes_trailing_newline() {
        let mut builder = TemplateStringBuilder::new();
        builder.append_literal("line1\n");
        let section = TemplateString::new(String::new());
        builder.append_section(&section);
        assert_eq!(builder.build().description(), "line1");
    }

    // MARK: - Helper function tests

    #[test]
    fn joined_as_lines_basic() {
        let parts = vec!["first", "second", "third"];
        let result = joined_as_lines(&parts, "  ");
        assert_eq!(result, "first\n  second\n  third");
    }

    #[test]
    fn joined_as_lines_with_empty() {
        let parts = vec!["first", "", "third"];
        let result = joined_as_lines(&parts, "  ");
        assert_eq!(result, "first\n\n  third");
    }

    #[test]
    fn joined_as_lines_single() {
        let parts = vec!["only"];
        let result = joined_as_lines(&parts, "  ");
        assert_eq!(result, "only");
    }

    #[test]
    fn joined_as_comment_lines_basic() {
        let parts = vec!["first", "second"];
        let result = joined_as_comment_lines(&parts, "///");
        assert_eq!(result, "/// first\n/// second");
    }

    #[test]
    fn joined_as_comment_lines_with_empty() {
        let parts = vec!["first", "", "third"];
        let result = joined_as_comment_lines(&parts, "///");
        // Empty line gets only prefix, no trailing space (Pitfall 6)
        assert_eq!(result, "/// first\n///\n/// third");
    }

    #[test]
    fn joined_as_comment_lines_single() {
        let parts = vec!["only"];
        let result = joined_as_comment_lines(&parts, "//");
        assert_eq!(result, "// only");
    }
}
