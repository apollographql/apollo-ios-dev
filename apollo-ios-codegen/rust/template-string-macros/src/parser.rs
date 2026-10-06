//! Template syntax parser for the `template_string!` proc macro.
//!
//! Parses a token stream of alternating string literals and
//! `{keyword: ...}` interpolation blocks into a `Vec<TemplateNode>` AST.
//!
//! The parser recognizes:
//! - String literals -> `TemplateNode::Literal`
//! - `{expr}` -> `TemplateNode::StringInterpolation`
//! - `{if: cond, then_expr}` / `{if: cond, then_expr, else: else_expr}`
//! - `{ifLet: source, |binding| body}` / with else clause
//! - `{forEachIn: source, |binding| body}` / with separator, terminator, where
//! - `{list: source}` / with separator, terminator
//! - `{comment: expr}` / `{documentation: expr}`
//! - `{section: expr}`

use proc_macro2::TokenStream;
use syn::{
    braced,
    ext::IdentExt,
    parse::{Parse, ParseStream},
    Expr, Ident, LitStr, Pat, Token,
};

/// AST nodes representing the parsed template.
pub enum TemplateNode {
    /// A string literal in the template.
    Literal(String),
    /// A simple expression interpolation: `{expr}`
    /// Generates: `builder.append_string(&(expr).to_string())`
    StringInterpolation(Expr),
    /// Conditional rendering: `{if: cond, then}` or `{if: cond, then, else: otherwise}`
    If {
        condition: Expr,
        then_expr: Expr,
        else_expr: Option<Expr>,
    },
    /// Optional unwrapping: `{ifLet: source, |binding| body}` or with else
    IfLet {
        binding: Pat,
        source: Expr,
        body: Expr,
        where_block: Option<Expr>,
        else_expr: Option<Expr>,
    },
    /// Iteration: `{forEachIn: source, |binding| body}` with optional separator, terminator, where
    ForEachIn {
        binding: Pat,
        source: Expr,
        body: Expr,
        separator: Option<Expr>,
        terminator: Option<Expr>,
        where_block: Option<Expr>,
    },
    /// List rendering: `{list: source}` with optional separator, terminator
    List {
        source: Expr,
        separator: Option<Expr>,
        terminator: Option<Expr>,
    },
    /// Comment prefixing: `{comment: expr}`
    Comment(Expr),
    /// Documentation prefixing: `{documentation: expr}`
    Documentation(Expr),
    /// Section rendering: `{section: expr}`
    Section(Expr),
}

/// Top-level parser that collects all nodes from the template.
struct TemplateInput {
    nodes: Vec<TemplateNode>,
}

impl Parse for TemplateInput {
    fn parse(input: ParseStream<'_>) -> syn::Result<Self> {
        let mut nodes = Vec::new();

        while !input.is_empty() {
            if input.peek(LitStr) {
                // String literal
                let lit: LitStr = input.parse()?;
                nodes.push(TemplateNode::Literal(lit.value()));
            } else if input.peek(syn::token::Brace) {
                // Interpolation block
                let content;
                braced!(content in input);
                let node = parse_interpolation(&content)?;
                nodes.push(node);
            } else {
                return Err(input.error(
                    "expected string literal or {interpolation} block",
                ));
            }
        }

        Ok(TemplateInput { nodes })
    }
}

/// Try to parse a keyword identifier (handles Rust keywords like `if`, `else`, `where`).
/// Uses `Ident::parse_any` which accepts keywords as identifiers.
fn try_parse_keyword_ident(input: ParseStream<'_>) -> Option<String> {
    // We need to check if the next token is an ident-like token followed by ':'
    // Use a speculative parse to avoid consuming tokens on failure
    let fork = input.fork();
    if let Ok(ident) = Ident::parse_any(&fork) {
        if fork.peek(Token![:]) {
            return Some(ident.to_string());
        }
    }
    None
}

/// Parse the contents of a `{...}` interpolation block.
fn parse_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    // Check for named interpolations by peeking at ident/keyword followed by colon
    if let Some(keyword) = try_parse_keyword_ident(input) {
        match keyword.as_str() {
            "if" | "ifLet" | "forEachIn" | "list" | "comment" | "documentation" | "section" => {
                // Consume the ident and colon for real
                let _ident = Ident::parse_any(input)?;
                let _colon: Token![:] = input.parse()?;

                match keyword.as_str() {
                    "if" => parse_if_interpolation(input),
                    "ifLet" => parse_if_let_interpolation(input),
                    "forEachIn" => parse_for_each_in_interpolation(input),
                    "list" => parse_list_interpolation(input),
                    "comment" => parse_comment_interpolation(input),
                    "documentation" => parse_documentation_interpolation(input),
                    "section" => parse_section_interpolation(input),
                    _ => unreachable!(),
                }
            }
            _ => {
                // Not a known keyword, treat as expression
                let expr: Expr = input.parse()?;
                Ok(TemplateNode::StringInterpolation(expr))
            }
        }
    } else {
        // Simple expression interpolation
        let expr: Expr = input.parse()?;
        Ok(TemplateNode::StringInterpolation(expr))
    }
}

/// Parse a trailing keyword argument identifier.
/// Handles Rust keywords (`else`, `where`) as well as regular identifiers.
fn parse_keyword_arg(input: ParseStream<'_>) -> syn::Result<String> {
    let ident = Ident::parse_any(input)?;
    Ok(ident.to_string())
}

