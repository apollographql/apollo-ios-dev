# Claude Automation

Three workflows use [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)
to review pull requests and triage upstream issues. Claude's standing
instructions live in `.github/claude/` so they can be tuned without touching
workflow YAML.

| Workflow | Trigger | What it does |
|---|---|---|
| `claude-pr-review.yml` | Called from `ci-tests.yml` as a job that `needs` every CI job | Runs on the same `pull_request` event as CI, so the action has full PR context, but only after every CI job has finished. Skipped CI jobs count as passing; a failed or cancelled job posts one editable status note instead of a review, so a stale verdict never stands. A newer push cancels a review in flight, so only the latest commit is reviewed. Review instructions are read from `main`, not from the PR. Findings are tiered: blocking and important ones (each with a concrete failure scenario) get inline comments; minors are listed, collapsed, in the summary only. A re-review verifies prior findings and reviews only the new commits, and never raises minors on already-reviewed code, so nits do not cause round after round. Posts a tracking-comment summary. Skips drafts, forks, and CI bots. PRs that touch only `.github/claude/**` do not trigger CI and therefore get no review. |
| `claude-issue-triage.yml` | Every 30 minutes, manual, or `repository_dispatch` | Finds new `apollographql/apollo-ios` issues, and previously triaged issues where the reporter has commented since the last triage, then triages each one and publishes a result (below). |
| `claude-followup.yml` | `@claude` in a PR comment by an owner, member, or collaborator | Continues a triage from your answers, or does whatever you ask on a PR. Only the triggering comment's own text counts as instructions. Posts a Slack notice of what it replied and of anything it opened, marked ready, or sent upstream. |

## Identity and authentication

Three credentials are involved, and it matters which does what.

- **Model credential.** One of the org secrets `CLAUDE_API_KEY` (Anthropic
  Console key, preferred) or `CLAUDE_CODE_OAUTH_TOKEN`; a repo-level
  `ANTHROPIC_API_KEY` is accepted as a fallback. IT grants org secrets to this
  repository on request. Set only one.
- **Claude GitHub App.** With no `github_token` input, the action authenticates
  as the Claude App installed on the org, so review comments and the follow-up
  bot's PR comments show as `claude[bot]`. Two hard limits, both confirmed in
  the action's source and docs: the token is scoped to this repository only,
  and the action revokes it at the end of its own step. It therefore cannot be
  used to post on `apollo-ios` or by any later workflow step.
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

  Without the bot app, dev-repo fix and tracking PRs are opened with
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
| `high` with a drafted reply | Reply is posted on the upstream issue under a bot identity (bot app or relay), with a footer saying it was generated by an automated assistant and not yet reviewed by a maintainer, and inviting the reporter to reply. Reporter replies re-trigger triage. Disable with `CLAUDE_TRIAGE_AUTO_COMMENT` set to `false`. |
| Anything else | A draft tracking PR `[triage] apollo-ios#<N>: ...` opens on an **empty commit** (no files are committed), assigned to you and labeled `needs-input`. Its description holds the summary, the questions whose answers would change the next step, and any draft reply. |

Nothing from triage is written into the repository tree. Draft replies exist
only in the PR description, the Slack alert, and the run artifact. `@mentions`
in anything written to dev-repo PRs are defused so reporters are never pinged
from here. Uncommitted work Claude leaves behind is saved to the run artifact.
Branches that already exist on the remote are never rewritten; if you or the
follow-up bot pushed to a tracking branch, a re-triage only updates the PR
description. Any publish failure sends a Slack alert.

Every outcome sends a Slack message (see Slack alerts below). The needs-input
message carries the full summary, questions, and draft reply so you can act
from Slack. GitHub also emails you on assignment.

The tracking PR is the dedup record: an issue is skipped while a PR labeled
`claude-triage` with `apollo-ios#<N>` in its title exists (open or closed).
Every tracking and fix PR body carries a hidden `triaged-at` stamp. When the
issue's author (only the author; bots and other commenters are ignored) posts
a comment newer than that stamp, the issue is re-triaged with the new comments
in view: an open tracking PR is updated in place, a closed one is superseded
by a new record, and a follow-up that changes nothing just re-stamps the
record with a short comment and alerts no one.
Empty-commit PRs change no files, so `ci-tests.yml` (which has a `paths-ignore`
filter) does not run for them. `main` has no required status checks today; if
that changes, move the filter to per-job `paths-filter` gating so PRs that touch
only `.github/claude/**` still get a check run and remain mergeable.

Answer a tracking PR by commenting with `@claude` and your decision. Claude
re-reads the upstream issue, implements the fix on that branch and marks the PR
ready, posts the approved reply upstream, or closes the PR, per your comment.

## Slack alerts

Everything the bot does in public is announced in `#alerts-client-ios` (the
default; override with `CLAUDE_TRIAGE_SLACK_CHANNEL_ID`, or set it to your
member ID for DMs). The Slack app behind `SLACK_BOT_TOKEN` must be a member of
the channel. `scripts/claude-notify/slack-notify.sh` is the only place anything
posts to Slack; with either the token or the channel unset every alert is a
no-op and the rest of the automation still runs.

| Event | Message |
|---|---|
| Triage opens a fix PR | The PR, the issue summary, and whether a reply went out |
| Triage replies to a reporter | The upstream comment and the tracking record |
| Triage needs your input | Full summary, the open questions, and any draft reply |
| Triage publish fails | The issue and the run log |
| Claude answers an `@claude` comment | What you asked, Claude's reply, and any PR the run opened or marked ready for review, plus any reply it posted upstream |
| A follow-up run fails | The same, flagged, with the run log |

The follow-up notice reports pull requests opened during the run only when the
author is a bot, so a PR you open while it works is never reported as Claude's.
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
| `CLAUDE_TRIAGE_ASSIGNEE` | `AnthonyMDev` | Assigned to tracking PRs, requested as reviewer on fix PRs. |
| `CLAUDE_TRIAGE_AUTO_COMMENT` | `true` | Post high-confidence replies upstream (bot identity only). |
| `CLAUDE_TRIAGE_SLACK_CHANNEL_ID` | `C06VAE92F7A` (#alerts-client-ios) | Slack channel ID or member ID for every alert, triage and follow-up alike. |
| `CLAUDE_TRIAGE_LOOKBACK_DAYS` | `3` | Only issues created or updated within this window are examined by the poll. |
| `CLAUDE_TRIAGE_MAX_PER_RUN` | `3` | Cap on issues triaged per poll. |
| `CLAUDE_BOT_APP_ID` | unset | Optional bot app ID; see Identity and authentication. |

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
