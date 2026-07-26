#!/usr/bin/env bash
# Orchestrates evidence generation for a merged pull request. For each enabled
# evidence type it collects a raw snapshot, shapes the predicate + subject,
# renders a human-readable markdown report, then signs and uploads. This is the
# body of action.yml's "Generate git evidence" step, lifted into a real script
# so it is shellcheck-covered, locally runnable, and unit-testable.
#
# Runtime working files (raw-snapshot.json, predicate.json, subject.json,
# report.md) are reused between evidence types, so each type is fully signed and
# uploaded before the next overwrites them.
#
# Required env: GITHUB_REPOSITORY, MERGE_COMMIT_SHA, plus everything the
#   collector / build / sign scripts require (GITHUB_TOKEN, PR_NUMBER,
#   PROJECT_KEY, EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS, ...).
# Optional env: COLLECT_BRANCH_PROTECTION, COLLECT_PULL_REQUEST_MERGE (each
#   defaults to "true"; only an exact "true" enables its evidence type - any
#   other value, including a typo or empty string, is treated as opt-out).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${MERGE_COMMIT_SHA:?MERGE_COMMIT_SHA must be set}"
resolve_owner_repo

# Short form of the merge commit SHA (first 8 chars) keeps subject paths
# readable; full-length collisions aren't a concern within one repo.
CHANGE_SHA="${MERGE_COMMIT_SHA:0:8}"

# Both evidence types share one subject naming structure keyed to the merge:
# <owner>-<type>-<short-merge-commit-sha>, so they stay aligned to the change.
evidence_subject_path() {
  local etype="$1"
  printf 'git-evidence/%s/%s-%s-%s.json' "$etype" "$GH_OWNER" "$etype" "$CHANGE_SHA"
}

# Collect one evidence type, shape its predicate + subject, render the markdown
# report, then sign and upload it.
generate() {
  local etype="$1" predicate_type="$2"
  local subject_repo_path
  subject_repo_path="$(evidence_subject_path "$etype")"
  echo "::group::${etype} evidence"

  case "$etype" in
    pull-request-merge) "${SCRIPT_DIR}/collect-pr-merge.sh" > raw-snapshot.json ;;
    branch-protection)  "${SCRIPT_DIR}/collect-settings-snapshot.sh" > raw-snapshot.json ;;
  esac

  EVIDENCE_TYPE="$etype" RAW_SNAPSHOT_FILE=raw-snapshot.json \
    PREDICATE_TYPE="$predicate_type" \
    "${SCRIPT_DIR}/build-predicate.sh"

  EVIDENCE_TYPE="$etype" PREDICATE_FILE=predicate.json \
    SUBJECT_FILE=subject.json MARKDOWN_OUT=report.md \
    "${SCRIPT_DIR}/build-markdown.sh"

  SUBJECT_FILE=subject.json PREDICATE_FILE=predicate.json \
    SUBJECT_REPO_PATH="$subject_repo_path" PREDICATE_TYPE="$predicate_type" \
    MARKDOWN_FILE=report.md \
    "${SCRIPT_DIR}/sign-and-upload.sh"

  echo "::endgroup::"
}

# This action is intended to run on a merged pull request (gate the calling job
# on github.event.pull_request.merged == true). Both evidence types are recorded
# by default; each can be opted out via its collect_* input.
main() {
  local collect_bp collect_pr
  collect_bp="${COLLECT_BRANCH_PROTECTION:-true}"
  collect_pr="${COLLECT_PULL_REQUEST_MERGE:-true}"

  if [ "$collect_bp" != "true" ] && [ "$collect_pr" != "true" ]; then
    echo "::warning::Both evidence types are disabled (collect_branch_protection=false, collect_pull_request_merge=false); nothing to generate."
  fi

  if [ "$collect_bp" = "true" ]; then
    generate "branch-protection" \
      "https://jfrog.com/evidence/branch-protection/v1"
  else
    echo "Skipping branch-protection evidence (collect_branch_protection=false)."
  fi

  if [ "$collect_pr" = "true" ]; then
    generate "pull-request-merge" \
      "https://jfrog.com/evidence/pull-request-merge/v1"
  else
    echo "Skipping pull-request-merge evidence (collect_pull_request_merge=false)."
  fi
}

# Run the orchestration only when executed directly, so tests can source this
# file to exercise evidence_subject_path / main (with a stubbed generate) in
# isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
