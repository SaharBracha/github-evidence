# JFrog Traceability

A single GitHub Action that collects **Git data** from your repository and
records it as **signed JFrog evidence** on a `gitCommit` entity (keyed by the
merge commit sha). It runs when a pull request is **merged into a configured
target branch** (for example `main`), giving you a tamper-evident,
cryptographically signed record of how each change was reviewed at that moment.

The action installs and configures the JFrog CLI for you — you only supply your
JFrog OIDC provider and signing key.

## Why JFrog Traceability

Teams enforce strong controls in GitHub — required pull-request reviews, signed
commits, and related merge gates — but that governance context stays in GitHub.
By the time a build is promoted and released, there is no tamper-evident proof
that a given change was actually reviewed when it merged. That **approval gap**
is where unreviewed or unauthorized changes can slip into a release.

JFrog Traceability closes the gap. It captures the review-and-merge context
behind each merge as **signed JFrog evidence** on the merge commit (and later
surfaced on AppTrust application versions), so the proof travels with the
software. On promotion, **JFrog AppTrust** can automatically use this evidence
and gate releases on it — turning review-and-merge controls into enforceable,
auditable release policy.

## What you get

For every pull request merged into a **selected target branch** (the branches
you list in the workflow `on.pull_request.branches` filter), the action produces
**one** signed JFrog evidence named `github-pull-request` attached to a
`gitCommit` entity whose id is the merge commit sha (`<gitSha>`). The evidence
uses the [`github-pull-request.json`](predicates/github-pull-request.json)
schema and includes a human-readable markdown report. Both the JSON predicate
and the markdown are part of the signed evidence package you can open in the
JFrog evidence **Content** tab.

Everything is **read-only** against GitHub, and secret *values* are never fetched.

### Merged pull request (`pull_request_merge`)

