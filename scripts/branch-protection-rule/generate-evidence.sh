#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Orchestrates evidence generation for a branch_protection_rule webhook event
# (types: created, edited, deleted). Reads the event payload from
# GITHUB_EVENT_PATH, collects the full branch-protection API snapshot, shapes
# them into the "branch-protection-rule" predicate + subject, renders a
# markdown report, then creates one signed evidence on the JFrog application
# entity identified by APP_KEY (also passed as ?app_key=<APP_KEY> on create).
#
# Required env: GITHUB_TOKEN, GITHUB_EVENT_PATH, GITHUB_REPOSITORY, APP_KEY,
#   EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

: "${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH must be set (runner-provided)}"
: "${APP_KEY:?APP_KEY must be set (repo variable APP_KEY)}"

if [[ ! -f "$GITHUB_EVENT_PATH" ]]; then
  echo "::error::GITHUB_EVENT_PATH not found: ${GITHUB_EVENT_PATH}" >&2
  exit 1
fi

PREDICATE_TYPE="https://jfrog.com/evidence/branch-protection-rule/v1"
ENTITY_TYPE="application"
ENTITY_ID="$APP_KEY"

main() {
  echo "::group::branch-protection-rule evidence"

  cp "$GITHUB_EVENT_PATH" event.json

  "${SCRIPT_DIR}/../branch-protection/collect-settings-snapshot.sh" > snapshot.json

  EVENT_PAYLOAD_FILE=event.json SNAPSHOT_FILE=snapshot.json \
    PREDICATE_TYPE="$PREDICATE_TYPE" \
    "${SCRIPT_DIR}/build-predicate.sh"

  PREDICATE_FILE=predicate.json SUBJECT_FILE=subject.json MARKDOWN_OUT=report.md \
    "${SCRIPT_DIR}/build-markdown.sh"

  PREDICATE_FILE=predicate.json PREDICATE_TYPE="$PREDICATE_TYPE" \
    ENTITY_TYPE="$ENTITY_TYPE" ENTITY_ID="$ENTITY_ID" \
    MARKDOWN_FILE=report.md \
    APP_KEY="$APP_KEY" \
    "${SCRIPT_DIR}/../create-entity-evidence.sh"

  echo "::endgroup::"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
