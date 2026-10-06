//! Code generator for the `template_string!` proc macro.
//!
//! Takes a `Vec<TemplateNode>` AST from the parser and produces
//! Rust code that creates a `TemplateStringBuilder`, calls the
//! appropriate `append_*` methods, and returns a `TemplateString`.
//!
//! All generated code uses fully qualified paths
//! (`::template_string::TemplateString`, `::template_string::TemplateStringBuilder`)
//! so the macro works regardless of the user's imports.

use proc_macro2::TokenStream;
use quote::quote;

use crate::parser::TemplateNode;

/// Generate Rust code from a vector of template nodes.
///
/// Produces a block expression:
/// ```ignore
/// {
///     let mut __builder = ::template_string::TemplateStringBuilder::new();
///     __builder.append_literal("...");
///     // ... more append calls ...
///     __builder.build()
/// }
/// ```
pub fn generate(nodes: Vec<TemplateNode>) -> TokenStream {
    let mut statements = Vec::new();

    for node in nodes {
        let stmt = generate_node(node);
        statements.push(stmt);
    }

    quote! {
        {
            let mut __builder = ::template_string::TemplateStringBuilder::new();
            #(#statements)*
            __builder.build()
        }
    }
}

/// Generate the code for a single template node.
fn generate_node(node: TemplateNode) -> TokenStream {
    match node {
        TemplateNode::Literal(s) => {
            quote! {
                __builder.append_literal(#s);
            }
        }

        TemplateNode::StringInterpolation(expr) => {
            quote! {
                __builder.append_string(&(#expr).to_string());
            }
        }

        TemplateNode::If {
            condition,
            then_expr,
            else_expr,
        } => {
            let else_arm = match else_expr {
                Some(expr) => quote! {
                    Some(|| {
                        let __val = #expr;
                        if let Some(__ts) = __to_opt_template_string(__val) {
                            __ts
                        } else {
                            ::template_string::TemplateString::new(String::new())
                        }
                    })
                },
                None => quote! { None::<fn() -> ::template_string::TemplateString> },
            };

            quote! {
                {
                    // Helper to convert various types to Option<TemplateString>
                    #[allow(unused)]
                    fn __to_opt_template_string<T: ::std::fmt::Display>(val: T) -> Option<::template_string::TemplateString> {
                        let s = val.to_string();
                        Some(::template_string::TemplateString::new(s))
                    }
                    __builder.append_if(
                        #condition,
                        || {
                            let __val = #then_expr;
                            if let Some(__ts) = __to_opt_template_string(__val) {
                                __ts
                            } else {
                                ::template_string::TemplateString::new(String::new())
                            }
                        },
                        #else_arm,
                    );
                }
            }
        }

        TemplateNode::IfLet {
            binding,
            source,
            body,
            where_block,
            else_expr,
        } => {
            let where_arm = match where_block {
                Some(expr) => quote! { Some(#expr) },
                None => quote! { None::<fn(&_) -> bool> },
            };

            let else_arm = match else_expr {
                Some(expr) => quote! {
                    Some(|| {
                        let __val = #expr;
                        ::template_string::TemplateString::new(__val.to_string())
                    })
                },
                None => quote! { None::<fn() -> ::template_string::TemplateString> },
            };

            quote! {
                __builder.append_if_let(
                    #source,
                    |#binding| {
                        let __val = #body;
                        ::template_string::TemplateString::new(__val.to_string())
                    },
                    #where_arm,
                    #else_arm,
                );
            }
        }

        TemplateNode::ForEachIn {
            binding,
            source,
            body,
            separator,
            terminator,
            where_block,
        } => {
            let sep = match separator {
                Some(expr) => quote! { #expr },
                None => quote! { ",\n" },
            };

            let term = match terminator {
                Some(expr) => quote! { Some(#expr) },
                None => quote! { None },
            };

            let where_arm = match where_block {
                Some(expr) => quote! { Some(#expr) },
                None => quote! { None::<fn(&_) -> bool> },
            };

            quote! {
                __builder.append_for_each_in(
                    #source,
                    #sep,
                    #term,
                    #where_arm,
                    |#binding| {
                        let __val = #body;
                        Some(::template_string::TemplateString::new(__val.to_string()))
                    },
                );
            }
        }

        TemplateNode::List {
            source,
            separator,
            terminator,
        } => {
            let sep = match separator {
                Some(expr) => quote! { #expr },
                None => quote! { ",\n" },
            };

            let term = match terminator {
                Some(expr) => quote! { Some(#expr) },
                None => quote! { None },
            };

            quote! {
                __builder.append_list(&(#source), #sep, #term);
            }
        }

        TemplateNode::Comment(expr) => {
            quote! {
                __builder.append_comment((#expr).as_deref());
            }
        }

        TemplateNode::Documentation(expr) => {
            quote! {
                __builder.append_documentation((#expr).as_deref());
            }
        }

        TemplateNode::Section(expr) => {
            quote! {
                {
                    let __section = #expr;
                    __builder.append_section(&__section);
                }
            }
        }
    }
}
