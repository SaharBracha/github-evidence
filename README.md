# JFrog Traceability

A single GitHub Action that collects **Git evidence** from your repository and
attaches it to Artifactory as **signed JFrog evidence**. It runs when a pull
request is **merged**, giving you a tamper-evident, cryptographically signed
record of how each change was reviewed and how your repository was governed at
that moment.

The action installs the JFrog CLI for you — you only supply your JFrog
credentials and signing key.

## What you get

For every merged pull request, the action produces up to two signed evidence
types and attaches them to your artifact in Artifactory:

- **Branch protection** — a normalized snapshot of the repository's protected
  branches, rulesets, and CODEOWNERS enforcement at merge time. Proof of how the
  repo was governed when the change landed.
  ([schema](predicates/branch-protection.json))
- **Merged pull request** — who approved the PR, what commits it put on the
  target branch, and who authored them.
  ([schema](predicates/pull-request-merge.json))

Each evidence attachment includes:

- A **signed JSON predicate** conforming to a published schema — machine-readable
  for automated policy checks and audits.
- A **human-readable report** you can open directly in the JFrog evidence
  **Content** tab.

Everything is **read-only** against GitHub, and secret *values* are never
fetched. You can opt out of either evidence type with the
`collect_branch_protection` and `collect_pull_request_merge` inputs (both default
`true`).

## Prerequisites

Before adding the workflow, set up the following in the JFrog platform:

- A **JFrog project** (you'll reference its project key).
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
          jf_project: ${{ vars.JF_PROJECT }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
          evidence_key_alias: ${{ vars.EVIDENCE_KEY_ALIAS }}
```

The `closed` trigger fires on every PR close, but the `if` guard limits the job
to merges only — so each merged PR produces both branch-protection and merged-PR
evidence (unless disabled via the `collect_*` inputs below), and closed-unmerged
PRs produce nothing. A runnable copy lives in
[`examples/git-evidence.yml`](examples/git-evidence.yml).

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL; normalized to `https://&lt;host&gt;/`). |
| `oidc_provider_name` | yes | — | Name of the OIDC integration in the JFrog platform; the runner exchanges its GitHub OIDC token for JFrog access (no stored token). |
| `jf_project` | yes | — | JFrog project key. |
| `evidence_signing_key` | yes | — | Private key (raw PEM contents) used to sign the evidence. |
| `evidence_key_alias` | yes | — | Signing key alias registered in the JFrog platform. |
| `collect_branch_protection` | no | `true` | Generate branch-protection evidence. Set to `false` to skip it. |
| `collect_pull_request_merge` | no | `true` | Generate merged-pull-request evidence. Set to `false` to skip it. |

GitHub data is read from `api.github.com` with the workflow's built-in
`GITHUB_TOKEN` (grant it `contents: read` and `pull-requests: read`).
Branch-protection fields the token isn't allowed to read are recorded as
`unavailable` rather than failing the run.

The merged-PR number is read automatically from the triggering `pull_request`
event — there is no `pr_number` input. Each `collect_*` input is enabled only by
an exact `true`; any other value (`false`, a typo, or empty) is treated as opt-out.

## Required secrets and variables

| Name | Kind | Description |
|---|---|---|
| `EVIDENCE_KEY` | secret | Private signing key (PEM). |
| `JF_URL` | variable | JFrog platform host. |
| `JF_PROJECT` | variable | JFrog project key. |
| `JF_OIDC_PROVIDER` | variable | Name of the OIDC integration configured in the JFrog platform. |
| `EVIDENCE_KEY_ALIAS` | variable | Signing key alias. |

Authentication uses OIDC, so there is no stored JFrog access token — the only
secret is the signing key. Configure a matching OIDC integration in the JFrog
platform under **Administration → OIDC**, with an identity mapping for this
repository, and use its provider name as `JF_OIDC_PROVIDER`.

## What gets recorded

Each evidence type ships a machine-readable JSON Schema (`.json`) describing its
predicate. At merge time the action also generates a human-readable report from
the run's actual data and attaches it to the evidence (`jf evd create
--markdown`), visible in the JFrog evidence Content tab.

- Branch protection — [`branch-protection.json`](predicates/branch-protection.json)
- Merged pull request — [`pull-request-merge.json`](predicates/pull-request-merge.json)

## Versioning

Pin the moving major tag `@v1` for automatic minor/patch updates, or a full
`@vX.Y.Z` for an immutable pin.
