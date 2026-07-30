#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Orchestrates evidence generation for a merged pull request. Collects both the
# pull-request-merge and branch-protection snapshots, shapes them into a single
# unified "git-commit" predicate + subject, renders a human-readable markdown
# report, then creates one signed evidence on the merge commit entity. This is
# the body of action.yml's "Generate git evidence" step, lifted into a real
# script so it is statically linted, locally runnable, and unit-testable.
#
# Required env: GITHUB_REPOSITORY, MERGE_COMMIT_SHA, plus everything the
#   collector / build / create scripts require (GITHUB_TOKEN, PR_NUMBER,
#   PROJECT_KEY, EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS, ...).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${MERGE_COMMIT_SHA:?MERGE_COMMIT_SHA must be set}"
resolve_owner_repo

PREDICATE_TYPE="https://jfrog.com/evidence/git-commit/v1"
ENTITY_TYPE="gitCommit"

# Collect both snapshots, shape the unified predicate + subject, render the
# markdown report, then create one signed entity evidence.
main() {
  echo "::group::git-commit evidence"

  "${SCRIPT_DIR}/pull-request-merge/collect-pr-merge.sh" > pr-raw.json
  "${SCRIPT_DIR}/branch-protection/collect-settings-snapshot.sh" > bp-raw.json

  PR_RAW_SNAPSHOT_FILE=pr-raw.json BP_RAW_SNAPSHOT_FILE=bp-raw.json \
    PREDICATE_TYPE="$PREDICATE_TYPE" \
    "${SCRIPT_DIR}/build-predicate.sh"

  PREDICATE_FILE=predicate.json SUBJECT_FILE=subject.json MARKDOWN_OUT=report.md \
    "${SCRIPT_DIR}/build-markdown.sh"

  PREDICATE_FILE=predicate.json PREDICATE_TYPE="$PREDICATE_TYPE" \
    ENTITY_TYPE="$ENTITY_TYPE" ENTITY_ID="$MERGE_COMMIT_SHA" \
    MARKDOWN_FILE=report.md \
    "${SCRIPT_DIR}/create-entity-evidence.sh"

  echo "::endgroup::"
}

# Run the orchestration only when executed directly, so tests can source this
# file to exercise helpers / main (with stubbed collaborators) in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
