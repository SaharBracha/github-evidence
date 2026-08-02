# JFrog Traceability

A single GitHub Action that collects **Git data** from your repository and
records it as **signed JFrog evidence** on the merge commit entity. It runs when
a pull request is **merged into your main branch**, giving you a tamper-evident,
cryptographically signed record of how each change was reviewed and how your
repository was governed at that moment.

The action installs and configures the JFrog CLI for you — you only supply your
JFrog OIDC provider and signing key.

## Why JFrog Traceability

Teams enforce strong controls in GitHub — required pull-request reviews, branch
protection, CODEOWNERS, signed commits — but that governance context stays in
GitHub. By the time a build is promoted and released, there is no tamper-evident
proof that a given change was actually reviewed, or that the repository was
properly governed when the change merged. That **approval gap** is where
unreviewed or unauthorized changes can slip into a release.

JFrog Traceability closes the gap. It captures the Git governance behind each
merge as **signed JFrog evidence** attached to your artifact in Artifactory, so
the proof travels with the software. On promotion, **JFrog AppTrust** can
automatically use this evidence and gate releases on it — turning
review-and-merge controls into enforceable, auditable release policy.

## What you get

For every merged pull request, the action produces **one** signed evidence named
`github-pull-request` attached to a `githubPullRequest` entity whose id is the
`{owner}-{repo}-{prID}` identity. The single predicate
carries two sections under separate root keys — `branch_protection` and
`pull_request_merge` — so all the governance context for a merge travels as one
attachment. It includes a **signed JSON predicate** (machine-readable, conforming
to the published [`github-pull-request.json`](predicates/github-pull-request.json) schema) and a
**human-readable report** you can open directly in the JFrog evidence **Content**
tab.

Everything is **read-only** against GitHub, and secret *values* are never fetched.

### Branch protection (`branch_protection` key)

A normalized snapshot of the repository's protected branches, rulesets, and
CODEOWNERS enforcement at merge time — proof of how the repo was governed when
the change landed. Lives under the predicate's `branch_protection` key (see the
[`github-pull-request.json`](predicates/github-pull-request.json) schema).

Example `branch_protection` section (abbreviated):

```json
{
  "repository": {
    "owner": "acme",
    "name": "widget",
    "full_name": "acme/widget",
    "url": "https://github.com/acme/widget"
  },
  "summary": {
    "protected_branch_count": 2,
    "ruleset_count": 1,
    "has_codeowners_file": true,
    "codeowners_rule_count": 2,
    "codeowners_validation_errors_present": false
  },
  "branches": [
    {
      "name": "main",
      "protection_source": ["branch_protection", "ruleset"],
      "required_pull_request_reviews": {
        "required": true,
        "required_approving_review_count": 2,
        "require_code_owner_reviews": true,
        "dismiss_stale_reviews": true,
        "require_last_push_approval": false
      },
      "required_status_checks": { "strict": true, "checks": ["ci/build"] },
      "enforce_admins": true,
      "required_signatures": false,
      "code_owner_review_required": { "via_branch_protection": true, "via_ruleset": true }
    }
  ]
}
```

The full section also carries `rulesets`, a `collection` block, and the complete
collector snapshot embedded verbatim as `raw_snapshot` (see the schema).

**Using this in policies.** A JFrog AppTrust policy can evaluate fields such as
`branch_protection.summary.protected_branch_count`,
`branch_protection.branches[].required_pull_request_reviews.required_approving_review_count`,
`branch_protection.branches[].required_pull_request_reviews.require_code_owner_reviews`,
`branch_protection.branches[].required_signatures`, and
`branch_protection.branches[].enforce_admins` — for example,
to require that `main` enforced at least two approvals plus code-owner review at
merge time. See [AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

### Merged pull request (`pull_request_merge` key)

Who approved the PR, what commits it put on the target branch, who authored them,
and each commit's cryptographic-signature verification status (`commit_signatures`
plus an `all_commits_verified` summary). Lives under the predicate's
`pull_request_merge` key (see the
[`github-pull-request.json`](predicates/github-pull-request.json) schema).