Who approved the PR, what commits it put on the target branch, who authored them,
and signed-commits status and details (`commit_signatures` plus an
`all_commits_verified` summary). Lives under the predicate's
`pull_request_merge` section (see the
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

**Where it lives.** Each run attaches signed evidence to a **`gitCommit`
entity** whose id is the merge commit sha (`<gitSha>`). Evidence stores it
under the default `gitCommit-entity` repository (path under
`.entities/gitCommit/...`).

**How to retrieve and verify.** Because `gitCommit-entity` holds merge
commit evidence from **multiple GitHub repositories**, access is restricted by
design to specific Artifactory permissions on that repository:

| Permission | Needed to |
|---|---|
| **Read** | List and open evidence (REST, GraphQL, UI Content tab) and run `jf evidence verify` |
| **Annotate** (with **Read**) | Create / attach new evidence (what the action’s OIDC identity needs) |

List evidence with the Evidence REST API
(`GET /evidence/api/v1/entity/gitCommit/<gitSha>`) or GraphQL
`hasEntityWith(entity_type: "gitCommit", entity_id: "<gitSha>")`, and open the
human-readable **Content** report in the JFrog UI. You can also
cryptographically verify evidence with the JFrog CLI (`jf evidence verify`).

**How it's used.** This evidence is a signed, auditable record that stands on its
own — no AppTrust required. When the resulting artifact is later bundled inside
an **AppTrust application version** and **promoted**, JFrog AppTrust
automatically consumes this Git evidence to generate new AppTrust evidence, and
AppTrust lifecycle policies can gate the promotion on it. The set of pull
requests associated with each AppTrust application version depends on the
previous application versions that reached **production** maturity, so two
applications that include the same artifact can surface different PR lists. See
[AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

## Prerequisites

You do **not** need to add `jfrog/setup-jfrog-cli` to your workflow — this
action installs and configures the latest JFrog CLI for you (URL normalization,
OIDC token exchange, and project selection) in its own step. The prerequisites
are the platform-side setup:

- An **entity repository** named `gitCommit-entity` in Artifactory
  (Evidence does not create it automatically). The OIDC identity used by this
  action must have **Read** and **Annotate** on that repository.
  Treat **Read** carefully: this repository aggregates merge commit details
  from every GitHub repository that writes evidence into the same Artifactory
  instance. Grant Read only to identities that should see cross-repo merge
  context (for example security / compliance auditors), not to broad developer
  groups.
- A platform Evidence service that includes **Evidence on Non-Artifacts**
  (entity APIs used for `gitCommit` subjects). Older Evidence builds that only
  support artifact subjects are not compatible.
- An **OIDC integration** under **Administration → OIDC**, with an identity
  mapping for this repository. Authentication uses OIDC, so no long-lived JFrog
  access token is stored — the runner exchanges its GitHub OIDC token for JFrog
  access at run time.
- An **evidence signing key** (private PEM). Upload the matching **public** key
  to the platform under the alias you will use (default alias:
  `github-evidence`) via the UI or the
  [Upload the Public Key to Artifactory](https://docs.jfrog.com/governance/docs/upload-the-public-key-to-artifactory)
  REST API (`POST /artifactory/api/security/keys/trusted`). The private key is
  the only secret you store in GitHub.

See [Required secrets and variables](#required-secrets-and-variables) for how to
wire these into your repository.

## Setup

A one-time setup, in order:

1. **Create the entity repository** `gitCommit-entity` in Artifactory.
   Limit **Read** (and **Annotate**) as described under
   [Prerequisites](#prerequisites).
2. **Register the signing key** — upload the public key to the platform with
   alias `github-evidence` (or another alias you choose) using the
   [public key upload API](https://docs.jfrog.com/governance/docs/upload-the-public-key-to-artifactory).
3. **Configure OIDC** under **Administration → OIDC** with an identity mapping
   for this GitHub repository; note the **provider name**.
4. **Add the GitHub secret and variables** (see
   [Required secrets and variables](#required-secrets-and-variables)):
   `EVIDENCE_KEY` (secret), `JF_URL`, `JF_OIDC_PROVIDER`. Add
   `EVIDENCE_KEY_ALIAS` only if your public-key alias is not `github-evidence`.
5. **Add the workflow** from [Quick start](#quick-start) to
   `.github/workflows/`.

Merge a pull request into `main` (or another configured branch) and confirm the
workflow succeeds; the evidence appears on the `gitCommit` entity for the merge
sha (see [On the JFrog platform](#on-the-jfrog-platform)).

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
      - uses: actions/checkout@v4.2.2
      - uses: jfrog/github-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
          # evidence_key_alias: ${{ vars.EVIDENCE_KEY_ALIAS }}  # optional; default github-evidence
```

The `branches: [main]` filter scopes the workflow to pull requests targeting
`main`, and the `closed` trigger plus the `if: ...merged == true` guard limits the
job to merges — so closed-unmerged PRs produce nothing. Each merge into a listed
branch then produces one `github-pull-request` evidence covering the merge. Add
more branches to the list to cover additional release branches. A runnable copy
lives in [`examples/git-evidence.yml`](examples/git-evidence.yml).

### Supported triggers and target-branch validation

The action's preflight step runs two independent checks and skips (before the
JFrog CLI is installed or OIDC is exchanged) if either fails, so skipped runs
are essentially free:

1. **Trigger check.** The event must be either a merged `pull_request: closed`
   or a `push`. Everything else (`pull_request` opened/synchronize/reopened, a
   closed but unmerged PR, `workflow_dispatch`, `branch_protection_rule`,
   `schedule`, …) is skipped with a `notice`.
2. **Target-branch check.** The branch the event merged into (for
   `pull_request`, `github.event.pull_request.base.ref`) or the branch that
   was pushed (for `push`, `github.ref_name`) must equal the **target
   branch**. The target branch is the `target_branch` input when set, and
   otherwise falls back to the repository's default branch from the event
   payload (`github.event.repository.default_branch`). PRs merging into
   feature or unlisted release branches, or pushes to non-target branches,
   are skipped with a `notice`.

The two accepted triggers, once past the target-branch check:

- **`pull_request: closed` with `merged == true`** _(recommended)_. Full PR
  context (number, approvers) is available directly from the event payload.
- **`push` to the target branch.** The collector resolves the associated PR
  from the merge commit sha via the GitHub API. Use this when the target
  branch is updated by mechanisms that don't fire `pull_request: closed`
  (merge queues that push instead of merging via the PR API, callers that
  only expose the `push` event, etc.).

### Supported merge strategies

All three GitHub strategies produce a single canonical sha per merge and are
supported by both triggers above:

| Strategy | Entity id (`merge_commit_sha`) |
|---|---|
| Create a merge commit | The 2-parent merge commit sha |
| Squash and merge | The squash commit sha |
| Rebase and merge | The tip sha of the rebased range |

For all three, approvers, `code_committers`, `commit_signatures`, and
`all_commits_verified` are read from `/pulls/{N}/commits` and are complete.
`commits_on_target_branch` reflects what landed on the target branch: the full
range for merge commits, the single squash commit for squash, and the tip of
the rebased range for rebase (the other rebased shas are not enumerated).

### Subscribing to a single trigger (recommended)

Pick **one** of the two supported triggers in your workflow. The quick-start
example above uses `pull_request`; a `push`-based equivalent looks like:

```yaml
name: JFrog Traceability
on:
  push:
    branches: [main]
permissions:
  contents: read
  pull-requests: read
  id-token: write
jobs:
  git-evidence:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.2.2
      - uses: jfrog/github-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
```

### Subscribing to both triggers — avoiding duplicates

If your workflow already subscribes to **both** `pull_request` and `push` (for
example because another job in the same workflow needs those triggers), a
single merge will fire the action twice — once from each event — and both
runs will attach an evidence document to the same `gitCommit` entity for the
same merge sha.

To keep the "one evidence per merge" invariant, add a **job-level
`concurrency`** grouped on the merge sha. GitHub cancels or queues the second
concurrent run, so only one attaches evidence:

```yaml
jobs:
  git-evidence:
    concurrency:
      group: git-evidence-${{ github.event.pull_request.merge_commit_sha || github.sha }}
      cancel-in-progress: true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.2.2
      - uses: jfrog/github-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
```

The `merge_commit_sha || github.sha` expression uses the PR's merge-commit sha
when the trigger is `pull_request`, and falls back to the pushed commit sha
when the trigger is `push`. Since both events converge on the same sha for a
given merge, both would-be runs land in the same concurrency group and only
one proceeds.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL; normalized to `https://<host>/`). |
| `oidc_provider_name` | yes | — | Name of the OIDC integration in the JFrog platform; the runner exchanges its GitHub OIDC token for JFrog access (no stored token). |
| `evidence_signing_key` | yes | — | Private key (raw PEM contents) used to sign the evidence. |
| `evidence_key_alias` | no | `github-evidence` | Signing key alias registered in the JFrog platform. Set only if you registered the public key under a different alias. |
| `target_branch` | no | `github.event.repository.default_branch` | Branch this action attests merges into. The preflight step skips events whose merge/push branch does not match. Set explicitly when your release trunk is a non-default branch (for example `release/main`), or to be tolerant of default-branch renames. |

GitHub data is read from `api.github.com` with the workflow's built-in
`GITHUB_TOKEN` (grant it `contents: read` and `pull-requests: read`).

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
| `EVIDENCE_KEY_ALIAS` | variable (optional) | Signing key alias. Required only when the public key was registered under an alias other than `github-evidence`. |

Authentication uses OIDC, so there is no stored JFrog access token — the only
secret is the signing key. Configure a matching OIDC integration in the JFrog
platform under **Administration → OIDC**, with an identity mapping for this
repository, and use its provider name as `JF_OIDC_PROVIDER`.

## Versioning

Pin the moving major tag `@v1` for automatic minor/patch updates, or a full
`@vX.Y.Z` for an immutable pin.

## Troubleshooting

| Symptom in the run log | Likely cause | Fix |
|---|---|---|
| OIDC token exchange fails in **Setup JFrog CLI** | `id-token: write` missing, or no OIDC identity mapping for this repo | Add the permission to the workflow and configure the mapping under **Administration → OIDC**. |
| `jf evd create` fails with `404` | The `gitCommit-entity` repository does not exist | Create it in Artifactory (it is not created automatically). |
| `jf evd create` fails with another `4xx`/`5xx` | Platform lacks **Evidence on Non-Artifacts** support | Upgrade to an Evidence build with entity APIs. |
| `jf evd create` fails about the key/alias | Public-key alias does not match (`github-evidence` by default, or `EVIDENCE_KEY_ALIAS`), or `EVIDENCE_KEY` is not the matching PEM | Re-check the alias and that the secret holds the full private PEM. |
| The job is skipped entirely | PR was closed without merging, or targeted a branch not in the `branches` filter | Expected — evidence is produced only on merges to the configured branches. |
| `notice: Skipping JFrog Traceability … this action only records evidence on merged pull_request events or on push …` | Preflight trigger check failed | Expected — see [Supported triggers and target-branch validation](#supported-triggers-and-target-branch-validation). |
| `notice: Skipping JFrog Traceability — event branch 'X' is not the configured target branch 'Y'` | Preflight target-branch check failed (merge/push landed on a branch other than `target_branch` or the repo default) | Expected — evidence is only recorded for merges into the configured target branch. Override with the `target_branch` input, or change the repo's default branch in Settings. |
| Two runs succeed for the same merge and two evidence documents appear on the `gitCommit` entity | The workflow subscribes to both `pull_request` and `push` events; both pass the preflight | Add job-level `concurrency` grouped on the merge sha, per [Subscribing to both triggers — avoiding duplicates](#subscribing-to-both-triggers--avoiding-duplicates). |
| `403` listing or opening evidence | Caller lacks **Read** on `gitCommit-entity` | Grant Read only to identities that should see cross-repo merge evidence. |
