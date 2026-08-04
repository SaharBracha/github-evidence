#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Local smoke test: prepare → DSSE sign → create evidence on githubPullRequest entity.
# Targets the default entity repo `githubPullRequest-entity` (no project/application scope).
# Default predicate + markdown come from fixtures/unified-github-pull-request-predicate.json.
#
# Required env:
#   JF_URL              Platform base URL, e.g. http://localhost:8082
#   JF_ACCESS_TOKEN     Bearer token with annotate on githubPullRequest-entity
#   EVIDENCE_SIGNING_KEY  Private PEM contents, or set EVIDENCE_SIGNING_KEY_FILE
#   EVIDENCE_KEY_ALIAS  Key alias registered in Artifactory
#
# Optional env:
#   ENTITY_TYPE         Default: githubPullRequest
#   ENTITY_ID           Default: {owner}-{repo}-{prID} from fixture + PR_NUMBER
#   PR_NUMBER           Default: 1 (used when ENTITY_ID is unset)
#   PREDICATE_FILE      Default: fixtures/unified-github-pull-request-predicate.json
#   MARKDOWN_FILE       Default: rendered from the predicate via build-markdown.sh
#   PROVIDER_ID         Default: github-actions
#   SKIP_LIST           If set, skip the final GET
#
# Example:
#   JF_URL=http://localhost:8082 \
#   JF_ACCESS_TOKEN=... \
#   EVIDENCE_SIGNING_KEY_FILE=./private.pem \
#   EVIDENCE_KEY_ALIAS=my-key \
#   bash scripts/smoke-entity-evidence.sh
set -euo pipefail
set +x

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DEFAULT_PREDICATE="${SCRIPT_DIR}/fixtures/unified-github-pull-request-predicate.json"

: "${JF_URL:?JF_URL must be set}"
: "${JF_ACCESS_TOKEN:?JF_ACCESS_TOKEN must be set}"
: "${EVIDENCE_KEY_ALIAS:?EVIDENCE_KEY_ALIAS must be set}"

if [[ -n "${EVIDENCE_SIGNING_KEY_FILE:-}" ]]; then
  EVIDENCE_SIGNING_KEY="$(< "$EVIDENCE_SIGNING_KEY_FILE")"
fi
: "${EVIDENCE_SIGNING_KEY:?EVIDENCE_SIGNING_KEY or EVIDENCE_SIGNING_KEY_FILE must be set}"

JF_URL="${JF_URL%/}"
ENTITY_TYPE="${ENTITY_TYPE:-githubPullRequest}"
PROVIDER_ID="${PROVIDER_ID:-github-actions}"
PREDICATE_FILE="${PREDICATE_FILE:-$DEFAULT_PREDICATE}"

if [[ ! -f "$PREDICATE_FILE" ]]; then
  echo "::error::PREDICATE_FILE not found: ${PREDICATE_FILE}" >&2
  exit 1
fi

PREDICATE_TYPE="${PREDICATE_TYPE:-$(jq -r '.predicate_type // "https://jfrog.com/evidence/pull-request-merge/v1"' "$PREDICATE_FILE")}"
# Default id: readable "{owner}-{repo}-{prID}" from the fixture repository.
if [[ -z "${ENTITY_ID:-}" ]]; then
  owner="$(jq -r '.branch_protection.repository.owner // empty' "$PREDICATE_FILE")"
  repo="$(jq -r '.branch_protection.repository.name // empty' "$PREDICATE_FILE")"
  pr="${PR_NUMBER:-1}"
  if [[ -n "$owner" && -n "$repo" ]]; then
    ENTITY_ID="${owner}-${repo}-${pr}"
  else
    ENTITY_ID="$(openssl rand -hex 20)"
  fi
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/smoke-entity-evidence.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

KEY_FILE="${WORKDIR}/key.pem"
PREPARE_REQ="${WORKDIR}/prepare-req.json"
PREPARE_RESP="${WORKDIR}/prepare-resp.json"
ENVELOPE="${WORKDIR}/envelope.json"
CREATE_RESP="${WORKDIR}/create-resp.json"
PREDICATE_PATH="${WORKDIR}/predicate.json"
MARKDOWN_PATH="${WORKDIR}/report.md"

