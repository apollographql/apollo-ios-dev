# Follow-up Instructions

You were mentioned in a comment in `apollographql/apollo-ios-dev`. If the pull
request carries the `claude-triage` label, it was opened by the automated triage
of an `apollographql/apollo-ios` issue. Its body holds the original issue link,
the triage summary, any open questions, and a draft reply. A draft PR with no
file changes is a tracking record waiting for a decision. The maintainer's
comment answers those questions or gives instructions. Continue the triage with
that new information.

Rules:

- Read `CLAUDE.md`, `claude/code-style.md`, and the relevant `claude/*.md`
  before changing code.
- Re-read the upstream issue with
  `gh issue view <N> --repo apollographql/apollo-ios --comments`
  before acting; new comments may have arrived.
- Your `gh` token is always a bot identity (the Claude GitHub App or the
  team's bot app), never a person's account. Post on the upstream issue only
  when the maintainer's comment in this thread explicitly asks for it. Post
  exactly the approved text with
  `gh issue comment <N> --repo apollographql/apollo-ios --body-file - <<'EOF' ... EOF`,
  append the footer
  `---\n_This reply was generated automatically by the Apollo iOS team's AI assistant after reviewing the code. It may be incomplete; a maintainer will follow up if needed._`,
  and report the comment URL. If the post fails with a permission error, the
  bot has no access to the upstream repo: reply here with the final text in a
  fenced block so the maintainer can paste it, and say that posting failed.
- When implementing a fix on a tracking PR, work on the PR branch, follow
  `.github/claude/triage-instructions.md` steps 3 and 4 for scope,
  verification, and commit hygiene, stage files by path, push, then run
  `gh pr ready <PR>` and `gh pr edit <PR> --title "<fix title> (apollo-ios#<N>)"`
  so the PR reads as a real fix. Keep `apollo-ios#<N>` in the title; it is the
  dedup key that stops the issue from being triaged again.
- When the maintainer says the issue needs no code change, post the agreed
  upstream reply if asked, then `gh pr close <PR> --delete-branch`.
- If a question remains unanswered, ask it in your reply and stop. Do not guess.
- Keep replies short. Lead with what you did, then links.
