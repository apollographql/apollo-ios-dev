# Claude Automation

Three workflows use [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)
to review pull requests and triage upstream issues. Claude's standing
instructions live in `.github/claude/` so they can be tuned without touching
workflow YAML.

| Workflow | Trigger | What it does |
|---|---|---|
| `claude-pr-review.yml` | Called from `ci-tests.yml` as a job that `needs` every CI job | Runs on the same `pull_request` event as CI, so the action has full PR context, but only after every CI job has finished. Skipped CI jobs count as passing; a failed or cancelled job posts one editable status note instead of a review, so a stale verdict never stands. A newer push cancels a review in flight, so only the latest commit is reviewed. Review instructions are read from `main`, not from the PR. Findings are tiered: blocking and important ones (each with a concrete failure scenario) get inline comments; minors are listed, collapsed, in the summary only. A re-review verifies prior findings and reviews only the new commits, and never raises minors on already-reviewed code, so nits do not cause round after round. Posts a tracking-comment summary. Skips drafts, forks, and CI bots. PRs that touch only `.github/claude/**` do not trigger CI and therefore get no review. |
| `claude-issue-triage.yml` | Every 30 minutes, manual, or `repository_dispatch` | Finds new `apollographql/apollo-ios` issues, and previously triaged issues where the reporter has commented since the last triage, then triages each one. Verified fixes become PRs, high-confidence replies are posted upstream by a bot, everything else is a Slack message (below). |
| `claude-followup.yml` | `@claude` in a PR comment by an owner, member, or collaborator | Continues a triage from your answers, or does whatever you ask on a PR. Only the triggering comment's own text counts as instructions. Posts a Slack notice of what it replied and of anything it opened, marked ready, or sent upstream. |
| `claude-fork-pr-review.yml` | `pull_request_target` (labeled / synchronize / reopened) on a fork PR | Reviews external fork PRs, which `claude-pr-review.yml` skips because a fork's `pull_request` run has no secrets or write token. Gated on the `safe to review` label: a maintainer must apply it (see the approval queue below) before a credentialed job reads fork content. Base branch is checked out at the workspace root and the PR head into `pr-head/` (read-only, via `--add-dir`), so fork-authored config is never loaded as instructions. Third-party actions are SHA-pinned. |
| `fork-review-queue.yml` | Fork `pull_request_target` (opened / reopened / ready_for_review) and manual catch-up | When a fork PR opens, posts a Slack heads-up linking to it. A maintainer approves by adding the `safe to review` label in GitHub's UI (declines with `fork-review-declined`); GitHub gates labeling on write access, so that click is the approval, and it starts the review above. This job only reads PR metadata and posts to Slack: no write token, no label application, no fork checkout. |

## Identity and authentication

Three credentials are involved, and it matters which does what.

- **Model credential.** One of the org secrets `CLAUDE_API_KEY` (Anthropic
  Console key, preferred) or `CLAUDE_CODE_OAUTH_TOKEN`; a repo-level
  `ANTHROPIC_API_KEY` is accepted as a fallback. IT grants org secrets to this
  repository on request. Set only one.
- **Claude GitHub App.** With no `github_token` input, the action authenticates
  as the Claude App installed on the org (via an OIDC exchange), so comments would
  show as `claude[bot]`. Two hard limits, both confirmed in the action's source
  and docs: the token is scoped to this repository only, and the action revokes it
  at the end of its own step, so it cannot post on `apollo-ios` or in a later step.
  The **PR review** does not use this identity: `claude-pr-review.yml` drops
  `id-token: write` (an OIDC token is exchangeable for cloud credentials), and
  without OIDC the App token cannot be minted, so the job passes `github_token`
  instead and its review comments post as `github-actions[bot]` on both the
  same-repo and fork paths. Its re-review can still find its own prior summary
  because `github-actions[bot]` is not excluded from the pre-fetched comment
  context. The follow-up bot (`claude-followup.yml`) keeps the App identity.