( umask 077; printf '%s\n' "$EVIDENCE_SIGNING_KEY" > "$KEY_FILE" )
chmod 600 "$KEY_FILE"

# Prepare expects the predicate object; drop top-level predicate_type if present
# so it is only sent as the separate prepare field.
jq 'del(.predicate_type)' "$PREDICATE_FILE" > "$PREDICATE_PATH"

if [[ -n "${MARKDOWN_FILE:-}" ]]; then
  if [[ ! -f "$MARKDOWN_FILE" ]]; then
    echo "::error::MARKDOWN_FILE not found: ${MARKDOWN_FILE}" >&2
    exit 1
  fi
  cp "$MARKDOWN_FILE" "$MARKDOWN_PATH"
else
  PREDICATE_FILE="$PREDICATE_PATH" MARKDOWN_OUT="$MARKDOWN_PATH" \
    "${SCRIPT_DIR}/build-markdown.sh"
fi

jq_args=(
  -n
  --slurpfile predicate "$PREDICATE_PATH"
  --arg predicate_type "$PREDICATE_TYPE"
  --arg provider_id "$PROVIDER_ID"
  --arg entity_type "$ENTITY_TYPE"
  --arg entity_id "$ENTITY_ID"
  --rawfile markdown "$MARKDOWN_PATH"
)
jq_filter='{
  predicate: $predicate[0],
  predicate_type: $predicate_type,
  provider_id: $provider_id,
  markdown: $markdown,
  subject: {
    subject_type: "entity",
    entity_type: $entity_type,
    entity_id: $entity_id
  }
}'

jq "${jq_args[@]}" "$jq_filter" > "$PREPARE_REQ"

echo "→ prepare  entity=${ENTITY_TYPE}/${ENTITY_ID}  (repo githubPullRequest-entity)" >&2
echo "  predicate=${PREDICATE_FILE}" >&2
http_code="$(
  curl -sS -o "$PREPARE_RESP" -w '%{http_code}' \
    -X POST "${JF_URL}/evidence/api/v1/evidence/prepare" \
    -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @"$PREPARE_REQ"
)"
if [[ "$http_code" != "200" ]]; then
  echo "::error::prepare failed HTTP ${http_code}" >&2
  cat "$PREPARE_RESP" >&2 || true
  exit 1
fi

post_url="$(jq -r '.post_url // empty' "$PREPARE_RESP")"
if [[ -z "$post_url" ]]; then
  echo "::error::prepare response missing post_url" >&2
  cat "$PREPARE_RESP" >&2
  exit 1
fi
echo "  post_url=${post_url}" >&2

echo "→ sign" >&2
node "${SCRIPT_DIR}/lib/sign-dsse.mjs" \
  --prepare-response "$PREPARE_RESP" \
  --key "$KEY_FILE" \
  --key-id "$EVIDENCE_KEY_ALIAS" \
  > "$ENVELOPE"

echo "→ create" >&2
http_code="$(
  curl -sS -o "$CREATE_RESP" -w '%{http_code}' \
    -X POST "${JF_URL}${post_url}" \
    -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @"$ENVELOPE"
)"
if [[ "$http_code" != "201" && "$http_code" != "200" ]]; then
  echo "::error::create failed HTTP ${http_code}" >&2
  cat "$CREATE_RESP" >&2 || true
  exit 1
fi

echo "  created:" >&2
jq '{id, name, repository, path, sha256}' "$CREATE_RESP" >&2 || cat "$CREATE_RESP" >&2

if [[ -z "${SKIP_LIST:-}" ]]; then
  echo "→ list" >&2
  curl -sS \
    "${JF_URL}/evidence/api/v1/entity/${ENTITY_TYPE}/${ENTITY_ID}" \
    -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
    | jq .
fi

echo "OK  entity=${ENTITY_TYPE}/${ENTITY_ID}" >&2