/// Parse `{if: condition, then_expr}` or `{if: condition, then_expr, else: else_expr}`
fn parse_if_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let condition: Expr = parse_expr_before_comma(input)?;
    let _comma: Token![,] = input.parse()?;
    let then_expr: Expr = parse_expr_before_comma(input)?;

    let else_expr = if input.peek(Token![,]) {
        let _comma: Token![,] = input.parse()?;
        // Expect "else:"
        let kw = parse_keyword_arg(input)?;
        if kw != "else" {
            return Err(input.error(format!("expected `else`, found `{}`", kw)));
        }
        let _colon: Token![:] = input.parse()?;
        let expr: Expr = input.parse()?;
        Some(expr)
    } else {
        None
    };

    Ok(TemplateNode::If {
        condition,
        then_expr,
        else_expr,
    })
}

/// Parse `{ifLet: source, |binding| body}` with optional where and else
fn parse_if_let_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let source: Expr = parse_expr_before_comma(input)?;
    let _comma: Token![,] = input.parse()?;

    // Parse closure: |binding| body
    let _pipe1: Token![|] = input.parse()?;
    let binding: Pat = Pat::parse_single(input)?;
    let _pipe2: Token![|] = input.parse()?;
    let body: Expr = parse_expr_before_comma(input)?;

    let mut where_block = None;
    let mut else_expr = None;

    // Optional trailing arguments
    while input.peek(Token![,]) {
        let _comma: Token![,] = input.parse()?;
        if input.is_empty() {
            break;
        }
        let kw = parse_keyword_arg(input)?;
        let _colon: Token![:] = input.parse()?;

        match kw.as_str() {
            "where" => {
                where_block = Some(input.parse()?);
            }
            "else" => {
                else_expr = Some(input.parse()?);
            }
            other => {
                return Err(input.error(format!(
                    "unexpected keyword `{}` in ifLet, expected `where` or `else`",
                    other
                )));
            }
        }
    }

    Ok(TemplateNode::IfLet {
        binding,
        source,
        body,
        where_block,
        else_expr,
    })
}

/// Parse `{forEachIn: source, |binding| body}` with optional separator, terminator, where
fn parse_for_each_in_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let source: Expr = parse_expr_before_comma(input)?;
    let _comma: Token![,] = input.parse()?;

    // Parse closure: |binding| body
    let _pipe1: Token![|] = input.parse()?;
    let binding: Pat = Pat::parse_single(input)?;
    let _pipe2: Token![|] = input.parse()?;
    let body: Expr = parse_expr_before_comma(input)?;

    let mut separator = None;
    let mut terminator = None;
    let mut where_block = None;

    // Optional trailing arguments
    while input.peek(Token![,]) {
        let _comma: Token![,] = input.parse()?;
        if input.is_empty() {
            break;
        }
        let kw = parse_keyword_arg(input)?;
        let _colon: Token![:] = input.parse()?;

        match kw.as_str() {
            "separator" => {
                separator = Some(parse_expr_before_comma(input)?);
            }
            "terminator" => {
                terminator = Some(parse_expr_before_comma(input)?);
            }
            "where" => {
                where_block = Some(parse_expr_before_comma(input)?);
            }
            other => {
                return Err(input.error(format!(
                    "unexpected keyword `{}` in forEachIn, expected `separator`, `terminator`, or `where`",
                    other
                )));
            }
        }
    }

    Ok(TemplateNode::ForEachIn {
        binding,
        source,
        body,
        separator,
        terminator,
        where_block,
    })
}

/// Parse `{list: source}` with optional separator, terminator
fn parse_list_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let source: Expr = parse_expr_before_comma(input)?;

    let mut separator = None;
    let mut terminator = None;

    // Optional trailing arguments
    while input.peek(Token![,]) {
        let _comma: Token![,] = input.parse()?;
        if input.is_empty() {
            break;
        }
        let kw = parse_keyword_arg(input)?;
        let _colon: Token![:] = input.parse()?;

        match kw.as_str() {
            "separator" => {
                separator = Some(parse_expr_before_comma(input)?);
            }
            "terminator" => {
                terminator = Some(parse_expr_before_comma(input)?);
            }
            other => {
                return Err(input.error(format!(
                    "unexpected keyword `{}` in list, expected `separator` or `terminator`",
                    other
                )));
            }
        }
    }

    Ok(TemplateNode::List {
        source,
        separator,
        terminator,
    })
}

/// Parse `{comment: expr}`
fn parse_comment_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let expr: Expr = input.parse()?;
    Ok(TemplateNode::Comment(expr))
}

/// Parse `{documentation: expr}`
fn parse_documentation_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let expr: Expr = input.parse()?;
    Ok(TemplateNode::Documentation(expr))
}

/// Parse `{section: expr}`
fn parse_section_interpolation(input: ParseStream<'_>) -> syn::Result<TemplateNode> {
    let expr: Expr = input.parse()?;
    Ok(TemplateNode::Section(expr))
}

/// Parse an expression that stops before a comma.
///
/// syn's `Expr::parse` is greedy and will consume commas in some contexts
/// (e.g., tuple expressions). This function uses `Expr::parse` on a fork
/// and handles the common case where we need to stop at a comma delimiter.
///
/// For simple expressions (identifiers, literals, method calls, field access),
/// this works because `Expr::parse` naturally stops at commas.
fn parse_expr_before_comma(input: ParseStream<'_>) -> syn::Result<Expr> {
    // Expr::parse in syn stops at commas in most contexts since commas
    // are not part of most expression forms. The main exception is
    // tuple expressions, but we don't expect those in template positions.
    input.parse()
}

/// Parse a token stream into a vector of template nodes.
pub fn parse(input: TokenStream) -> Vec<TemplateNode> {
    let template_input: TemplateInput =
        syn::parse2(input).expect("failed to parse template_string! input");
    template_input.nodes
}