- **Upstream replies** are posted under a bot identity by
  `scripts/claude-triage/post-upstream-reply.sh`, never by Claude and never
  with a person's token as author. Two mechanisms, in order of preference:
  1. An optional org-owned **bot app** (`CLAUDE_BOT_APP_ID` variable,
     `CLAUDE_BOT_APP_PRIVATE_KEY` secret) installed on `apollo-ios` and
     `apollo-ios-dev` with Contents, Issues, and Pull requests read/write. When
     present it posts directly and also opens the dev-repo PRs. Creating it
     needs an org owner.
  2. The **relay**: the publish step sends a `post-triage-reply`
     `repository_dispatch` to `apollo-ios` (using `APOLLO_IOS_PAT` only to fire
     the event) and `apollo-ios/.github/workflows/triage-reply-relay.yml` posts
     the comment with that repo's own token, so the author is
     `github-actions[bot]`. The script waits up to three minutes for the
     comment to appear and returns its URL; if it never appears (for example
     before the relay workflow has reached apollo-ios's default branch via the
     subtree push), the draft is routed to the maintainer with a warning. No
     admin permissions are needed for this path.

  Without the bot app, dev-repo fix PRs are opened with
  `APOLLO_IOS_PAT` and therefore show the maintainer as author, the same as
  release PRs today. Using the workflow token instead would stop CI from running
  on Claude's fix PRs.

The triage job's tool deny list stops mistakes, not attacks. Issue text is
untrusted input to the model; the instructions in `.github/claude/` say so
explicitly and route anything that looks like an instruction to the maintainer.
Network-capable tools (`curl`, `npm`, `swift package`, `WebFetch`) are denied
in the triage and follow-up runs for that reason.

## Triage outcomes

Claude classifies each issue (`bug`, `question`, `feature`, `unclear`) and
rates its confidence in the proposed action. `high` requires locating the exact
code, needing no guesses about the reporter's setup, and, for a fix, a build and
targeted test run that pass. Features and unclear reports are never `high`.

Claude never auto-replies to possible security reports, spam, issues a
maintainer has already commented on, duplicates, non-English reports, or
reports without a stated version; those always come to you.

| Outcome | Result |
|---|---|
| `bug` + `high`, fix verified | Branch `claude/triage/apollo-ios-<N>` (the only accepted name) is pushed and a ready-for-review PR opens with you as reviewer. "Verified" means the new test was seen failing, the package built, and `xcodebuild test` passed afterwards; the publish step refuses a fix without a recorded test run. The PR review workflow reviews it like any other PR and labels it as self-authored. |
| `high` with a drafted reply | Reply is posted on the upstream issue under a bot identity (bot app or relay), with a footer saying it was generated by an automated assistant and not yet reviewed by a maintainer, and inviting the reporter to reply. Reporter replies re-trigger triage. Disable with `CLAUDE_TRIAGE_AUTO_COMMENT` set to `false`. A Slack message reports what was posted. |
| Anything else | A Slack message to `#alerts-client-ios` with the summary, the questions whose answers would change the next step, and the full draft reply so you can paste it if you agree. **No PR, no issue, nothing in git.** If Slack rejects the message the job fails, so a lost alert is never silent. |

Claude never auto-replies to possible security reports, spam, issues a
maintainer has already commented on, duplicates, non-English reports, or
reports without a stated version; those always come to you.

