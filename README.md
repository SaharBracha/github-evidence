# JFrog Traceability

A GitHub Action that records signed **JFrog evidence** for every pull request merged into a configured target branch. Evidence is attached to a `gitCommit` entity keyed by the merge commit sha and travels with your software through Artifactory and AppTrust.

The action installs and configures the JFrog CLI for you — you only supply your JFrog OIDC provider and signing key.

## Why

Review and merge controls (required reviews, signed commits, branch protections) live in GitHub. By the time an artifact is promoted, there's no tamper-evident proof it was actually reviewed. This action captures that context as signed evidence on the merge commit so **AppTrust lifecycle policies** can gate releases on it.

## What it records

One `github-pull-request` evidence per merge, containing:

- **Merge metadata** — target branch, merge sha, merger, merged-at
- **Approvers** — reviewers, approved shas, whether approval covered the PR head
- **Commits** — shas landed on the target branch, code committers, per-commit signature verification, and an `all_commits_verified` summary

Full schema: [`predicates/github-pull-request.json`](predicates/github-pull-request.json).

Identities come straight from what GitHub attests. Missing pieces (approver email, committer login) are filled best-effort using the built-in `GITHUB_TOKEN`; anything unresolved is left `null` rather than guessed.

## Quick start

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

Subscribe to `push` on your target branch — the action rejects other triggers so a single merge can't fan out to duplicate runs. A runnable copy lives in [`examples/git-evidence.yml`](examples/git-evidence.yml).

All three GitHub merge strategies (merge commit, squash, rebase) are supported.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL). |
| `oidc_provider_name` | yes | — | OIDC integration name in the JFrog platform. |
| `evidence_signing_key` | yes | — | Private signing key (raw PEM contents). |
| `evidence_key_alias` | no | `github-evidence` | Public-key alias registered in the platform. |
| `target_branch` | no | repo default branch | Branch this action attests merges into. |

## Prerequisites

One-time platform setup:

1. **Entity repository** `gitCommit-entity` in Artifactory. The action's OIDC identity needs **Read** and **Annotate**. This repo aggregates merge context across every GitHub repository writing to the same platform — grant Read narrowly (auditors, not broad dev groups).
2. **Evidence signing key** — upload the public key under alias `github-evidence` (or your own) via the [public key upload API](https://docs.jfrog.com/governance/docs/upload-the-public-key-to-artifactory). Store the private PEM as the `EVIDENCE_KEY` secret.
3. **OIDC integration** under **Administration → OIDC** with an identity mapping for this repository.
4. **GitHub config**: secret `EVIDENCE_KEY`; variables `JF_URL`, `JF_OIDC_PROVIDER` (and `EVIDENCE_KEY_ALIAS` if non-default).

The platform's Evidence service must support **entity evidence APIs** (not just artifact subjects).

## On the JFrog platform

Evidence is stored under `.entities/gitCommit/...` in the `gitCommit-entity` repo. Retrieve via:

- REST: `GET /evidence/api/v1/entity/gitCommit/<gitSha>`
- GraphQL: `hasEntityWith(entity_type: "gitCommit", entity_id: "<gitSha>")`
- CLI verify: `jf evidence verify`
- UI: the **Content** tab

When the merged artifact is bundled into an **AppTrust application version** and promoted, AppTrust consumes this evidence automatically and lifecycle policies can gate the promotion. See [AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

## Versioning

Pin `@v1` for automatic minor/patch updates, or `@vX.Y.Z` for an immutable pin.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| OIDC exchange fails | `id-token: write` missing, or no identity mapping | Add the permission; configure the mapping under **Administration → OIDC**. |
| `jf evd create` fails with `404` | `gitCommit-entity` repository missing | Create it in Artifactory. |
| `jf evd create` key/alias error | Alias mismatch, or `EVIDENCE_KEY` not the matching PEM | Recheck alias and secret contents. |
| Run skipped with a `notice` | Event wasn't a `push` to the target branch | Expected — subscribe to `push` on the correct branch. |
| `403` reading evidence | Missing **Read** on `gitCommit-entity` | Grant Read narrowly. |