Identity fields come straight from what GitHub attests, so each side is partial:
a commit carries the author's email but resolves a `login` only when that email
is verified on a GitHub account, while a review carries the approver's `login`
but no email. The action fills these gaps on a best-effort basis (see
[Identity enrichment](#identity-enrichment)); when nothing authoritative is
available the field is left `null` rather than guessed, because the evidence is
signed.

Example `pull_request_merge` section:

```json
{
  "merge": {
    "merge_commit_sha": "9f3c1a2",
    "merged_at": "2026-07-20T10:00:00Z",
    "merged_by": "merger",
    "target_branch": "main",
    "target_base_sha": "1b7e0d4"
  },
  "approvers": [
    { "review_id": 100, "login": "alice", "email": "alice@example.com", "body": "lgtm", "submitted_at": "2026-07-19T09:00:00Z", "approved_sha": "7c2e9a1", "is_pr_head_approval": true },
    { "review_id": 101, "login": "bob", "email": null, "body": "", "submitted_at": "2026-07-18T09:00:00Z", "approved_sha": "3d5f8b0", "is_pr_head_approval": false }
  ],
  "commits_on_target_branch": ["c1a2b3c", "d4e5f6a"],
  "code_committers": [
    { "login": "alice", "email": "alice@example.com" },
    { "login": "bob", "email": "bob@example.com" }
  ],
  "commit_signatures": [
    { "sha": "c1a2b3c", "verified": true, "reason": "valid", "signer_login": "alice" },
    { "sha": "d4e5f6a", "verified": false, "reason": "unsigned", "signer_login": "bob" }
  ],
  "all_commits_verified": false,
  "collection": {
    "collected_at": "2026-07-20T10:00:01.000Z",
    "workflow_run_url": "https://github.com/acme/widget/actions/runs/123"
  }
}
```

**Using this in policies.** A JFrog AppTrust policy can evaluate
`pull_request_merge.all_commits_verified`, the number and identity of
`pull_request_merge.approvers`, `pull_request_merge.commit_signatures[].verified`,
and `pull_request_merge.code_committers` — for example, to require that every
commit is signature-verified and that the merge carried at least one approval. See [AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

## On the JFrog platform

Once the action runs, the signed evidence lives in Artifactory — you do
**not** need JFrog AppTrust to produce or store it.

**Where it lives.** Each run attaches signed evidence to a non-artifact
**entity** whose type is `githubPullRequest` and whose id is the
`{owner}-{repo}-{prID}` identity.
With project scope, Evidence stores it under the conventional repository
`{jf_project}-githubPullRequest-entity` (path under `.entities/githubPullRequest/...`).

**How to retrieve and verify.** List evidence with the Evidence REST API
(`GET /evidence/api/v1/entity/githubPullRequest/{owner}-{repo}-{prID}?project-key=...`)
or GraphQL `hasEntityWith`, and open the human-readable **Content** report in the
JFrog UI. You can also cryptographically verify evidence with the JFrog CLI
(`jf evidence verify`).

**How it's used.** This evidence is a signed, auditable record that stands on its
own — no AppTrust required. When the resulting artifact is later **promoted**,
JFrog AppTrust automatically consumes this Git evidence to generate new AppTrust
evidence, and AppTrust lifecycle policies can gate the promotion on it. See
[AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

## Prerequisites

You do **not** need to add `jfrog/setup-jfrog-cli` to your workflow — this action
installs and configures the JFrog CLI for you (URL normalization, OIDC token
exchange, and project selection) in its own step. The prerequisites are the
platform-side setup:

- A **JFrog project** (you'll reference its project key).
- An **entity repository** named `{jf_project}-githubPullRequest-entity` in Artifactory
  (Evidence does not create it automatically). The OIDC identity must be able to
  annotate that repository.
- A platform Evidence service that includes **non-artifact entity APIs**
  (RTDEV-92120 / Evidence on Non-Artifacts). Older Evidence builds that only
  support artifact subjects are not compatible.
- An **OIDC integration** under **Administration → OIDC**, with an identity
  mapping for this repository. Authentication uses OIDC, so no long-lived JFrog
  access token is stored — the runner exchanges its GitHub OIDC token for JFrog
  access at run time.
- An **evidence signing key** (private PEM) and its **alias** registered in the
  platform. The signing key is the only secret you store in GitHub.

See [Required secrets and variables](#required-secrets-and-variables) for how to
wire these into your repository.

## Quick start

Drop this one workflow into `.github/workflows/`:

```yaml
name: JFrog Traceability
on:
  pull_request:
    types: [closed]
    branches: [main]
permissions:
  contents: read
  pull-requests: read
  id-token: write
jobs:
  git-evidence:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jfrog/git-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
          evidence_key_alias: ${{ vars.EVIDENCE_KEY_ALIAS }}
```

The `branches: [main]` filter scopes the workflow to pull requests targeting
`main`, and the `closed` trigger plus the `if: ...merged == true` guard limits the
job to merges — so closed-unmerged PRs produce nothing. Each merge into `main`
then produces one combined `github-pull-request` evidence covering both the branch
protection and the merge. Add more branches to the list to cover additional
release branches. A runnable copy lives in
[`examples/git-evidence.yml`](examples/git-evidence.yml).

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL; normalized to `https://&lt;host&gt;/`). |
| `oidc_provider_name` | yes | — | Name of the OIDC integration in the JFrog platform; the runner exchanges its GitHub OIDC token for JFrog access (no stored token). |
| `evidence_signing_key` | yes | — | Private key (raw PEM contents) used to sign the evidence. |
| `evidence_key_alias` | yes | — | Signing key alias registered in the JFrog platform. |

GitHub data is read from `api.github.com` with the workflow's built-in
`GITHUB_TOKEN` (grant it `contents: read` and `pull-requests: read`).
Branch-protection fields the token isn't allowed to read are recorded as
`unavailable` rather than failing the run.

### Identity enrichment

Merged-PR evidence records approver and committer identities. GitHub only
attests part of each: a review has a `login` but no email, and a commit has an
email but a `login` only when that email is verified on a GitHub account. The
action fills these gaps best-effort using only the built-in `GITHUB_TOKEN` — no
extra inputs, tokens, or scopes — and never guesses:

- **Approver email** — the user's public GitHub profile email, when they have
  published one; otherwise `null`.
- **Committer login** — recovered from a `…@users.noreply.github.com` commit
  email, which encodes the login; otherwise `null`.

Anything unresolved is left `null` rather than guessed, because the evidence is
signed. A committer `login` also resolves on its own — with no reliance on the
no-reply heuristic — once a contributor **verifies their commit email on their
GitHub account** (Settings → Emails), which is what makes GitHub attest the
`login` directly.

The merged-PR number is read automatically from the triggering `pull_request`
event — there is no `pr_number` input.

## Required secrets and variables

| Name | Kind | Description |
|---|---|---|
| `EVIDENCE_KEY` | secret | Private signing key (PEM). |
| `JF_URL` | variable | JFrog platform host. |
| `JF_OIDC_PROVIDER` | variable | Name of the OIDC integration configured in the JFrog platform. |
| `EVIDENCE_KEY_ALIAS` | variable | Signing key alias. |

Authentication uses OIDC, so there is no stored JFrog access token — the only
secret is the signing key. Configure a matching OIDC integration in the JFrog
platform under **Administration → OIDC**, with an identity mapping for this
repository, and use its provider name as `JF_OIDC_PROVIDER`.

## Versioning

Pin the moving major tag `@v1` for automatic minor/patch updates, or a full
`@vX.Y.Z` for an immutable pin.