| Outcome | Result |
|---|---|
| `bug` + `high`, fix verified | Branch `claude/triage/apollo-ios-<N>` (the only accepted name) is pushed and a ready-for-review PR opens with you as reviewer. "Verified" means the new test was seen failing, the package built, and `xcodebuild test` passed afterwards; the publish step refuses a fix without a recorded test run. The PR review workflow reviews it like any other PR and labels it as self-authored. |
| `high` with a drafted reply | Reply is posted on the upstream issue under a bot identity (bot app or relay), with a footer saying it was generated by an automated assistant and not yet reviewed by a maintainer, and inviting the reporter to reply. Reporter replies re-trigger triage. Disable with `CLAUDE_TRIAGE_AUTO_COMMENT` set to `false`. A Slack message reports what was posted. |
| Anything else | A Slack message to `#alerts-client-ios` with the summary, the questions whose answers would change the next step, and the full draft reply so you can paste it if you agree. **No PR, no issue, nothing in git.** If Slack rejects the message the job fails, so a lost alert is never silent. |

Every outcome sends a Slack message to `#alerts-client-ios` (the default;
override with `CLAUDE_TRIAGE_SLACK_CHANNEL_ID`, or set it to your member ID for
DMs). The Slack app behind `SLACK_BOT_TOKEN` (Clients/EDU Bot) must be a member
of the channel; `not_in_channel` is the error when it is not.

Claude never auto-replies to possible security reports, spam, issues a
maintainer has already commented on, duplicates, non-English reports, or
reports without a stated version; those always come to you.

**Dedup and follow-ups.** The record of what has been triaged is `triaged.json`
on the orphan branch `claude-triage-state`: issue number to last-triaged time,
read and written through the GitHub contents API by
`scripts/claude-triage/triage-state.sh`. It holds no drafts. An issue is skipped
while it has an entry; when the issue's author (only the author; bots and other
commenters are ignored) comments after that time, the issue is re-triaged with
the new comments in view. A follow-up that changes nothing just re-stamps the
entry and alerts no one. `@mentions` in anything written to dev-repo PRs are
defused so reporters are never pinged from here. Uncommitted work Claude leaves
behind is saved to the run artifact. Any publish failure sends a Slack alert.

