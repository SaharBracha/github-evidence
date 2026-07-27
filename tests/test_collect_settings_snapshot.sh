#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# End-to-end test for scripts/branch-protection/collect-settings-snapshot.sh: runs the real
# orchestrator (which shells out to the three collector scripts) against the
# mock GitHub API and checks the printed document is a single valid JSON
# document (no log markers) with the expected schema and computed correlation.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GITHUB_REPOSITORY="acme/widget"
unset GH_OWNER GH_REPO

snapshot() {
  MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/full-success.json" "${REPO_ROOT}/scripts/branch-protection/collect-settings-snapshot.sh"
}

test_prints_one_valid_document_without_markers() {
  local body
  body="$(snapshot)" || return 1
  assert_valid_json "$body" "output must be a single valid JSON document" || return 1
  assert_equal "0" "$(printf '%s\n' "$body" | grep -c 'SETTINGS_SNAPSHOT_')" "no log markers should be printed" || return 1
  assert_equal "1.0.0" "$(printf '%s' "$body" | jq -r '.schema_version')" "schema_version should be present and stable" || return 1
  assert_equal "acme/widget" "$(printf '%s' "$body" | jq -r '.repository.full_name')" "repository identity from GITHUB_REPOSITORY" || return 1
  assert_equal "collected" "$(printf '%s' "$body" | jq -r '.sections.branch_protection.protected_branches.status')" "branch protection section present" || return 1
  assert_equal "collected" "$(printf '%s' "$body" | jq -r '.sections.code_owners.file.status')" "code owners section present" || return 1
  assert_equal "collected" "$(printf '%s' "$body" | jq -r '.sections.repository_access.repository.status')" "repository access section present"
}

test_code_owner_enforcement_correlation_matches_per_branch_policy() {
  local body
  body="$(snapshot)" || return 1
  assert_equal "true" "$(printf '%s' "$body" | jq -r '.sections.code_owner_enforcement.has_codeowners_file')" "CODEOWNERS file was found" || return 1
  assert_equal "false" "$(printf '%s' "$body" | jq -r '.sections.code_owner_enforcement.codeowners_validation_errors_present')" "no validation errors in fixture" || return 1

  local main_entry release_entry
  main_entry="$(printf '%s' "$body" | jq -c '.sections.code_owner_enforcement.per_branch[] | select(.branch == "main")')"
  release_entry="$(printf '%s' "$body" | jq -c '.sections.code_owner_enforcement.per_branch[] | select(.branch == "release")')"
  assert_equal "true" "$(printf '%s' "$main_entry" | jq -r '.require_code_owner_reviews_via_branch_protection')" "main requires code owner review via branch protection" || return 1
  assert_equal "true" "$(printf '%s' "$main_entry" | jq -r '.require_code_owner_review_via_rules')" "main also requires it via rules" || return 1
  assert_equal "false" "$(printf '%s' "$release_entry" | jq -r '.require_code_owner_reviews_via_branch_protection')" "release does not require code owner review"
}

run_test test_prints_one_valid_document_without_markers
run_test test_code_owner_enforcement_correlation_matches_per_branch_policy

report_results
