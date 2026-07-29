#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/build-predicate.sh: shapes both collector outputs into the
# unified git-commit predicate and its merge-commit-identity subject file.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

test_git_commit_predicate_and_subject() {
  local pr_raw bp_raw pred subj
  pr_raw="${WORK}/raw-pr.json"; bp_raw="${WORK}/raw-bp.json"
  pred="${WORK}/pred.json"; subj="${WORK}/subj.json"

  GITHUB_TOKEN="t" GITHUB_REPOSITORY="acme/widget" GITHUB_SERVER_URL="https://github.com" \
    GITHUB_RUN_ID="5" PR_NUMBER="7" \
    MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-success.json" \
    "${REPO_ROOT}/scripts/pull-request-merge/collect-pr-merge.sh" > "$pr_raw" || return 1

  GITHUB_TOKEN="t" GITHUB_REPOSITORY="acme/widget" \
    MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/full-success.json" \
    env -u GH_OWNER -u GH_REPO "${REPO_ROOT}/scripts/branch-protection/collect-settings-snapshot.sh" > "$bp_raw" || return 1

  PR_RAW_SNAPSHOT_FILE="$pr_raw" BP_RAW_SNAPSHOT_FILE="$bp_raw" \
    GITHUB_REPOSITORY="acme/widget" GITHUB_SERVER_URL="https://github.com" \
    PREDICATE_OUT="$pred" SUBJECT_OUT="$subj" \
    "${REPO_ROOT}/scripts/build-predicate.sh" || return 1

  assert_valid_json "$(cat "$pred")" "predicate must be valid JSON" || return 1

  # Top-level envelope
  assert_equal "1.0.0" "$(jq -r '.schema_version' "$pred")" "top-level schema_version" || return 1
  assert_equal "GitCommit" "$(jq -r '.subject_type' "$pred")" "top-level subject_type" || return 1
  assert_equal "https://jfrog.com/evidence/git-commit/v1" "$(jq -r '.predicate_type' "$pred")" "top-level predicate_type" || return 1

  # Inner envelopes are stripped from both sections.
  assert_equal "null" "$(jq -r '.pull_request_merge.schema_version // "null"' "$pred")" "no inner PR schema_version" || return 1
  assert_equal "null" "$(jq -r '.branch_protection.predicate_type // "null"' "$pred")" "no inner BP predicate_type" || return 1

  # pull_request_merge section
  assert_equal "mergesha" "$(jq -r '.pull_request_merge.merge.merge_commit_sha' "$pred")" "merge commit carried through" || return 1
  assert_equal "2" "$(jq '.pull_request_merge.approvers | length' "$pred")" "approvers carried through" || return 1
  assert_equal "2" "$(jq '.pull_request_merge.commit_signatures | length' "$pred")" "commit_signatures carried through" || return 1
  assert_equal "false" "$(jq -r '.pull_request_merge.all_commits_verified' "$pred")" "all_commits_verified carried through" || return 1

  # branch_protection section
  assert_equal "2" "$(jq -r '.branch_protection.summary.protected_branch_count' "$pred")" "protected branch count" || return 1
  assert_equal "1" "$(jq -r '.branch_protection.summary.ruleset_count' "$pred")" "ruleset count" || return 1
  assert_equal "2" "$(jq '.branch_protection.branches | length' "$pred")" "two normalized branches" || return 1
  assert_equal "501" "$(jq -r '.branch_protection.rulesets[0].id' "$pred")" "ruleset id carried through" || return 1
  assert_equal "1.0.0" "$(jq -r '.branch_protection.raw_snapshot.schema_version' "$pred")" "raw_snapshot embedded under branch_protection" || return 1

  local main
  main="$(jq -c '.branch_protection.branches[] | select(.name=="main")' "$pred")"
  assert_equal "true" "$(printf '%s' "$main" | jq -r '.required_pull_request_reviews.require_code_owner_reviews')" "main requires code owner reviews" || return 1
  assert_json_equal '["ci/build"]' "$(printf '%s' "$main" | jq -c '.required_status_checks.checks')" "required checks normalized from contexts" || return 1

  # Merge-commit identity subject
  assert_equal "mergesha" "$(jq -r '.merge_commit_sha' "$subj")" "subject merge_commit_sha" || return 1
  assert_equal "headsha" "$(jq -r '.head_sha' "$subj")" "subject head_sha" || return 1
  assert_equal "7" "$(jq -r '.pr_number' "$subj")" "subject pr_number"
}

run_test test_git_commit_predicate_and_subject

report_results
