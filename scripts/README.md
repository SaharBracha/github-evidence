# Local entity evidence smoke test

[`smoke-entity-evidence.sh`](smoke-entity-evidence.sh) creates signed evidence on a
`githubPullRequest` entity via the Evidence **prepare → sign → create** APIs.

It uses the **default** entity repository `githubPullRequest-entity` (no `project_key` /
`application-key` / `repo` scope).

Default sample data is [`fixtures/unified-github-pull-request-predicate.json`](fixtures/unified-github-pull-request-predicate.json)
(unified github-pull-request predicate). Markdown is rendered from that predicate with
[`build-markdown.sh`](build-markdown.sh). The entity id defaults to the
`{owner}-{repo}-{prID}` identity from the fixture repository.

Requires a platform Evidence build that includes non-artifact entity APIs
(Evidence on Non-Artifacts).

## Prerequisites

- `curl`, `jq`, `node`, `openssl`
- Artifactory repository named **`githubPullRequest-entity`**
- Access token that can **annotate** that repository
- Evidence signing key (private PEM) whose **alias** is registered in the platform

## Run

From the repository root:

```bash
JF_URL=http://localhost:8082 \
JF_ACCESS_TOKEN=<token> \
EVIDENCE_SIGNING_KEY_FILE=./private.pem \
EVIDENCE_KEY_ALIAS=<key-alias> \
bash scripts/smoke-entity-evidence.sh
```

Or with the PEM contents in the environment:

```bash
JF_URL=http://localhost:8082 \
JF_ACCESS_TOKEN=<token> \
EVIDENCE_SIGNING_KEY="$(cat ./private.pem)" \
EVIDENCE_KEY_ALIAS=<key-alias> \
bash scripts/smoke-entity-evidence.sh
```

## Environment

| Variable | Required | Description |
|---|---|---|
| `JF_URL` | yes | Platform base URL (e.g. `http://localhost:8082`) |
| `JF_ACCESS_TOKEN` | yes | Bearer token |
| `EVIDENCE_KEY_ALIAS` | yes | Signing key alias in Artifactory |
| `EVIDENCE_SIGNING_KEY_FILE` | one of | Path to private PEM file |
| `EVIDENCE_SIGNING_KEY` | one of | Private PEM contents |
| `ENTITY_ID` | no | Entity id (default: hex-encoded `{owner}-{repo}-{prID}` from fixture + `PR_NUMBER`) |
| `PR_NUMBER` | no | PR id used in the default entity id (default: `1`) |
| `PREDICATE_FILE` | no | Predicate JSON (default: unified fixture) |
| `MARKDOWN_FILE` | no | Markdown override (default: rendered from predicate) |
| `PROVIDER_ID` | no | Default `github-actions` |
| `SKIP_LIST` | no | If set, skip the final list GET |

## What it does

1. Loads the unified predicate fixture (or `PREDICATE_FILE`)
2. Renders markdown via `build-markdown.sh` (or uses `MARKDOWN_FILE`)
3. `POST /evidence/api/v1/evidence/prepare` with `subject_type=entity`,
   `entity_type=githubPullRequest`
4. Signs the returned DSSE payload with [`lib/sign-dsse.mjs`](lib/sign-dsse.mjs)
5. `POST` the envelope to the returned `post_url`
   (`/evidence/api/v1/entity/githubPullRequest/{id}`)
6. `GET` the same entity to list evidence (unless `SKIP_LIST` is set)

On success, stderr prints the created evidence id/name/path and stdout shows the
list response.
