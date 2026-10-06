//! `template_string!` proc macro for the TemplateString DSL.
//!
//! This macro translates template syntax into runtime
//! `TemplateStringBuilder` method calls. The proc macro's job is
//! ONLY syntax translation -- all indentation tracking, empty-line
//! removal, and comment formatting happens at runtime.
//!
//! # Syntax
//!
//! The macro accepts alternating string literals and interpolation blocks:
//!
//! ```ignore
//! let result = template_string!(
//!     "prefix " {expr} " suffix\n"
//!     "  " {documentation: field.doc}
//!     "  " {if: condition, "included text"}
//! );
//! ```
//!
//! ## Interpolation types (mirror Swift's names per D-02):
//!
//! - `{expr}` -- string interpolation via `.to_string()`
//! - `{if: cond, then_expr}` / `{if: cond, then_expr, else: else_expr}`
//! - `{ifLet: source, |binding| body}` / with `else:` and `where:` clauses
//! - `{forEachIn: source, |binding| body}` / with `separator:`, `terminator:`, `where:`
//! - `{list: source}` / with `separator:`, `terminator:`
//! - `{comment: expr}` -- prefixes lines with `//`
//! - `{documentation: expr}` -- prefixes lines with `///`
//! - `{section: expr}` -- section rendering with trailing newline removal

extern crate proc_macro;
mod codegen;
mod parser;

use proc_macro::TokenStream;

/// Template string DSL macro.
///
/// Generates a `TemplateString` value by creating a `TemplateStringBuilder`,
/// calling the appropriate `append_*` methods, and building the result.
///
/// All indentation tracking, empty-line removal, and comment formatting
/// happens at runtime in the builder, not at compile time in this macro.
#[proc_macro]
pub fn template_string(input: TokenStream) -> TokenStream {
    let input2 = proc_macro2::TokenStream::from(input);
    let nodes = parser::parse(input2);
    let output = codegen::generate(nodes);
    TokenStream::from(output)
}
