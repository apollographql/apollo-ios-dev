---
name: apollo-ios-feature-analysis
description: >
  Run an Apollo iOS feature request analysis for roadmap planning, or add a single new feature
  request to the existing analysis. Use this skill whenever someone asks to: analyze Apollo iOS
  feature requests, build a roadmap for Apollo iOS, research what customers are asking for in
  Apollo iOS, prioritize Apollo iOS work, create a stakeholder document about Apollo iOS
  priorities, add a new feature request to the roadmap analysis, score a specific Apollo iOS
  issue, or run the feature request workflow. Trigger on any mention of "Apollo iOS roadmap",
  "feature requests", "roadmap document", "stakeholder analysis", "what should we build next in
  Apollo iOS", or "add [issue #N] to the feature analysis".
---

# Apollo iOS Feature Request Analysis

This skill automates the workflow for gathering, scoring, and ranking Apollo iOS feature
requests. It has two modes:

- **Full analysis** (Steps 1–5 below) — periodic (quarterly / pre-planning cycle) sweep
  across all sources. Produces the complete roadmap document.
- **Single-feature update** (see "Single-Feature Update Mode" at the end) — add one new
  feature request to the existing analysis. Scoped research, interactive scoring, and
  surgical insertion into the existing Confluence page without re-running the full sweep.

When the user names a specific issue number or says "add this to the analysis", use
single-feature mode. Otherwise, run the full analysis.

---

## Step 1: Research — Gather Feature Requests

Search all sources in parallel. The goal is to build a candidate list of 15–25 items
before filtering. Cast a wide net; you'll narrow down later.

### 1a. Slack

Use `slack_search_public_and_private` (with user consent) to search broadly across all channels.
Focus on these channels for customer-facing feature requests related to Apollo iOS:

- **#inbox-client-mobile** — primary triage channel; external customers asking about mobile client features
- **#apollo-ios-dev** — internal team discussions; triage threads, contributor conversations
- **#ask-anything** — general channel where customers raise issues; catch enterprise-specific requests here
- **#ext-apollo-\*** — partner/customer channels (e.g., `#ext-apollo-indeed`, `#ext-apollo-wayfair-shared`); these often contain named-customer signals that won't appear on GitHub
- **#internal-\*** — internal customer account channels that may have iOS-specific discussions

Search terms to use: "feature request", "would love", "any plans to", "is there a way to", "missing feature", "support for", "Swift", "iOS", "Apollo iOS", "codegen", "SPM", "Swift Package Manager", "Xcode", "SwiftUI", and the names of candidate features from GitHub.

For each relevant thread, note:

- Channel and thread link
- Customer name (if any)
- What they're asking for
- Whether they described a workaround

### 1b. GitHub

GitHub's API may be blocked in some environments. If `api.github.com` returns an error, use WebSearch with queries like `site:github.com apollographql/apollo-ios "feature request" reactions` to find issue details.

Search these repos:

- **apollographql/apollo-feature-requests** — primary feature request tracker; filter for open non-bug issues related to iOS/mobile/Swift
- **apollographql/apollo-ios** — find open issues tagged as enhancements or feature requests (runtime SDK)
- **apollographql/apollo-ios-dev** — the development monorepo; issues filed here may cover SDK, codegen, or pagination
- **apollographql/apollo-ios-codegen** — code generation library feature requests
- **apollographql/apollo-ios-pagination** — pagination library feature requests

For each candidate, capture:

- Issue number and URL
- Title
- Date opened
- Approximate reaction count (👍 and equivalents)
- Notable comments that signal demand or workarounds

**Exclude:** bug reports, issues labeled "question", and anything explicitly marked as shipped in recent release notes (check the Apollo iOS changelog at `apollo-ios/CHANGELOG.md` in the dev repo or GitHub releases page).

### 1c. ROADMAP.md

Read the Apollo iOS roadmap at `apollo-ios/ROADMAP.md` in the dev repo. For each item listed:

1. **If already shipped** — exclude it (cross-reference with the changelog)
2. **If already covered by a candidate from GitHub/Slack** — note the roadmap status on the existing candidate (e.g., "API design in progress", "Feature Design", "Not started")
3. **If not yet captured as a candidate** — add it as a new feature request entry. Use the roadmap status as context for the team priority and difficulty ratings.

Roadmap items often represent team-driven priorities that may not have strong community signal yet (e.g., spec alignment work like semantic nullability). Including them ensures the analysis covers both demand-driven and strategy-driven features.

### 1d. Community Forum

Search `community.apollographql.com` with iOS and mobile tags:

- URL pattern: `https://community.apollographql.com/tag/ios` or `https://community.apollographql.com/latest?tags=ios%2Cmobile`
- Use WebFetch or WebSearch to find posts. If direct fetching fails, search for `site:community.apollographql.com apollo ios feature`.

For each relevant post, capture:

- Title and URL
- Reply count and view count
- Whether the post asks for a new feature vs. reporting a bug

### 1e. GitHub User → Company Cross-referencing

For each GitHub issue in the candidate list, collect all commenters and reactors using the GitHub API:

```bash
gh api "repos/apollographql/apollo-ios/issues/{number}/comments" --jq '.[].user.login'
gh api "repos/apollographql/apollo-ios/issues/{number}/reactions" --jq '.[].user.login'
```

Then look up each user's company affiliation:

```bash
gh api "users/{username}" --jq '{login, name: .name, company: .company, bio: .bio, email: .email, blog: .blog}'
```

For users without a company in their GitHub profile, cross-reference using:

1. **Username patterns** — usernames like `sahilsharma-toast` (Toast), `nilkanthjp-doordash` (DoorDash), `jeroenvb-wbd` (Warner Bros Discovery) often encode their employer
2. **Email domains** — `@company.com` emails in profiles map directly to employers
3. **LinkedIn/web search** — search `site:linkedin.com "{name}" iOS developer {location}` to find current employers
4. **GitHub contributions** — check if they contribute to company-owned repos (e.g., a user contributing to `RevenueCat/purchases-ios` likely works at RevenueCat)

Maintain a persistent directory of GitHub users → companies on the **Apollo iOS GitHub User Company Directory** Confluence page in the Client Development space (space key `ClientDev`, page ID `2464579597`, cloud ID `b8116c26-1732-446c-9a3b-e138b1e55296`). Update it each time the analysis runs using the Atlassian `updateConfluencePage` tool — fetch the current page with `getConfluencePage`, merge new rows into the Full User Directory table and any new features into the Companies by Feature Request table, and submit the full updated body. If the page ID has changed, look it up via `getPagesInConfluenceSpace` filtered by title.

### 1f. Enterprise Customer Data (Optional)

If available, check these additional sources for customer signal:

- **Omni dashboard** — The enhanced client awareness dashboard at `https://apollographql.omniapp.co/dashboards/546702af` shows which customers use Apollo iOS (requires Omni MCP or manual access)
- **Confluence "Top 10 customer problems"** — Search Confluence for quarterly customer problem pages in the PDE space
- **Jira support tickets** — Search Jira for TSH tickets mentioning Apollo iOS feature requests

---

## Step 2: Candidate Curation

From your research, identify 10–20 distinct feature requests. Merge duplicates (same underlying ask
across repos or channels) into a single item. Assign provisional IDs: FR-01, FR-02, etc.

**Exclude anything that is:**

- A bug fix, not a feature
- Already shipped (check the Apollo iOS changelog — currently the latest releases are in `apollo-ios/CHANGELOG.md`)
- Too vague to scope ("improve performance" without specifics)
- An Apollo Studio/GraphOS feature, not a client-side feature
- A feature that only applies to the web client (React hooks, browser APIs, etc.)

Group items that have cross-system dependencies (e.g., requiring Apollo Router or Apollo Kotlin
changes that the iOS team cannot deliver independently) separately — They'll go into the
"Candidates with cross-system dependencies" section.

---

## Step 3: Score Each Feature Request

For each candidate, score across these four dimensions independently (before interactive scoring):

### Scoring Dimensions

| Dimension              | Max | How to Score |
| ---------------------- | --- | ------------ |
| **Community Interest** | 10  | Combined GitHub reactions + forum engagement. **GitHub** (primary): 100+ reactions = 9–10, 50–100 = 7–8, 20–50 = 5–6, 10–20 = 3–4, <10 = 1–2. Boost +1 if multiple issues across repos. Boost +1 if high comment quality/depth. **Forum** (secondary): Add +1 if 5+ replies on community.apollographql.com, +2 if 15+ replies. |
| **Customer Signals**   | 10  | Named companies requesting or affected by the feature. Sources: Slack channels, GitHub user→company mapping, Jira support tickets, Omni dashboard. **Scoring**: 5+ identified companies = 9–10, 3–4 companies = 6–8, 2 companies = 4–5, 1 company = 2–3. No named companies but strong general demand = 1. Boost +1 per enterprise/paying customer (vs. general community company). Boost +1 if customer has a workaround in production (signals real pain). |
| **Longevity**          | 5   | Age **combined with** interest level. The key insight: age alone is not a signal — a feature open for 5 years with 2 reactions is not actually in demand. Use this matrix: Old (4+ yrs) + High interest (7+ Community) = 5; Old + Medium interest = 3; Old + Low interest = 1; Recent (1–3 yrs) + High interest = 4; Recent + Medium = 2; Recent + Low = 1. |
| **Strategic Value**    | 5   | Competitive parity (Relay, Firebase, AWS Amplify, URLSession/SwiftUI native patterns), cross-product alignment (Apollo Client web, Apollo Kotlin, GraphOS), growing architectural patterns (Swift 6 concurrency, SwiftUI, structured concurrency, Swift Testing). |

### Interactive: iOS Team Priority

After completing the 4 research-based dimensions, ask about each feature's team priority using
the `AskUserQuestion` tool — one question per feature. Present the feature name and a brief
one-line description, then ask:

> "What is the Apollo iOS team's priority for [feature name]?"
> Options: High (5 pts), Medium (2 pts), Low (1 pt)

### Interactive: Difficulty

Then ask about difficulty for each feature:

> "How difficult is [feature name] to implement?"
> Options: Easy (4 pts), Medium (2 pts), Difficult (1 pt)

You can batch these into a single multi-choice question per feature to reduce back-and-forth:
ask priority and difficulty together for each item. If the list is long (10+ items), do this
in rounds of 3–5 at a time so it doesn't feel overwhelming.

**Maximum possible score: 39 points**
(10 + 10 + 5 + 5 + 5 + 4)

---

## Step 4: Rank and Finalize

After collecting all scores:

1. Compute composite scores for each item.
2. Sort by score descending. Break ties by: strategic value, then customer signals, then team priority.
3. Select the top 10 for the active roadmap. Items with cross-system dependencies
   go into the "Candidates with cross-system dependencies" section instead.
4. Re-read your reasoning and check: does the order make intuitive sense to someone who knows the
   product? If something feels off, document why in the rationale section.

---

## Step 5: Write the Document

Publish the output as an update to the **Apollo iOS Feature Request Analysis** Confluence page in the Client Development space (space key `ClientDev`, page ID `2463760410`, cloud ID `b8116c26-1732-446c-9a3b-e138b1e55296`).

Use the Atlassian `updateConfluencePage` tool with `contentFormat: "markdown"`. The update fully replaces the page body, so always send the complete document (not a diff). Before updating:

1. Call `getConfluencePage` to confirm the page still exists and capture the current version number.
2. Compose the full new document body per the structure below.
3. Include a `versionMessage` identifying the run (e.g., `"Quarterly refresh 2026-Q3"` or `"Ad-hoc update: added Generate All Schema Types (#3635)"`).

If the page ID has changed, look it up via `getPagesInConfluenceSpace` filtered by title `"Apollo iOS Feature Request Analysis"`. If the page is missing entirely, fall back to `createConfluencePage` in the `ClientDev` space and save the new page ID in memory.

Also save a local markdown copy to `apollo-ios-feature-request-analysis-YYYY-MM-DD.md` for the git history only when the user explicitly asks for a file artifact — the Confluence page is the canonical location.

### Document Structure

```
# Apollo iOS Feature Request Analysis

**Prepared for:** [name]
**Date:** [date]
**Sources:** Slack (internal + external channels), GitHub (apollo-ios + apollo-ios-dev + apollo-ios-codegen + apollo-ios-pagination + apollo-feature-requests), GitHub user→company mapping, Apollo Community Forum

---

## Scoring Methodology

[Table with all 6 dimensions, max points, and description]

**Maximum possible score: 39**

---

## Section 1: Raw Feature Request List

> Listed in discovery order with no implied priority. Sources linked for each.

[One subsection per feature: FR-01 through FR-N]
[Each subsection: description, sources with links, companies identified, score table]

---

## Section 2: Suggested Roadmap Order

[Priority 1 through Priority 10, each with: score badge, GitHub links, "Why N:" rationale paragraph]

---

## Summary Scorecard

[Table: # | Feature | Score | Team Priority | Difficulty | Key Signal | Companies]

---

## Candidates with cross-system dependencies — Not Currently Roadmapped

[Features with cross-system dependencies; one subsection each]

---

_Note: [list any features explicitly excluded and why, e.g., shipped features]_
```

### Feature Entry Format (Section 1)

Each feature in Section 1 should follow this structure:

```markdown
### FR-NN — [Feature Name]

**Description:** [2–4 sentences. What problem does this solve? What is the current workaround?
What would the ideal solution look like?]

**Sources:**

- GitHub (repo): [Issue #NNN – Title](URL) _(opened YYYY, N reactions)_
- Slack (#channel, Month YYYY) — [Customer name]: brief description → [Thread](URL)
- Community Forum: [Post title](URL) _(N replies, N views)_

**Companies identified:** [List companies whose employees commented/reacted on this issue]

**Score: N/39**

| Dimension            | Score | Rationale                       |
| -------------------- | ----- | ------------------------------- |
| Community Interest   | N     | ...                             |
| Customer Signals     | N     | ...                             |
| Longevity            | N     | ...                             |
| Strategic Value      | N     | ...                             |
| iOS Team Priority    | N     | **High/Medium/Low** — ...       |
| Difficulty           | N     | **Easy/Medium/Difficult** — ... |
```

### Priority Entry Format (Section 2)

```markdown
### 🥇 Priority N — [Feature Name]

**Score: N/39** | GitHub: [#NNN](URL)

**Why N:** [2–4 sentence rationale explaining why this ranks here. Reference the key signals.
Mention what would move it up or down the list. Be honest about tradeoffs.]
```

Use medal emojis (🥇🥈🥉) for top 3; plain "Priority N —" for 4–10.

---

## Quality Notes

**Be specific about sources.** Every feature entry should have at least one linked source. Slack
links should use the permalink format (`https://apollograph.slack.com/archives/CHANNEL/pTIMESTAMP`).
GitHub links should go to the specific issue, not a search. Forum links to the specific thread.

**Write real rationale in Section 2.** The "Why N:" paragraph is the most useful part of this
document for stakeholders. Don't just restate the score — explain the story: what's driving the
demand, who's asking, what the team would need to commit to, and what might change the ranking.

**Flag cross-system dependencies.** Items that require Apollo Router, Apollo Kotlin, or other teams
to deliver changes the iOS team cannot ship independently should be called out explicitly in both
their Section 1 entry and in the "Candidates with cross-system dependencies" section.
Don't let these inflate the active roadmap.

**Periodically check for shipped features.** Before including any item, confirm it hasn't
shipped recently. Check the Apollo iOS changelog (`apollo-ios/CHANGELOG.md` in the dev repo)
and the latest major/minor release notes.

**Update the GitHub user directory.** After each analysis run, update the **Apollo iOS GitHub User Company Directory** Confluence page (space `ClientDev`, page ID `2464579597`) with any new users and companies discovered. Read the page first to preserve existing rows, then send a merged body via `updateConfluencePage`.

**The Summary Scorecard uses emoji indicators:**

- Team Priority: 🔴 High, 🟡 Medium, ⚪ Low
- Difficulty: 🔴 Difficult, 🟡 Medium, 🟢 Easy

---

## Reference: First Analysis (April 2026)

The inaugural analysis produced these results for context and comparison in future runs:

| #   | Feature                               | Score |
| --- | ------------------------------------- | ----- |
| 1   | Cache Eviction / TTL / Expiration     | 30    |
| 2   | Error Policies                        | 25    |
| 3   | Mutable Response Models (codegen)     | 22    |
| 4   | Caching Rewrite (RFC)                 | 17    |
| 5   | Union Types as Enums                  | 16    |
| 6   | Local-only Fields                     | 15    |
| 7   | Dynamic Codegen Config Values         | 14    |
| 8   | Watch Fragments API                   | 14    |
| 9   | Query Batching                        | 12    |
| 10  | Generate All Schema Types             | 12    |
| 11  | Operations Without Response Models    | 11    |
| 12  | NumberOfFiles Output                  | 10    |
| 13  | Semantic Nullability                  | 10    |

Not roadmapped: SPM Build Plugin (score 9), Linux/Android Support (score 8), @stream (score 7).

Use this as a baseline when running future analyses. Features that appeared in the original list
and are still open represent sustained demand. New entries show emerging needs.

---

## Single-Feature Update Mode

Use this mode when the user asks to add **one specific feature** (usually by issue number)
to the existing analysis rather than re-running the full sweep. This is the common
operating mode between quarterly refreshes.

**Triggers:** "Add issue #N to the feature analysis", "Score issue #N and add it",
"Run an analysis for #N and add it to the doc", any single-issue reference in context
of the roadmap document.

### When NOT to use single-feature mode

- User asks to "refresh" or "rerun" the analysis → full analysis mode
- User lists multiple issues at once → full analysis mode (or prompt them to pick one)
- Current analysis is older than ~6 months → suggest a full refresh first, since
  existing scores may be stale

### Workflow

**Step A: Scoped research for the single issue.** Do not re-scan Slack/forum/other issues.
Gather only:

1. The issue body, reaction count, reactors, commenters. Use:
   ```
   gh issue view <N> --repo apollographql/apollo-ios --json reactionGroups,comments,createdAt,author,state
   gh api "repos/apollographql/apollo-ios/issues/<N>/reactions" --jq '.[] | {user: .user.login, content}'
   gh api "repos/apollographql/apollo-ios/issues/<N>/comments" --jq '.[].user.login'
   ```
2. Company affiliations for each reactor/commenter — check the **Apollo iOS GitHub User
   Company Directory** Confluence page first (space `ClientDev`, page `2464579597`); for
   users not already in the directory, use `gh api users/<login>` and LinkedIn search.
   Mark new users for directory update.
3. Cross-platform parity check — does Apollo Kotlin or Apollo Client web have this feature?
   This informs Strategic Value.
4. Quick changelog check — confirm the issue isn't already resolved by a shipped release.

**Step B: Score the 4 research dimensions** per the standard scoring matrix. Present them
in a compact table to the user.

**Step C: Interactive scoring for the remaining 2 dimensions.** Ask the user for Team
Priority (High/Medium/Low) and Difficulty (Easy/Medium/Difficult). If the user has already
stated these in the conversation (e.g., during an issue response), propose them as defaults
and confirm rather than asking again.

**Step D: Determine sort position.** Compute the composite score, then find where this
feature slots into the current ranking using the standard tiebreaker (strategic value →
customer signals → team priority). Renumber any Priority entries that shift.

**Step E: Update the Confluence page.** Fetch the current page body with `getConfluencePage`,
then submit the full updated body via `updateConfluencePage`:

1. Append the new `FR-NN` entry to the end of Section 1 (Raw Feature Request List).
   Use the next available FR number — do not renumber existing FR entries, since
   Section 1 is discovery order, not priority order.
2. Insert a new Priority entry in Section 2 at the correct sorted position, and renumber
   any subsequent Priority headings.
3. Add a new row to the Summary Scorecard at the correct sorted position and update the
   `#` column for any rows that shifted down.
4. Append a bullet to the **Changelog** section at the end of the page (add the Changelog
   section if it doesn't exist) describing the update. Format: `- **YYYY-MM-DD** — Added
   FR-NN <Name> (issue #N). Score X/39 places it at Priority P.`
5. Update the `Last updated:` date in the header.

Use `versionMessage` that identifies the addition, e.g., `"Add FR-16 Generate All Schema
Types (#3635); renumber Priorities 10–13"`.

**Step F: Update the companion user directory.** If new reactors/commenters were discovered
that aren't in the GitHub User Company Directory, update that Confluence page (page
`2464579597`) with the new rows and, if this feature introduces a new entry to the
"Companies by Feature Request" table, add that row too.

**Critical — do not send placeholder bodies.** When calling `updateConfluencePage`, the
`body` parameter always writes to the page. Never submit a placeholder value with the
intent to "fix it next call" — a broken intermediate version will be published. Compose
the complete final body before the first call.
