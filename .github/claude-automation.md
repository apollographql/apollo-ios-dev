# Claude Automation

Three workflows use [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)
to review pull requests and triage upstream issues. Claude's standing
instructions live in `.github/claude/` so they can be tuned without touching
workflow YAML.

| Workflow | Trigger | What it does |
|---|---|---|
| `claude-pr-review.yml` | PRs opened, updated, or marked ready | Reviews the diff against `CLAUDE.md`, `claude/code-style.md`, and the subtree context files. Posts inline comments plus one sticky summary. Skips drafts, forks, and CI bots. |
| `claude-issue-triage.yml` | Every 30 minutes, manual, or `repository_dispatch` | Finds new `apollographql/apollo-ios` issues, triages each one, and publishes a result (below). |
| `claude-followup.yml` | `@claude` in any issue or PR comment here | Continues a triage from your answers, or does whatever you ask on a PR. |

## Identity and authentication

Two separate credentials are involved:

- **Model credential.** One of two secrets, whichever is set:
  - `CLAUDE_CODE_OAUTH_TOKEN`: an **organization secret** that IT (Joshua
    Phillips) created in August 2026 and grants to repositories on request.
    Other Apollo repos, for example `mdg-private/constellation-policy-eval`,
    use it. Ask Josh to add `apollo-ios-dev` to its repository list; no new
    key is provisioned.
  - `CLAUDE_API_KEY`: an **organization secret** holding an Anthropic Console
    key, created by IT in September 2026 for GitHub Actions use. It must be
    granted to this repository like any selected-repo org secret. A repo
    secret named `ANTHROPIC_API_KEY` is accepted as a fallback for anyone
    provisioning their own Console key (Console access is requested through
    `/assist`; spend limits are covered by the "Usage and Budgets in Claude"
    Confluence page).
- **GitHub identity.** With no `github_token` input, the action authenticates
  as the **Claude GitHub App** installed on the `apollographql` org, so every
  push, PR, and comment shows as `claude[bot]`. No PAT is involved, and PRs
  opened this way still trigger CI.

Replies to reporters on `apollographql/apollo-ios` are posted only under a bot
identity, never a person's account. The Claude App token may be scoped to this
repository alone; if a post fails for lack of access, the draft is routed to
you instead and the log says so. To guarantee upstream posting, create a
small org-owned GitHub App (permissions: Issues read/write, Pull requests
read/write, Contents read/write; install on `apollo-ios` and `apollo-ios-dev`)
and set the `CLAUDE_BOT_APP_ID` variable and `CLAUDE_BOT_APP_PRIVATE_KEY`
secret. When present, that app is preferred for upstream posts and for the
follow-up workflow's `gh` calls.

`APOLLO_IOS_PAT` (your account) is used only as a last resort to open a
"triage failed" tracking PR when the Claude step produced no token. It is never
used to post upstream.

## Triage outcomes

Claude classifies each issue (`bug`, `question`, `feature`, `unclear`) and
rates its confidence in the proposed action. `high` requires locating the exact
code, needing no guesses about the reporter's setup, and, for a fix, a build and
targeted test run that pass. Features and unclear reports are never `high`.

| Outcome | Result |
|---|---|
| `bug` + `high`, fix verified | Branch `claude/triage/apollo-ios-<N>` is pushed and a ready-for-review PR opens with you as reviewer. The PR review workflow reviews it like any other PR. |
| `high` with a drafted reply | Reply is posted on the upstream issue by the bot, with a footer stating it was AI-generated and a maintainer will follow up. Disable with the `CLAUDE_TRIAGE_AUTO_COMMENT` variable set to `false`. |
| Anything else | A draft tracking PR `[triage] apollo-ios#<N>: ...` opens on an **empty commit** (no files are committed), assigned to you and labeled `needs-input`. Its description holds the summary, the questions whose answers would change the next step, and any draft reply. |

Nothing from triage is written into the repository tree. Draft replies exist
only in the PR description, the Slack alert, and the run artifact.

Every outcome sends a Slack message to `#alerts-client-ios` (the default;
override with `CLAUDE_TRIAGE_SLACK_CHANNEL_ID`, or set it to your member ID for
DMs). The Slack app behind `SLACK_BOT_TOKEN` must be a member of the channel.
The needs-input message carries the full summary, questions, and draft reply
so you can act from Slack. GitHub also emails you on assignment.

The tracking PR is the dedup record: an issue is skipped while a PR labeled
`claude-triage` with `apollo-ios#<N>` in its title exists (open or closed).
Empty-commit PRs change no files, so `ci-tests.yml` (which has a `paths-ignore`
filter) does not run for them.

Answer a tracking PR by commenting with `@claude` and your decision. Claude
re-reads the upstream issue, implements the fix on that branch and marks the PR
ready, posts the approved reply upstream, or closes the PR, per your comment.

## Setup

Secrets:

| Secret | Purpose |
|---|---|
| `CLAUDE_API_KEY` | Org secret (Anthropic Console key); IT must grant this repo access. Preferred. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Org secret (Claude Code OAuth token); alternative if granted instead. |
| `ANTHROPIC_API_KEY` | Repo-level fallback for a self-provisioned Console key. Set only one credential. |
| `SLACK_BOT_TOKEN` | Existing. Needs `chat:write` (and `im:write` for DMs). |
| `CLAUDE_BOT_APP_PRIVATE_KEY` | Optional custom bot app, see above. |
| `APOLLO_IOS_PAT` | Existing. Last-resort fallback only. |

Variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_MODEL` | `claude-opus-5` | Model for all workflows. |
| `CLAUDE_TRIAGE_ASSIGNEE` | `AnthonyMDev` | Assigned to tracking PRs, requested as reviewer on fix PRs. |
| `CLAUDE_TRIAGE_AUTO_COMMENT` | `true` | Post high-confidence replies upstream (bot identity only). |
| `CLAUDE_TRIAGE_SLACK_CHANNEL_ID` | `C06VAE92F7A` (#alerts-client-ios) | Slack channel ID or member ID for alerts. |
| `CLAUDE_TRIAGE_LOOKBACK_DAYS` | `3` | Only issues created within this window are picked up by the poll. |
| `CLAUDE_TRIAGE_MAX_PER_RUN` | `3` | Cap on issues triaged per poll. |
| `CLAUDE_BOT_APP_ID` | unset | Optional custom bot app, see above. |

## Running triage by hand

Actions → Claude Issue Triage → Run workflow. Leave `issue_number` blank to
poll, or set it to triage one issue. Set `force` to re-triage an issue that
already has a tracking PR. From the CLI:

```bash
gh workflow run claude-issue-triage.yml -f issue_number=3654 -f force=true
```

To trigger from the upstream repo instead of polling, dispatch the
`apollo-ios-issue` event with `{"issue_number": N}` as the client payload.

## Cost notes

Triage and follow-up run on `macos-26` so Claude can run `swift build` and
targeted `xcodebuild` tests before proposing a fix. The 30-minute poll itself
runs on `ubuntu-latest` and spawns macOS jobs only when there is something to
triage. PR review runs on `ubuntu-latest` and does not build.
