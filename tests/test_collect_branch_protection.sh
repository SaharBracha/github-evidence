#!/usr/bin/env bash
# Tests for scripts/collect-branch-protection.sh against fixture-driven mock responses.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GH_OWNER="acme"
export GH_REPO="widget"

collect_branch_protection() {
  MOCK_CURL_FIXTURE="$1" "${REPO_ROOT}/scripts/collect-branch-protection.sh"
}

test_collects_full_protection_rules_and_rulesets() {
  local output
  output="$(collect_branch_protection "${TESTS_DIR}/fixtures/full-success.json")"
  assert_valid_json "$output" "collector must print valid JSON" || return 1
  assert_equal "2" "$(printf '%s' "$output" | jq -r '.protected_branches.data | length')" "should list both protected branches" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.branches.main.protection.status')" "main protection should be collected" || return 1
  assert_equal "true" "$(printf '%s' "$output" | jq -r '.branches.main.protection.data.required_pull_request_reviews.require_code_owner_reviews')" "main should require code owner reviews" || return 1
  assert_equal "false" "$(printf '%s' "$output" | jq -r '.branches.release.protection.data.required_pull_request_reviews.require_code_owner_reviews')" "release should not require code owner reviews" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.rulesets.status')" "rulesets list should be collected" || return 1
  assert_equal "501" "$(printf '%s' "$output" | jq -r '.ruleset_details."501".data.id')" "ruleset detail should be fetched for each listed ruleset id"
}

test_missing_permission_reports_unavailable_without_dropping_branch_list() {
  local output
  output="$(collect_branch_protection "${TESTS_DIR}/fixtures/restricted-branch-protection.json")"
  assert_equal "1" "$(printf '%s' "$output" | jq -r '.protected_branches.data | length')" "branch listing itself should still succeed" || return 1
  assert_equal "unavailable" "$(printf '%s' "$output" | jq -r '.branches.main.protection.status')" "a 403 on protection detail must be unavailable, not empty" || return 1
  assert_equal "collected" "$(printf '%s' "$output" | jq -r '.branches.main.effective_rules.status')" "effective rules can still succeed even if the classic protection endpoint is forbidden" || return 1
  assert_equal "unavailable" "$(printf '%s' "$output" | jq -r '.rulesets.status')" "a 404 on rulesets must be unavailable, not an empty list"
}

run_test test_collects_full_protection_rules_and_rulesets
run_test test_missing_permission_reports_unavailable_without_dropping_branch_list

report_results
