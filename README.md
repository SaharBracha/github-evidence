# JFrog Git Evidence

A single GitHub Action that collects **Git evidence** and attaches it to
Artifactory as **signed JFrog evidence**. It runs when a pull request is
**merged** and, without you choosing an evidence type, produces both:

- **Branch protection** — a normalized snapshot of the repository's protected
  branches, rulesets, and CODEOWNERS enforcement at merge time.
  ([schema](predicates/branch-protection.json))
- **Merged pull request** — who approved the PR, what commits it put on the
  target branch, and who authored them.
  ([schema](predicates/pull-request-merge.json))

The action installs the JFrog CLI itself, so you only supply your JFrog
credentials and signing key.

## Quick start

Drop this one workflow into `.github/workflows/`:

```yaml
name: JFrog Git Evidence
on:
  pull_request:
    types: [closed]
permissions:
  contents: read
  pull-requests: read
  id-token: write
jobs:
  git-evidence:
    # GitHub has no "merged" trigger; listen on closed PRs and gate on merged.
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
evidence, and closed-unmerged PRs produce nothing. A runnable copy lives in
[`examples/git-evidence.yml`](examples/git-evidence.yml).

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `jf_url` | yes | — | JFrog platform host (bare host or URL; normalized to `https://<host>/`). |
| `oidc_provider_name` | yes | — | Name of the OIDC integration in the JFrog platform; the runner exchanges its GitHub OIDC token for JFrog access (no stored token). |
| `jf_project` | yes | — | JFrog project key. |
| `evidence_signing_key` | yes | — | Private key (raw PEM contents) used to sign the evidence. |
| `evidence_key_alias` | yes | — | Signing key alias registered in the JFrog platform. |
| `github_token` | no | `${{ github.token }}` | Token used to read repository data. |
| `gh_api_host` | no | `https://api.github.com` | GitHub REST API base URL (set for GHES). |
| `upload_subject` | no | `true` | Upload the subject artifact before attaching evidence. |
| `include_raw_snapshot` | no | `true` | Embed the full collector snapshot in the branch-protection predicate. |

The merged-PR number is read automatically from the triggering
`pull_request` event — there is no `pr_number` input.

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

## Versioning

Pin the moving major tag `@v1` for automatic minor/patch updates, or a full
`@vX.Y.Z` for an immutable pin.

## Predicates

Each evidence type ships a machine-readable JSON Schema (`.json`) describing its
predicate. At merge time the action also generates a human-readable report from
the run's actual data and attaches it to the evidence (`jf evd create
--markdown`), visible in the JFrog evidence Content tab.

- Branch protection — [`branch-protection.json`](predicates/branch-protection.json)
- Merged pull request — [`pull-request-merge.json`](predicates/pull-request-merge.json)

## Publishing to the GitHub Marketplace

- Public repo, root `action.yml` with `branding`, a `LICENSE`, and a unique
  action name (`JFrog Git Evidence`).
- Create a GitHub Release with a semver tag and tick **"Publish this Action to
  the GitHub Marketplace."**
- Maintain a moving `v1` tag that customers reference; keep the examples on `@v1`.

## Development

```bash
bash tests/run-tests.sh          # offline, fixture-driven test suites
shellcheck --severity=warning scripts/*.sh scripts/lib/*.sh tests/*.sh tests/lib/curl
```
