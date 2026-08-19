# JFrog Traceability

A GitHub Action that records signed **JFrog evidence** for every pull request merged into a configured target branch. Evidence is keyed by the merge commit sha and travels with your software through Artifactory and AppTrust.

The action installs and configures the JFrog CLI for you — you only supply your JFrog OIDC provider and signing key.

## Why

Review and merge controls (required reviews, signed commits) live in GitHub. By the time an artifact is promoted, there's no tamper-evident proof it was actually reviewed. This action captures that context as signed evidence on the merge commit so **AppTrust lifecycle policies** can gate releases on it.

## What it records

One `github-pull-request` evidence per merge, containing:

- **Merge metadata** — target branch, merge sha, merger, merged-at
- **Approvers** — reviewers, approved shas, whether approval covered the PR head
- **Commits** — shas landed on the target branch, code committers, per-commit signature verification, and an `all_commits_verified` summary

Full schema: [`predicates/github-pull-request.json`](predicates/github-pull-request.json).

## Quick start

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
      - uses: jfrog/github-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
          evidence_key_alias: ${{ vars.EVIDENCE_KEY_ALIAS }}
```

The action does not gate on the event itself — your workflow decides when it runs. The recommended trigger is **a pull request merged into your target branch**: subscribe to `pull_request: closed` on that branch and gate the job on `github.event.pull_request.merged == true`, so evidence is recorded once per merge. List every release branch you want covered under `branches`. A runnable copy lives in [`examples/git-evidence.yml`](examples/git-evidence.yml).

All three GitHub merge strategies (merge commit, squash, rebase) are supported.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL). |
| `oidc_provider_name` | yes | — | OIDC integration name in the JFrog platform. |
| `evidence_signing_key` | yes | — | Private signing key (raw PEM contents). |
| `evidence_key_alias` | yes | — | Public-key alias registered in the platform. |

## Prerequisites

One-time platform setup:

1. **Evidence signing key** — upload the public key under an alias via the [public key upload API](https://docs.jfrog.com/governance/docs/upload-the-public-key-to-artifactory). Store the private PEM as the `EVIDENCE_KEY` secret.
2. **OIDC integration** under **Administration → OIDC** with an identity mapping for this repository.
3. **GitHub config**: secret `EVIDENCE_KEY`; variables `JF_URL`, `JF_OIDC_PROVIDER`, `EVIDENCE_KEY_ALIAS`.

The platform's Evidence service must support **entity evidence APIs** (not just artifact subjects).

## On the JFrog platform

When the merged artifact is bundled into an **AppTrust application version** and promoted, AppTrust consumes this evidence automatically and lifecycle policies can gate the promotion. See [AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| OIDC exchange fails | `id-token: write` missing, or no identity mapping | Add the permission; configure the mapping under **Administration → OIDC**. |
| `jf evd create` fails with `404` | evidence entity repository missing | Create it in Artifactory. |
| `jf evd create` key/alias error | Alias mismatch, or `EVIDENCE_KEY` not the matching PEM | Recheck alias and secret contents. |
| Action ran on an unmerged PR | Job not gated on the merge | Add `if: github.event.pull_request.merged == true` to the job. |
| `403` reading evidence | Missing **Read** on the evidence entity repository | Grant Read narrowly. |
