#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Orchestrates evidence generation for a merged pull request. Collects the
# pull-request-merge snapshot, shapes it into the "github-pull-request"
# predicate + subject, renders a human-readable markdown report, then creates
# one signed evidence on the pull-request entity. This is the body of
# action.yml's "Generate git evidence" step, lifted into a real script so it
# is statically linted, locally runnable, and unit-testable.
#
# The evidence is attached to a githubPullRequest entity whose id is the readable
# "{owner}-{repo}-{prID}" identity.
#
# Required env: GITHUB_REPOSITORY, GITHUB_SHA (or PR_NUMBER), plus everything
#   the collector / build / create scripts require (GITHUB_TOKEN,
#   EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS, ...). When PR_NUMBER is not set
#   (e.g. push-to-main runs), it is resolved from GITHUB_SHA via the GitHub API.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=./lib/github-api.sh
source "${SCRIPT_DIR}/lib/github-api.sh"

resolve_owner_repo
resolve_pr_number

PREDICATE_TYPE="https://jfrog.com/evidence/pull-request-merge/v1"
ENTITY_TYPE="githubPullRequest"
ENTITY_ID="${GH_OWNER}-${GH_REPO}-${PR_NUMBER}"

# Collect the merge snapshot, shape the predicate + subject, render the
# markdown report, then create one signed entity evidence.
main() {
  echo "::group::github-pull-request evidence"

  "${SCRIPT_DIR}/pull-request-merge/collect-pr-merge.sh" > pr-raw.json

  PR_RAW_SNAPSHOT_FILE=pr-raw.json \
    PREDICATE_TYPE="$PREDICATE_TYPE" \
    "${SCRIPT_DIR}/build-predicate.sh"

  PREDICATE_FILE=predicate.json SUBJECT_FILE=subject.json MARKDOWN_OUT=report.md \
    "${SCRIPT_DIR}/build-markdown.sh"

  PREDICATE_FILE=predicate.json PREDICATE_TYPE="$PREDICATE_TYPE" \
    ENTITY_TYPE="$ENTITY_TYPE" ENTITY_ID="$ENTITY_ID" \
    MARKDOWN_FILE=report.md \
    "${SCRIPT_DIR}/create-entity-evidence.sh"

  echo "::endgroup::"
}

# Run the orchestration only when executed directly, so tests can source this
# file to exercise helpers / main (with stubbed collaborators) in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