**Acting on an alert.** Post the draft yourself if you agree with it, or reply
on the issue with what you know. Your own comment does not re-trigger triage
(only the reporter's does); to have Claude take another look after you act:

```bash
gh workflow run claude-issue-triage.yml -f issue_number=<N> -f force=true
```

## Slack alerts

Everything the bot does in public, and every triage result that needs you, is
announced in `#alerts-client-ios` (the default; override with
`CLAUDE_TRIAGE_SLACK_CHANNEL_ID`, or set it to your member ID for DMs). The
Slack app behind `SLACK_BOT_TOKEN` (Clients/EDU Bot) must be a member of the
channel; `not_in_channel` is the error when it is not.
`scripts/claude-notify/slack-notify.sh` is the only place anything posts to
Slack. Triage posts in strict mode: because the message is the only record of
a needs-input result, an unconfigured or rejected post fails the job so the
loss is visible. Follow-up notices are best effort and never fail a run.

| Event | Message |
|---|---|
| Triage opens a fix PR | The PR, the issue summary, and whether a reply went out |
| Triage replies to a reporter | The upstream comment and the issue summary |
| Triage needs your input | Full summary, the open questions, and the draft reply to paste if you agree |
| Triage publish fails | The issue and the run log |
| Claude answers an `@claude` comment | What you asked, Claude's reply, and any PR the run opened or marked ready for review, plus any reply it posted upstream |
| A follow-up run fails | The same, flagged with the step that failed — Claude's or the upstream post — plus a warning when a queued reply never made it upstream |

The follow-up notice attributes by author: a PR opened during the run is
reported only when a bot opened it, and "marked ready for review" is read from
the timeline event's actor, so work you do on the PR while it runs is never
reported as Claude's.
Automated PR reviews are deliberately not announced: they land on every PR and
GitHub already notifies the author.

## Setup

Secrets:

| Secret | Purpose |
|---|---|
| `CLAUDE_API_KEY` | Org secret (Anthropic Console key); IT must grant this repo access. Preferred. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Org secret (Claude Code OAuth token); alternative if granted instead. |
| `ANTHROPIC_API_KEY` | Repo-level fallback for a self-provisioned Console key. Set only one credential. |
| `SLACK_BOT_TOKEN` | Existing. Needs `chat:write` (and `im:write` for DMs). |
| `CLAUDE_BOT_APP_PRIVATE_KEY` | Optional bot app private key; enables direct posting and bot-authored PRs. |
| `APOLLO_IOS_PAT` | Existing. Opens dev-repo PRs when no bot app is configured and fires the upstream relay. Never authors an upstream comment. |

Variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_MODEL` | `claude-opus-5` | Model for all workflows. |
| `CLAUDE_TRIAGE_ASSIGNEE` | `AnthonyMDev` | Requested as reviewer on fix PRs. |
| `CLAUDE_TRIAGE_AUTO_COMMENT` | `true` | Post high-confidence replies upstream (bot identity only). |
| `CLAUDE_TRIAGE_SLACK_CHANNEL_ID` | `C06VAE92F7A` (#alerts-client-ios) | Slack channel ID or member ID for every alert, triage and follow-up alike. |
| `CLAUDE_TRIAGE_LOOKBACK_DAYS` | `3` | Only issues created or updated within this window are examined by the poll. |
| `CLAUDE_TRIAGE_MAX_PER_RUN` | `3` | Cap on issues triaged per poll. |
| `CLAUDE_BOT_APP_ID` | unset | Optional bot app ID; see Identity and authentication. |
| `FORK_REVIEW_SLACK_CHANNEL_ID` | falls back to `CLAUDE_TRIAGE_SLACK_CHANNEL_ID`, then #alerts-client-ios | Channel the fork-review heads-up is posted to. A private maintainer channel is recommended. |

## Fork PR review approval queue

`claude-fork-pr-review.yml` will not touch a fork PR until it carries the
`safe to review` label, because a `pull_request_target` job holds the base
repo's secrets and a write token. Applying that label is the approval, and it is
made in GitHub's own UI — which is already the right security boundary.

The flow, when a fork PR opens:

1. `fork-review-queue.yml` posts a Slack heads-up to the maintainer channel
   (`FORK_REVIEW_SLACK_CHANNEL_ID`) with a link to the PR. It applies no label,
   holds no write token, and runs no fork code.
2. A maintainer opens the PR and adds the **`safe to review`** label (or
   **`fork-review-declined`**). GitHub only lets a user with Triage/Write access
   apply a label, and a fork author cannot — so the label click *is* the
   authenticated approval; there is no separate allow-list to maintain.
3. The label — added by a human, not the default `GITHUB_TOKEN` — fires
   `claude-fork-pr-review.yml`.

Why not one-click from Slack: a plain link cannot apply a label (GitHub has no
"add this label" URL), and a single Slack button that approves would need a
hosted endpoint doing GitHub OAuth. The native-label step keeps the whole thing
to a Slack bot token and GitHub's own permissions — no Workflow Builder, no
connector, no PAT, no webhook, nothing stored in Slack.

The bot needs only `chat:write` on `SLACK_BOT_TOKEN` and to be a member of the
channel. Both labels must exist; create them once (declining is impossible
without `fork-review-declined`, and the queue would re-notify on every reopen):

```bash
gh label create "safe to review" --repo apollographql/apollo-ios-dev --color 0e8a16 --description "Run the automated Claude review on this fork PR"
gh label create "fork-review-declined" --repo apollographql/apollo-ios-dev --color b60205 --description "Fork PR declined for automated review"
```

To notify for PRs opened before this was set up, run the workflow manually
(Actions → Fork Review Approval Queue → Run workflow), which posts for every
currently pending fork PR.

## Running triage by hand

Actions → Claude Issue Triage → Run workflow. Leave `issue_number` blank to
poll, or set it to triage one issue. Set `force` to re-triage an issue that
was already triaged. From the CLI:

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
