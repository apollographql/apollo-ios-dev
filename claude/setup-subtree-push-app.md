# Setup: Subtree Push GitHub App

This runbook covers the one-time setup required to migrate the `PR Subtree Push` workflow from SSH deploy keys to a GitHub App, and to enforce push restrictions on the three upstream subtree repos.

**Why:** The workflow's "dev is the only writer" invariant is currently a convention, not an enforced rule. Anyone with write access on `apollo-ios`, `apollo-ios-codegen`, or `apollo-ios-pagination` can push directly to `main` today. A GitHub App's identity is the only thing GitHub branch protection can `restrictions`-allow (deploy keys can't be put in that list), so the path to enforcement is: switch the workflow to use an app, then restrict pushes to that app.

## Overview

| Phase | Who | What |
|---|---|---|
| 1 | Org admin (you) | Create the GitHub App in the apollographql org |
| 2 | Org admin (you) | Install the app on the four repos |
| 3 | Org admin (you) | Add app ID + private key as repo secrets in `apollo-ios-dev` |
| 4 | (Workflow already updated in this PR) | Merge this PR — workflow uses app token |
| 5 | Org admin (you) | Verify a test PR's workflow run succeeds end-to-end |
| 6 | Org admin (you) | Add push restrictions to each upstream `main` |
| 7 | Org admin (you) | Clean up old deploy keys + secrets |

Phases 1–3 must happen **before** this PR merges, otherwise the workflow will fail on the next PR merge to `main` (missing secrets).

## Phase 1: Create the GitHub App

1. Go to <https://github.com/organizations/apollographql/settings/apps/new>.
2. Fill in:
   - **Name:** `Apollo iOS Subtree Push` (or any unique name; lowercase + hyphens get used in the bot's username automatically)
   - **Homepage URL:** `https://github.com/apollographql/apollo-ios-dev`
   - **Webhook:** Uncheck "Active" (we don't need webhooks)
   - **Repository permissions:**
     - `Contents` → **Read & write** (required for pushing)
     - `Metadata` → **Read-only** (required by default)
     - Everything else → **No access**
   - **Organization permissions:** none
   - **User permissions:** none
   - **Where can this GitHub App be installed?** Only on this account
3. Click **Create GitHub App**.
4. On the resulting page:
   - Note the **App ID** at the top — you'll need it for secrets.
   - Scroll to **Private keys**, click **Generate a private key**. A `.pem` file downloads. Keep this safe — it's effectively the app's password. **Do not commit it anywhere.**

## Phase 2: Install the app on the four repos

1. From the app's settings page, click **Install App** in the left sidebar.
2. Click **Install** next to `apollographql`.
3. Choose **Only select repositories** and select:
   - `apollo-ios`
   - `apollo-ios-codegen`
   - `apollo-ios-pagination`
   - `apollo-ios-dev` _(needed because the workflow runs from this repo and needs to mint a token)_
4. Click **Install**.

## Phase 3: Add secrets to `apollo-ios-dev`

1. Go to <https://github.com/apollographql/apollo-ios-dev/settings/secrets/actions>.
2. Click **New repository secret**, add:
   - **Name:** `APOLLO_IOS_SUBTREE_APP_ID`
   - **Value:** the App ID from Phase 1
3. Click **New repository secret** again, add:
   - **Name:** `APOLLO_IOS_SUBTREE_APP_PRIVATE_KEY`
   - **Value:** the full contents of the `.pem` file from Phase 1, including the `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` lines

After saving, you can delete the `.pem` file locally. The secret is the only place it needs to live.

## Phase 4: Merge this PR

With secrets in place, this PR can be merged. The workflow will use the app token on the next PR merge.

## Phase 5: Verify

1. Wait for the next PR to merge to `main` (or trigger a manual one — e.g. a tiny no-op PR touching only this file or a comment).
2. In the workflow run, confirm:
   - The **Generate GitHub App Token** step succeeds (no missing-secret errors).
   - The **Push Subtrees** step succeeds (HTTP 200 / 204 in the logs).
   - The three upstream `main` branches advance with the new split SHAs.
3. If anything fails, the deploy keys are **still in place as a fallback** — you can revert this PR's workflow changes without any data loss.

## Phase 6: Add branch protection restrictions

Once Phase 5 passes, lock down the three upstream `main` branches so only the app can push.

For each of `apollo-ios`, `apollo-ios-codegen`, `apollo-ios-pagination`:

1. Go to `https://github.com/apollographql/<repo>/settings/branches`.
2. Edit the protection rule for `main`.
3. Check **Restrict who can push to matching branches**.
4. In the **People, teams, or apps** picker, add the GitHub App you created in Phase 1.
5. Also worth tightening while you're there:
   - Check **Do not allow bypassing the above settings** (this is the `enforce_admins: true` setting — applies the rule to admins too).
   - On `apollo-ios-pagination` specifically, uncheck **Allow force pushes** (it's currently enabled, unlike the other two).
6. Save the rule.

CLI alternative (for each upstream repo):
```bash
gh api -X PUT "repos/apollographql/<repo>/branches/main/protection" --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["ci/circleci: gitleaks", "ci/circleci: semgrep"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": {
    "users": [],
    "teams": [],
    "apps": ["apollo-ios-subtree-push"]
  },
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

(Replace `apollo-ios-subtree-push` with the actual slug GitHub assigns to your app — visible in its settings URL.)

## Phase 7: Clean up

Once the workflow has run successfully a few times with the app:

1. **Remove deploy keys from the upstream repos:**
   - `https://github.com/apollographql/apollo-ios/settings/keys` — delete the "Subtree Push" key
   - Same for `apollo-ios-codegen` and `apollo-ios-pagination`
   - (Leave `apollo-ios-dev`'s deploy key for now — see note below)
2. **Remove unused secrets from apollo-ios-dev:**
   - `APOLLO_IOS_DEPLOY_KEY`
   - `APOLLO_IOS_CODEGEN_DEPLOY_KEY`
   - `APOLLO_IOS_PAGINATION_DEPLOY_KEY`
   - (Leave `APOLLO_IOS_DEV_DEPLOY_KEY` — see note below)

**Note on `APOLLO_IOS_DEV_DEPLOY_KEY`:** The "Push Updated History" step pushes back to `apollo-ios-dev/main` using the workflow's checkout credentials (`GITHUB_TOKEN`), not this deploy key. The key may be unused, but verify before removing — there could be other workflows that depend on it.

## Rollback

If anything goes wrong after Phase 6 (branch protection blocking pushes unexpectedly):

1. Edit each upstream's branch protection rule, **uncheck Restrict who can push** — pushes work normally again.
2. If the workflow itself is broken (e.g., app token minting fails), revert the workflow PR. The deploy keys are still there (until Phase 7) and the previous workflow works as-is.

## Why a GitHub App, not a PAT?

- **No human owner.** Apps aren't tied to a person who might leave the company. PATs (even on a bot user) are.
- **No seat cost.** Bot users count toward the org's paid-seat quota; apps don't.
- **Scoped permissions.** The app's permissions are declared once and visible in its config. A PAT's scopes are opaque to anyone but its owner.
- **Branch protection support.** Both apps and users can be in `restrictions`, but apps are the cleaner choice for automation identities.

## Related files

- `.github/workflows/pr-subtree-push.yml` — the workflow that uses the app token
- `.github/actions/subtree-split-push/action.yml` — the composite action that does the per-subtree split
- `claude/ci-subtree-troubleshooting.md` — troubleshooting playbook for when something goes wrong
