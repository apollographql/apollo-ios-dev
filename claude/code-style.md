# Code Style

Conventions for code written in this repository (including the `apollo-ios`,
`apollo-ios-codegen`, and `apollo-ios-pagination` subtrees). These live in
`claude/` rather than a subtree directory so they are not pushed upstream.

## Comments

Strive to write self-documenting code that does not need comments. Clear naming
and structure should carry the meaning before a comment does.

- **Do not add a comment for every change or fix.** A fix does not need an
  inline explanation just because it was a fix. Rationale for *why* a change was
  made belongs in the commit message (and, for CI/infra, in the relevant doc
  such as `claude/ci-subtree-troubleshooting.md`) — not in an inline comment.
- **Public symbol documentation** explains *what* a symbol does and how to use
  it — not *why* the code was written the way it was.
- **Inline comments within a function body** should be as concise as possible.
  Prefer them for organizing and signposting longer bodies of code for
  readability. Only explain the code itself in genuinely complex situations
  where the intent is not clear from the code alone.
