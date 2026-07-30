#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Creates signed JFrog evidence on a non-artifact entity via the Evidence
# prepare + entity create APIs. Assumes the JFrog CLI is already configured
# (setup-jfrog-cli / jf c) so `jf api` can authenticate against the platform.
#
# Required env: PREDICATE_FILE, PREDICATE_TYPE, PROJECT_KEY, ENTITY_TYPE,
#               ENTITY_ID, EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS.
# Optional env: MARKDOWN_FILE (human-readable report included in prepare),
#               PROVIDER_ID (default github-actions).
set -euo pipefail
# This script writes the private signing key to disk. Force xtrace off so an
# inherited `set -x` or RUNNER_DEBUG=1 can never echo the PEM into the run log.
set +x

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
: "${PREDICATE_TYPE:?PREDICATE_TYPE must be set}"
: "${PROJECT_KEY:?PROJECT_KEY must be set}"
: "${ENTITY_TYPE:?ENTITY_TYPE must be set}"
: "${ENTITY_ID:?ENTITY_ID must be set}"
: "${EVIDENCE_SIGNING_KEY:?EVIDENCE_SIGNING_KEY must be set}"
: "${EVIDENCE_KEY_ALIAS:?EVIDENCE_KEY_ALIAS must be set}"

PROVIDER_ID="${PROVIDER_ID:-github-actions}"

if [[ ! -f "$PREDICATE_FILE" ]]; then
  echo "::error::PREDICATE_FILE not found: ${PREDICATE_FILE}" >&2
  exit 1
fi

# Register cleanup before creating the key file, and create it with a
# restrictive umask, so the private key is never briefly world-readable and is
# always removed on exit (including if a signal arrives mid-write).
cleanup() {
  rm -f evidence-signing-key.pem prepare-req.json prepare-resp.json envelope.json create-resp.json
}
trap cleanup EXIT
( umask 077; printf '%s\n' "$EVIDENCE_SIGNING_KEY" > evidence-signing-key.pem )
chmod 600 evidence-signing-key.pem

jq_args=(
  -n
  --slurpfile predicate "$PREDICATE_FILE"
  --arg predicate_type "$PREDICATE_TYPE"
  --arg provider_id "$PROVIDER_ID"
  --arg project_key "$PROJECT_KEY"
  --arg entity_type "$ENTITY_TYPE"
  --arg entity_id "$ENTITY_ID"
)
jq_filter='{
  predicate: $predicate[0],
  predicate_type: $predicate_type,
  provider_id: $provider_id,
  project_key: $project_key,
  subject: {
    subject_type: "entity",
    entity_type: $entity_type,
    entity_id: $entity_id
  }
}'

if [[ -n "${MARKDOWN_FILE:-}" ]]; then
  if [[ -f "$MARKDOWN_FILE" ]]; then
    echo "Including markdown report ${MARKDOWN_FILE}" >&2
    jq_args+=(--rawfile markdown "$MARKDOWN_FILE")
    jq_filter+=' | . + {markdown: $markdown}'
  else
    echo "::warning::MARKDOWN_FILE set but not found: ${MARKDOWN_FILE}; skipping markdown" >&2
  fi
fi

jq "${jq_args[@]}" "$jq_filter" > prepare-req.json

echo "Preparing evidence for entity ${ENTITY_TYPE}/${ENTITY_ID} (project ${PROJECT_KEY})" >&2
# jf api prints HTTP status on stderr; body on stdout. Non-2xx exits 1.
if ! jf api /evidence/api/v1/evidence/prepare \
  -X POST \
  -H "Content-Type: application/json" \
  --input prepare-req.json \
  > prepare-resp.json; then
  echo "::error::evidence prepare failed" >&2
  cat prepare-resp.json >&2 || true
  exit 1
fi

post_url="$(jq -r '.post_url // empty' prepare-resp.json)"
if [[ -z "$post_url" ]]; then
  echo "::error::prepare response missing post_url" >&2
  cat prepare-resp.json >&2
  exit 1
fi

node "${SCRIPT_DIR}/lib/sign-dsse.mjs" \
  --prepare-response prepare-resp.json \
  --key ./evidence-signing-key.pem \
  --key-id "$EVIDENCE_KEY_ALIAS" \
  > envelope.json

echo "Creating evidence at ${post_url}" >&2
if ! jf api "$post_url" \
  -X POST \
  -H "Content-Type: application/json" \
  --input envelope.json \
  > create-resp.json; then
  echo "::error::evidence create failed" >&2
  cat create-resp.json >&2 || true
  exit 1
fi
rm -f create-resp.json

echo "Evidence uploaded successfully" >&2
