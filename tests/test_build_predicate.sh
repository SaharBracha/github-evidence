#!/usr/bin/env bash
# Tests for scripts/build-predicate.sh: shapes collector output into the two
# predicates and their subject files, for both evidence types.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

test_pull_request_merge_predicate_and_subject() {
  local raw pred subj
  raw="${WORK}/raw-pr.json"; pred="${WORK}/pred-pr.json"; subj="${WORK}/subj-pr.json"

  GITHUB_TOKEN="t" GITHUB_REPOSITORY="acme/widget" GITHUB_SERVER_URL="https://github.com" \
    GITHUB_RUN_ID="5" PR_NUMBER="7" \
    MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-success.json" \
    "${REPO_ROOT}/scripts/pull-request-merge/collect-pr-merge.sh" > "$raw" || return 1

  EVIDENCE_TYPE=pull-request-merge RAW_SNAPSHOT_FILE="$raw" PREDICATE_OUT="$pred" SUBJECT_OUT="$subj" \
    "${REPO_ROOT}/scripts/build-predicate.sh" || return 1

  assert_valid_json "$(cat "$pred")" "predicate must be valid JSON" || return 1
  assert_equal "1.2" "$(jq -r '.schema_version' "$pred")" "schema_version bumped to 1.2" || return 1
  assert_equal "PullRequestMerge" "$(jq -r '.subject_type' "$pred")" "subject_type" || return 1
  assert_equal "null" "$(jq -r '.review // "null"' "$pred")" "the review block must be dropped" || return 1
  assert_equal "mergesha" "$(jq -r '.merge.merge_commit_sha' "$pred")" "merge commit carried through" || return 1
  assert_equal "2" "$(jq '.approvers | length' "$pred")" "approvers carried through" || return 1

  assert_equal "headsha" "$(jq -r '.head_sha' "$subj")" "subject head_sha" || return 1
  assert_equal "7" "$(jq -r '.pr_number' "$subj")" "subject pr_number"
}

test_branch_protection_predicate_and_subject() {
  local raw pred subj
  raw="${WORK}/raw-bp.json"; pred="${WORK}/pred-bp.json"; subj="${WORK}/subj-bp.json"

  GITHUB_TOKEN="t" GITHUB_REPOSITORY="acme/widget" \
    MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/full-success.json" \
    env -u GH_OWNER -u GH_REPO "${REPO_ROOT}/scripts/branch-protection/collect-settings-snapshot.sh" > "$raw" || return 1

  EVIDENCE_TYPE=branch-protection RAW_SNAPSHOT_FILE="$raw" \
    GITHUB_REPOSITORY="acme/widget" GITHUB_SERVER_URL="https://github.com" \
    PREDICATE_OUT="$pred" SUBJECT_OUT="$subj" \
    "${REPO_ROOT}/scripts/build-predicate.sh" || return 1

  assert_valid_json "$(cat "$pred")" "predicate must be valid JSON" || return 1
  assert_equal "1.0" "$(jq -r '.schema_version' "$pred")" "branch-protection schema_version" || return 1
  assert_equal "RepositoryBranchProtection" "$(jq -r '.subject_type' "$pred")" "subject_type" || return 1
  assert_equal "2" "$(jq -r '.summary.protected_branch_count' "$pred")" "protected branch count" || return 1
  assert_equal "1" "$(jq -r '.summary.ruleset_count' "$pred")" "ruleset count" || return 1
  assert_equal "2" "$(jq '.branches | length' "$pred")" "two normalized branches" || return 1

  local main
  main="$(jq -c '.branches[] | select(.name=="main")' "$pred")"
  assert_equal "true" "$(printf '%s' "$main" | jq -r '.required_pull_request_reviews.require_code_owner_reviews')" "main requires code owner reviews" || return 1
  assert_equal "true" "$(printf '%s' "$main" | jq -r '.code_owner_review_required.via_branch_protection')" "main code-owner via branch protection" || return 1
  assert_json_equal '["ci/build"]' "$(printf '%s' "$main" | jq -c '.required_status_checks.checks')" "required checks normalized from contexts" || return 1
  assert_equal "501" "$(jq -r '.rulesets[0].id' "$pred")" "ruleset id carried through" || return 1
  assert_equal "1.0.0" "$(jq -r '.raw_snapshot.schema_version' "$pred")" "raw_snapshot is always embedded" || return 1

  # For branch protection, the subject file is the full collector snapshot.
  assert_equal "1.0.0" "$(jq -r '.schema_version' "$subj")" "subject is the snapshot document"
}

run_test test_pull_request_merge_predicate_and_subject
run_test test_branch_protection_predicate_and_subject

report_results
